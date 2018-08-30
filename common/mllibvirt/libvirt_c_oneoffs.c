/* OCaml bindings for libvirt.
 * (C) Copyright 2007-2017 Richard W.M. Jones, Red Hat Inc.
 * https://libvirt.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 */

/* Please read libvirt/README file. */

#ifdef __GNUC__
#pragma GCC diagnostic ignored "-Wmissing-prototypes"
#endif

/*----------------------------------------------------------------------*/

CAMLprim value
ocaml_libvirt_get_version (value driverv, value unit)
{
  CAMLparam2 (driverv, unit);
  CAMLlocal1 (rv);
  const char *driver = Optstring_val (driverv);
  unsigned long libVer, typeVer = 0, *typeVer_ptr;
  int r;

  typeVer_ptr = driver ? &typeVer : NULL;
  NONBLOCKING (r = virGetVersion (&libVer, driver, typeVer_ptr));
  CHECK_ERROR (r == -1, "virGetVersion");

  rv = caml_alloc_tuple (2);
  Store_field (rv, 0, Val_int (libVer));
  Store_field (rv, 1, Val_int (typeVer));
  CAMLreturn (rv);
}

/*----------------------------------------------------------------------*/

/* Connection object. */

CAMLprim value
ocaml_libvirt_connect_open (value namev, value unit)
{
  CAMLparam2 (namev, unit);
  CAMLlocal1 (rv);
  const char *name = Optstring_val (namev);
  virConnectPtr conn;

  NONBLOCKING (conn = virConnectOpen (name));
  CHECK_ERROR (!conn, "virConnectOpen");

  rv = Val_connect (conn);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_open_readonly (value namev, value unit)
{
  CAMLparam2 (namev, unit);
  CAMLlocal1 (rv);
  const char *name = Optstring_val (namev);
  virConnectPtr conn;

  NONBLOCKING (conn = virConnectOpenReadOnly (name));
  CHECK_ERROR (!conn, "virConnectOpen");

  rv = Val_connect (conn);

  CAMLreturn (rv);
}

/* Helper struct holding data needed for the helper C authentication
 * callback (which will call the actual OCaml callback).
 */
struct ocaml_auth_callback_data {
  value *fvp;                  /* The OCaml auth callback. */
};

static int
_ocaml_auth_callback (virConnectCredentialPtr cred, unsigned int ncred, void *cbdata)
{
  CAMLparam0 ();
  CAMLlocal4 (listv, elemv, rv, v);
  struct ocaml_auth_callback_data *s = cbdata;
  int i, len;

  listv = Val_emptylist;
  for (i = ncred - 1; i >= 0; --i) {
    elemv = caml_alloc (2, 0);
    Store_field (elemv, 0, Val_virconnectcredential (&cred[i]));
    Store_field (elemv, 1, listv);
    listv = elemv;
  }

  /* Call the auth callback. */
  rv = caml_callback_exn (*s->fvp, listv);
  if (Is_exception_result (rv)) {
    /* The callback raised an exception, so return an error. */
    CAMLreturnT (int, -1);
  }

  len = _list_length (rv);
  if (len != (int) ncred) {
    /* The callback did not return the same number of results as the
     * credentials.
     */
    CAMLreturnT (int, -1);
  }

  for (i = 0; rv != Val_emptylist; rv = Field (rv, 1), ++i) {
    virConnectCredentialPtr c = &cred[i];
    elemv = Field (rv, 0);
    if (elemv == Val_int (0)) {
      c->result = NULL;
      c->resultlen = 0;
    } else {
      v = Field (elemv, 0);
      len = caml_string_length (v);
      c->result = malloc (len + 1);
      if (c->result == NULL)
        CAMLreturnT (int, -1);
      memcpy (c->result, String_val (v), len);
      c->result[len] = '\0';
      c->resultlen = len;
    }
  }

  CAMLreturnT (int, 0);
}

static virConnectPtr
_ocaml_libvirt_connect_open_auth_common (value namev, value authv, int flags)
{
  CAMLparam2 (namev, authv);
  CAMLlocal2 (listv, fv);
  virConnectPtr conn;
  virConnectAuth auth;
  struct ocaml_auth_callback_data data;
  int i;
  char *name = NULL;

  /* Keep a copy of the 'namev' string, as its value could move around
   * when calling other OCaml code that allocates memory.
   */
  if (namev != Val_int (0)) {  /* Some string */
    name = strdup (String_val (Field (namev, 0)));
    if (name == NULL)
      caml_raise_out_of_memory ();
  }

  fv = Field (authv, 1);
  data.fvp = &fv;

  listv = Field (authv, 0);
  auth.ncredtype = _list_length (listv);
  auth.credtype = malloc (sizeof (int) * auth.ncredtype);
  if (auth.credtype == NULL)
    caml_raise_out_of_memory ();
  for (i = 0; listv != Val_emptylist; listv = Field (listv, 1), ++i) {
    auth.credtype[i] = Int_val (Field (listv, 0)) + 1;
  }
  auth.cb = &_ocaml_auth_callback;
  auth.cbdata = &data;

  /* Call virConnectOpenAuth directly, without using the NONBLOCKING
   * macro, as this will indeed call ocaml_* APIs, and run OCaml code.
   */
  conn = virConnectOpenAuth (name, &auth, flags);
  free (auth.credtype);
  free (name);
  CHECK_ERROR (!conn, "virConnectOpenAuth");

  CAMLreturnT (virConnectPtr, conn);
}

CAMLprim value
ocaml_libvirt_connect_open_auth (value namev, value authv)
{
  CAMLparam2 (namev, authv);
  CAMLlocal1 (rv);
  virConnectPtr conn;

  conn = _ocaml_libvirt_connect_open_auth_common (namev, authv, 0);
  rv = Val_connect (conn);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_open_auth_readonly (value namev, value authv)
{
  CAMLparam2 (namev, authv);
  CAMLlocal1 (rv);
  virConnectPtr conn;

  conn = _ocaml_libvirt_connect_open_auth_common (namev, authv, VIR_CONNECT_RO);
  rv = Val_connect (conn);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_get_version (value connv)
{
  CAMLparam1 (connv);
  virConnectPtr conn = Connect_val (connv);
  unsigned long hvVer;
  int r;

  NONBLOCKING (r = virConnectGetVersion (conn, &hvVer));
  CHECK_ERROR (r == -1, "virConnectGetVersion");

  CAMLreturn (Val_int (hvVer));
}

CAMLprim value
ocaml_libvirt_connect_get_max_vcpus (value connv, value typev)
{
  CAMLparam2 (connv, typev);
  virConnectPtr conn = Connect_val (connv);
  const char *type = Optstring_val (typev);
  int r;

  NONBLOCKING (r = virConnectGetMaxVcpus (conn, type));
  CHECK_ERROR (r == -1, "virConnectGetMaxVcpus");

  CAMLreturn (Val_int (r));
}

CAMLprim value
ocaml_libvirt_connect_get_node_info (value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);
  virConnectPtr conn = Connect_val (connv);
  virNodeInfo info;
  int r;

  NONBLOCKING (r = virNodeGetInfo (conn, &info));
  CHECK_ERROR (r == -1, "virNodeGetInfo");

  rv = caml_alloc (8, 0);
  v = caml_copy_string (info.model); Store_field (rv, 0, v);
  v = caml_copy_int64 (info.memory); Store_field (rv, 1, v);
  Store_field (rv, 2, Val_int (info.cpus));
  Store_field (rv, 3, Val_int (info.mhz));
  Store_field (rv, 4, Val_int (info.nodes));
  Store_field (rv, 5, Val_int (info.sockets));
  Store_field (rv, 6, Val_int (info.cores));
  Store_field (rv, 7, Val_int (info.threads));

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_node_get_free_memory (value connv)
{
  CAMLparam1 (connv);
  CAMLlocal1 (rv);
  virConnectPtr conn = Connect_val (connv);
  unsigned long long r;

  NONBLOCKING (r = virNodeGetFreeMemory (conn));
  CHECK_ERROR (r == 0, "virNodeGetFreeMemory");

  rv = caml_copy_int64 ((int64_t) r);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_node_get_cells_free_memory (value connv,
						  value startv, value maxv)
{
  CAMLparam3 (connv, startv, maxv);
  CAMLlocal2 (rv, iv);
  virConnectPtr conn = Connect_val (connv);
  int start = Int_val (startv);
  int max = Int_val (maxv);
  int r, i;
  unsigned long long *freemems;

  freemems = malloc(sizeof (*freemems) * max);
  if (freemems == NULL)
    caml_raise_out_of_memory ();

  NONBLOCKING (r = virNodeGetCellsFreeMemory (conn, freemems, start, max));
  CHECK_ERROR_CLEANUP (r == -1, free (freemems), "virNodeGetCellsFreeMemory");

  rv = caml_alloc (r, 0);
  for (i = 0; i < r; ++i) {
    iv = caml_copy_int64 ((int64_t) freemems[i]);
    Store_field (rv, i, iv);
  }
  free (freemems);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_connect_set_keep_alive(value connv,
				     value intervalv, value countv)
{
  CAMLparam3 (connv, intervalv, countv);
  virConnectPtr conn = Connect_val(connv);
  int interval = Int_val(intervalv);
  unsigned int count = Int_val(countv);
  int r;

  NONBLOCKING(r = virConnectSetKeepAlive(conn, interval, count));
  CHECK_ERROR (r == -1, "virConnectSetKeepAlive");

  CAMLreturn(Val_unit);
}

CAMLprim value
ocaml_libvirt_connect_credtypes_from_auth_default (value unitv)
{
  CAMLparam1 (unitv);
  CAMLlocal2 (listv, itemv);
  int i;

  listv = Val_emptylist;

  if (virConnectAuthPtrDefault) {
    for (i = virConnectAuthPtrDefault->ncredtype; i >= 0; --i) {
      const int type = virConnectAuthPtrDefault->credtype[i];
      itemv = caml_alloc (2, 0);
      Store_field (itemv, 0, Val_int (type - 1));
      Store_field (itemv, 1, listv);
      listv = itemv;
    }
  }

  CAMLreturn (listv);
}

CAMLprim value
ocaml_libvirt_connect_call_auth_default_callback (value listv)
{
  CAMLparam1 (listv);
  CAMLlocal5 (credv, retv, elemv, optv, v);
  int i, len, ret;
  const char *str;
  virConnectCredentialPtr creds;

  if (virConnectAuthPtrDefault == NULL
      || virConnectAuthPtrDefault->cb == NULL)
    CAMLreturn (Val_unit);

  len = _list_length (listv);
  creds = calloc (len, sizeof (*creds));
  if (creds == NULL)
    caml_raise_out_of_memory ();
  for (i = 0; listv != Val_emptylist; listv = Field (listv, 1), ++i) {
    virConnectCredentialPtr cred = &creds[i];
    credv = Field (listv, 0);
    cred->type = Int_val (Field (credv, 0)) + 1;
    cred->prompt = strdup (String_val (Field (credv, 1)));
    if (cred->prompt == NULL)
      caml_raise_out_of_memory ();
    str = Optstring_val (Field (credv, 2));
    if (str) {
      cred->challenge = strdup (str);
      if (cred->challenge == NULL)
        caml_raise_out_of_memory ();
    }
    str = Optstring_val (Field (credv, 3));
    if (str) {
      cred->defresult = strdup (str);
      if (cred->defresult == NULL)
        caml_raise_out_of_memory ();
    }
  }

  ret = virConnectAuthPtrDefault->cb (creds, len,
                                      virConnectAuthPtrDefault->cbdata);
  if (ret >= 0) {
    retv = Val_emptylist;
    for (i = len - 1; i >= 0; --i) {
      virConnectCredentialPtr cred = &creds[i];
      elemv = caml_alloc (2, 0);
      if (cred->result != NULL && cred->resultlen > 0) {
        v = caml_alloc_string (cred->resultlen);
        memcpy (String_val (v), cred->result, cred->resultlen);
        optv = caml_alloc (1, 0);
        Store_field (optv, 0, v);
      } else
        optv = Val_int (0);
      Store_field (elemv, 0, optv);
      Store_field (elemv, 1, retv);
      retv = elemv;
    }
  }
  for (i = 0; i < len; ++i) {
    virConnectCredentialPtr cred = &creds[i];
    /* Cast to char *, as the virConnectCredential structs we fill have
     * const char * qualifiers.
     */
    free ((char *) cred->prompt);
    free ((char *) cred->challenge);
    free ((char *) cred->defresult);
  }
  free (creds);

  if (ret < 0)
    caml_failwith ("virConnectAuthPtrDefault callback failed");

  CAMLreturn (retv);
}

CAMLprim value
ocaml_libvirt_connect_get_domain_capabilities (value emulatorbinv, value archv, value machinev, value virttypev, value connv)
{
  CAMLparam5 (emulatorbinv, archv, machinev, virttypev, connv);
  CAMLlocal1 (rv);
  virConnectPtr conn = Connect_val (connv);
  char *r;

  NONBLOCKING (r = virConnectGetDomainCapabilities (conn, Optstring_val (emulatorbinv), Optstring_val (archv), Optstring_val (machinev), Optstring_val (virttypev), 0));
  CHECK_ERROR (r == NULL, "virConnectGetDomainCapabilities");

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_get_id (value domv)
{
  CAMLparam1 (domv);
  virDomainPtr dom = Domain_val (domv);
  unsigned int r;

  NONBLOCKING (r = virDomainGetID (dom));
  /* In theory this could return -1 on error, but in practice
   * libvirt never does this unless you call it with a corrupted
   * or NULL dom object.  So ignore errors here.
   */

  CAMLreturn (Val_int ((int) r));
}

CAMLprim value
ocaml_libvirt_domain_get_max_memory (value domv)
{
  CAMLparam1 (domv);
  CAMLlocal1 (rv);
  virDomainPtr dom = Domain_val (domv);
  unsigned long r;

  NONBLOCKING (r = virDomainGetMaxMemory (dom));
  CHECK_ERROR (r == 0 /* [sic] */, "virDomainGetMaxMemory");

  rv = caml_copy_int64 (r);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_set_max_memory (value domv, value memv)
{
  CAMLparam2 (domv, memv);
  virDomainPtr dom = Domain_val (domv);
  unsigned long mem = Int64_val (memv);
  int r;

  NONBLOCKING (r = virDomainSetMaxMemory (dom, mem));
  CHECK_ERROR (r == -1, "virDomainSetMaxMemory");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_set_memory (value domv, value memv)
{
  CAMLparam2 (domv, memv);
  virDomainPtr dom = Domain_val (domv);
  unsigned long mem = Int64_val (memv);
  int r;

  NONBLOCKING (r = virDomainSetMemory (dom, mem));
  CHECK_ERROR (r == -1, "virDomainSetMemory");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_get_info (value domv)
{
  CAMLparam1 (domv);
  CAMLlocal2 (rv, v);
  virDomainPtr dom = Domain_val (domv);
  virDomainInfo info;
  int r;

  NONBLOCKING (r = virDomainGetInfo (dom, &info));
  CHECK_ERROR (r == -1, "virDomainGetInfo");

  rv = caml_alloc (5, 0);
  Store_field (rv, 0, Val_int (info.state)); // These flags are compatible.
  v = caml_copy_int64 (info.maxMem); Store_field (rv, 1, v);
  v = caml_copy_int64 (info.memory); Store_field (rv, 2, v);
  Store_field (rv, 3, Val_int (info.nrVirtCpu));
  v = caml_copy_int64 (info.cpuTime); Store_field (rv, 4, v);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_get_scheduler_type (value domv)
{
  CAMLparam1 (domv);
  CAMLlocal2 (rv, strv);
  virDomainPtr dom = Domain_val (domv);
  char *r;
  int nparams;

  NONBLOCKING (r = virDomainGetSchedulerType (dom, &nparams));
  CHECK_ERROR (!r, "virDomainGetSchedulerType");

  rv = caml_alloc_tuple (2);
  strv = caml_copy_string (r); Store_field (rv, 0, strv);
  free (r);
  Store_field (rv, 1, nparams);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_get_scheduler_parameters (value domv, value nparamsv)
{
  CAMLparam2 (domv, nparamsv);
  CAMLlocal4 (rv, v, v2, v3);
  virDomainPtr dom = Domain_val (domv);
  int nparams = Int_val (nparamsv);
  virSchedParameterPtr params;
  int r, i;

  params = malloc (sizeof (*params) * nparams);
  if (params == NULL)
    caml_raise_out_of_memory ();

  NONBLOCKING (r = virDomainGetSchedulerParameters (dom, params, &nparams));
  CHECK_ERROR_CLEANUP (r == -1, free (params), "virDomainGetSchedulerParameters");

  rv = caml_alloc (nparams, 0);
  for (i = 0; i < nparams; ++i) {
    v = caml_alloc_tuple (2); Store_field (rv, i, v);
    v2 = caml_copy_string (params[i].field); Store_field (v, 0, v2);
    switch (params[i].type) {
    case VIR_DOMAIN_SCHED_FIELD_INT:
      v2 = caml_alloc (1, 0);
      v3 = caml_copy_int32 (params[i].value.i); Store_field (v2, 0, v3);
      break;
    case VIR_DOMAIN_SCHED_FIELD_UINT:
      v2 = caml_alloc (1, 1);
      v3 = caml_copy_int32 (params[i].value.ui); Store_field (v2, 0, v3);
      break;
    case VIR_DOMAIN_SCHED_FIELD_LLONG:
      v2 = caml_alloc (1, 2);
      v3 = caml_copy_int64 (params[i].value.l); Store_field (v2, 0, v3);
      break;
    case VIR_DOMAIN_SCHED_FIELD_ULLONG:
      v2 = caml_alloc (1, 3);
      v3 = caml_copy_int64 (params[i].value.ul); Store_field (v2, 0, v3);
      break;
    case VIR_DOMAIN_SCHED_FIELD_DOUBLE:
      v2 = caml_alloc (1, 4);
      v3 = caml_copy_double (params[i].value.d); Store_field (v2, 0, v3);
      break;
    case VIR_DOMAIN_SCHED_FIELD_BOOLEAN:
      v2 = caml_alloc (1, 5);
      Store_field (v2, 0, Val_int (params[i].value.b));
      break;
    default:
      caml_failwith ((char *)__FUNCTION__);
    }
    Store_field (v, 1, v2);
  }
  free (params);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_set_scheduler_parameters (value domv, value paramsv)
{
  CAMLparam2 (domv, paramsv);
  CAMLlocal1 (v);
  virDomainPtr dom = Domain_val (domv);
  int nparams = Wosize_val (paramsv);
  virSchedParameterPtr params;
  int r, i;
  char *name;

  params = malloc (sizeof (*params) * nparams);
  if (params == NULL)
    caml_raise_out_of_memory ();

  for (i = 0; i < nparams; ++i) {
    v = Field (paramsv, i);	/* Points to the two-element tuple. */
    name = String_val (Field (v, 0));
    strncpy (params[i].field, name, VIR_DOMAIN_SCHED_FIELD_LENGTH);
    params[i].field[VIR_DOMAIN_SCHED_FIELD_LENGTH-1] = '\0';
    v = Field (v, 1);		/* Points to the sched_param_value block. */
    switch (Tag_val (v)) {
    case 0:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_INT;
      params[i].value.i = Int32_val (Field (v, 0));
      break;
    case 1:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_UINT;
      params[i].value.ui = Int32_val (Field (v, 0));
      break;
    case 2:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_LLONG;
      params[i].value.l = Int64_val (Field (v, 0));
      break;
    case 3:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_ULLONG;
      params[i].value.ul = Int64_val (Field (v, 0));
      break;
    case 4:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_DOUBLE;
      params[i].value.d = Double_val (Field (v, 0));
      break;
    case 5:
      params[i].type = VIR_DOMAIN_SCHED_FIELD_BOOLEAN;
      params[i].value.b = Int_val (Field (v, 0));
      break;
    default:
      caml_failwith ((char *)__FUNCTION__);
    }
  }

  NONBLOCKING (r = virDomainSetSchedulerParameters (dom, params, nparams));
  free (params);
  CHECK_ERROR (r == -1, "virDomainSetSchedulerParameters");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_set_vcpus (value domv, value nvcpusv)
{
  CAMLparam2 (domv, nvcpusv);
  virDomainPtr dom = Domain_val (domv);
  int r, nvcpus = Int_val (nvcpusv);

  NONBLOCKING (r = virDomainSetVcpus (dom, nvcpus));
  CHECK_ERROR (r == -1, "virDomainSetVcpus");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_pin_vcpu (value domv, value vcpuv, value cpumapv)
{
  CAMLparam3 (domv, vcpuv, cpumapv);
  virDomainPtr dom = Domain_val (domv);
  int maplen = caml_string_length (cpumapv);
  unsigned char *cpumap = (unsigned char *) String_val (cpumapv);
  int vcpu = Int_val (vcpuv);
  int r;

  NONBLOCKING (r = virDomainPinVcpu (dom, vcpu, cpumap, maplen));
  CHECK_ERROR (r == -1, "virDomainPinVcpu");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_get_vcpus (value domv, value maxinfov, value maplenv)
{
  CAMLparam3 (domv, maxinfov, maplenv);
  CAMLlocal5 (rv, infov, strv, v, v2);
  virDomainPtr dom = Domain_val (domv);
  int maxinfo = Int_val (maxinfov);
  int maplen = Int_val (maplenv);
  virVcpuInfoPtr info;
  unsigned char *cpumaps;
  int r, i;

  info = calloc (maxinfo, sizeof (*info));
  if (info == NULL)
    caml_raise_out_of_memory ();
  cpumaps = calloc (maxinfo * maplen, sizeof (*cpumaps));
  if (cpumaps == NULL) {
    free (info);
    caml_raise_out_of_memory ();
  }

  NONBLOCKING (r = virDomainGetVcpus (dom, info, maxinfo, cpumaps, maplen));
  CHECK_ERROR_CLEANUP (r == -1, free (info); free (cpumaps), "virDomainPinVcpu");

  /* Copy the virVcpuInfo structures. */
  infov = caml_alloc (maxinfo, 0);
  for (i = 0; i < maxinfo; ++i) {
    v2 = caml_alloc (4, 0); Store_field (infov, i, v2);
    Store_field (v2, 0, Val_int (info[i].number));
    Store_field (v2, 1, Val_int (info[i].state));
    v = caml_copy_int64 (info[i].cpuTime); Store_field (v2, 2, v);
    Store_field (v2, 3, Val_int (info[i].cpu));
  }

  /* Copy the bitmap. */
  strv = caml_alloc_string (maxinfo * maplen);
  memcpy (String_val (strv), cpumaps, maxinfo * maplen);

  /* Allocate the tuple and return it. */
  rv = caml_alloc_tuple (3);
  Store_field (rv, 0, Val_int (r)); /* number of CPUs. */
  Store_field (rv, 1, infov);
  Store_field (rv, 2, strv);

  free (info);
  free (cpumaps);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_get_cpu_stats (value domv)
{
  CAMLparam1 (domv);
  CAMLlocal5 (cpustats, param_head, param_node, typed_param, typed_param_value);
  CAMLlocal1 (v);
  virDomainPtr dom = Domain_val (domv);
  virTypedParameterPtr params;
  int r, cpu, ncpus, nparams, i, j, pos;
  int nr_pcpus;

  /* get number of pcpus */
  NONBLOCKING (nr_pcpus = virDomainGetCPUStats(dom, NULL, 0, 0, 0, 0));
  CHECK_ERROR (nr_pcpus < 0, "virDomainGetCPUStats");

  /* get percpu information */
  NONBLOCKING (nparams = virDomainGetCPUStats(dom, NULL, 0, 0, 1, 0));
  CHECK_ERROR (nparams < 0, "virDomainGetCPUStats");

  if ((params = malloc(sizeof(*params) * nparams * 128)) == NULL)
    caml_failwith ("virDomainGetCPUStats: malloc");

  cpustats = caml_alloc (nr_pcpus, 0); /* cpustats: array of params(list of typed_param) */
  cpu = 0;
  while (cpu < nr_pcpus) {
    ncpus = nr_pcpus - cpu > 128 ? 128 : nr_pcpus - cpu;

    NONBLOCKING (r = virDomainGetCPUStats(dom, params, nparams, cpu, ncpus, 0));
    CHECK_ERROR (r < 0, "virDomainGetCPUStats");

    for (i = 0; i < ncpus; i++) {
      /* list of typed_param: single linked list of param_nodes */
      param_head = Val_emptylist; /* param_head: the head param_node of list of typed_param */

      if (params[i * nparams].type == 0) {
        Store_field(cpustats, cpu + i, param_head);
        continue;
      }

      for (j = r - 1; j >= 0; j--) {
        pos = i * nparams + j;
          if (params[pos].type == 0)
            continue;

        param_node = caml_alloc(2, 0); /* param_node: typed_param, next param_node */
        Store_field(param_node, 1, param_head);
        param_head = param_node;

        typed_param = caml_alloc(2, 0); /* typed_param: field name(string), typed_param_value */
        Store_field(param_node, 0, typed_param);
        Store_field(typed_param, 0, caml_copy_string(params[pos].field));

        /* typed_param_value: value with the corresponding type tag */
        switch(params[pos].type) {
        case VIR_TYPED_PARAM_INT:
          typed_param_value = caml_alloc (1, 0);
          v = caml_copy_int32 (params[pos].value.i);
          break;
        case VIR_TYPED_PARAM_UINT:
          typed_param_value = caml_alloc (1, 1);
          v = caml_copy_int32 (params[pos].value.ui);
          break;
        case VIR_TYPED_PARAM_LLONG:
          typed_param_value = caml_alloc (1, 2);
          v = caml_copy_int64 (params[pos].value.l);
          break;
        case VIR_TYPED_PARAM_ULLONG:
          typed_param_value = caml_alloc (1, 3);
          v = caml_copy_int64 (params[pos].value.ul);
          break;
        case VIR_TYPED_PARAM_DOUBLE:
          typed_param_value = caml_alloc (1, 4);
          v = caml_copy_double (params[pos].value.d);
          break;
        case VIR_TYPED_PARAM_BOOLEAN:
          typed_param_value = caml_alloc (1, 5);
          v = Val_bool (params[pos].value.b);
          break;
        case VIR_TYPED_PARAM_STRING:
          typed_param_value = caml_alloc (1, 6);
          v = caml_copy_string (params[pos].value.s);
          free (params[pos].value.s);
          break;
        default:
            /* XXX Memory leak on this path, if there are more
             * VIR_TYPED_PARAM_STRING past this point in the array.
             */
          free (params);
          caml_failwith ("virDomainGetCPUStats: "
                         "unknown parameter type returned");
        }
        Store_field (typed_param_value, 0, v);
        Store_field (typed_param, 1, typed_param_value);
      }
      Store_field (cpustats, cpu + i, param_head);
    }
    cpu += ncpus;
  }
  free(params);
  CAMLreturn (cpustats);
}

value
ocaml_libvirt_domain_get_all_domain_stats (value connv,
                                           value statsv, value flagsv)
{
  CAMLparam3 (connv, statsv, flagsv);
  CAMLlocal5 (rv, dsv, tpv, v, v1);
  CAMLlocal1 (v2);
  virConnectPtr conn = Connect_val (connv);
  virDomainStatsRecordPtr *rstats;
  unsigned int stats = 0, flags = 0;
  int i, j, r;
  unsigned char uuid[VIR_UUID_BUFLEN];

  /* Get stats and flags. */
  for (; statsv != Val_int (0); statsv = Field (statsv, 1)) {
    v = Field (statsv, 0);
    if (v == Val_int (0))
      stats |= VIR_DOMAIN_STATS_STATE;
    else if (v == Val_int (1))
      stats |= VIR_DOMAIN_STATS_CPU_TOTAL;
    else if (v == Val_int (2))
      stats |= VIR_DOMAIN_STATS_BALLOON;
    else if (v == Val_int (3))
      stats |= VIR_DOMAIN_STATS_VCPU;
    else if (v == Val_int (4))
      stats |= VIR_DOMAIN_STATS_INTERFACE;
    else if (v == Val_int (5))
      stats |= VIR_DOMAIN_STATS_BLOCK;
    else if (v == Val_int (6))
      stats |= VIR_DOMAIN_STATS_PERF;
  }
  for (; flagsv != Val_int (0); flagsv = Field (flagsv, 1)) {
    v = Field (flagsv, 0);
    if (v == Val_int (0))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_ACTIVE;
    else if (v == Val_int (1))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_INACTIVE;
    else if (v == Val_int (2))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_OTHER;
    else if (v == Val_int (3))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_PAUSED;
    else if (v == Val_int (4))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_PERSISTENT;
    else if (v == Val_int (5))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_RUNNING;
    else if (v == Val_int (6))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_SHUTOFF;
    else if (v == Val_int (7))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_TRANSIENT;
    else if (v == Val_int (8))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_BACKING;
    else if (v == Val_int (9))
      flags |= VIR_CONNECT_GET_ALL_DOMAINS_STATS_ENFORCE_STATS;
  }

  NONBLOCKING (r = virConnectGetAllDomainStats (conn, stats, &rstats, flags));
  CHECK_ERROR (r == -1, "virConnectGetAllDomainStats");

  rv = caml_alloc (r, 0);       /* domain_stats_record array. */
  for (i = 0; i < r; ++i) {
    dsv = caml_alloc (2, 0);    /* domain_stats_record */

    /* Libvirt returns something superficially resembling a
     * virDomainPtr, but it's not a real virDomainPtr object
     * (eg. dom->id == -1, and its refcount is wrong).  The only thing
     * we can safely get from it is the UUID.
     */
    v = caml_alloc_string (VIR_UUID_BUFLEN);
    virDomainGetUUID (rstats[i]->dom, uuid);
    memcpy (String_val (v), uuid, VIR_UUID_BUFLEN);
    Store_field (dsv, 0, v);

    tpv = caml_alloc (rstats[i]->nparams, 0); /* typed_param array */
    for (j = 0; j < rstats[i]->nparams; ++j) {
      v2 = caml_alloc (2, 0);   /* typed_param: field name, value */
      Store_field (v2, 0, caml_copy_string (rstats[i]->params[j].field));

      switch (rstats[i]->params[j].type) {
      case VIR_TYPED_PARAM_INT:
        v1 = caml_alloc (1, 0);
        v = caml_copy_int32 (rstats[i]->params[j].value.i);
        break;
      case VIR_TYPED_PARAM_UINT:
        v1 = caml_alloc (1, 1);
        v = caml_copy_int32 (rstats[i]->params[j].value.ui);
        break;
      case VIR_TYPED_PARAM_LLONG:
        v1 = caml_alloc (1, 2);
        v = caml_copy_int64 (rstats[i]->params[j].value.l);
        break;
      case VIR_TYPED_PARAM_ULLONG:
        v1 = caml_alloc (1, 3);
        v = caml_copy_int64 (rstats[i]->params[j].value.ul);
        break;
      case VIR_TYPED_PARAM_DOUBLE:
        v1 = caml_alloc (1, 4);
        v = caml_copy_double (rstats[i]->params[j].value.d);
        break;
      case VIR_TYPED_PARAM_BOOLEAN:
        v1 = caml_alloc (1, 5);
        v = Val_bool (rstats[i]->params[j].value.b);
        break;
      case VIR_TYPED_PARAM_STRING:
        v1 = caml_alloc (1, 6);
        v = caml_copy_string (rstats[i]->params[j].value.s);
        break;
      default:
        virDomainStatsRecordListFree (rstats);
        caml_failwith ("virConnectGetAllDomainStats: "
                       "unknown parameter type returned");
      }
      Store_field (v1, 0, v);

      Store_field (v2, 1, v1);
      Store_field (tpv, j, v2);
    }

    Store_field (dsv, 1, tpv);
    Store_field (rv, i, dsv);
  }

  virDomainStatsRecordListFree (rstats);
  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_migrate_native (value domv, value dconnv, value flagsv, value optdnamev, value opturiv, value optbandwidthv, value unitv)
{
  CAMLparam5 (domv, dconnv, flagsv, optdnamev, opturiv);
  CAMLxparam2 (optbandwidthv, unitv);
  CAMLlocal2 (flagv, rv);
  virDomainPtr dom = Domain_val (domv);
  virConnectPtr dconn = Connect_val (dconnv);
  int flags = 0;
  const char *dname = Optstring_val (optdnamev);
  const char *uri = Optstring_val (opturiv);
  unsigned long bandwidth;
  virDomainPtr r;

  /* Iterate over the list of flags. */
  for (; flagsv != Val_int (0); flagsv = Field (flagsv, 1))
    {
      flagv = Field (flagsv, 0);
      if (flagv == Val_int (0))
	flags |= VIR_MIGRATE_LIVE;
    }

  if (optbandwidthv == Val_int (0)) /* None */
    bandwidth = 0;
  else				/* Some bandwidth */
    bandwidth = Int_val (Field (optbandwidthv, 0));

  NONBLOCKING (r = virDomainMigrate (dom, dconn, flags, dname, uri, bandwidth));
  CHECK_ERROR (!r, "virDomainMigrate");

  rv = Val_domain (r, dconnv);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_migrate_bytecode (value *argv, int argn)
{
  return ocaml_libvirt_domain_migrate_native (argv[0], argv[1], argv[2],
					      argv[3], argv[4], argv[5],
					      argv[6]);
}

CAMLprim value
ocaml_libvirt_domain_block_stats (value domv, value pathv)
{
  CAMLparam2 (domv, pathv);
  CAMLlocal2 (rv,v);
  virDomainPtr dom = Domain_val (domv);
  char *path = String_val (pathv);
  struct _virDomainBlockStats stats;
  int r;

  NONBLOCKING (r = virDomainBlockStats (dom, path, &stats, sizeof stats));
  CHECK_ERROR (r == -1, "virDomainBlockStats");

  rv = caml_alloc (5, 0);
  v = caml_copy_int64 (stats.rd_req); Store_field (rv, 0, v);
  v = caml_copy_int64 (stats.rd_bytes); Store_field (rv, 1, v);
  v = caml_copy_int64 (stats.wr_req); Store_field (rv, 2, v);
  v = caml_copy_int64 (stats.wr_bytes); Store_field (rv, 3, v);
  v = caml_copy_int64 (stats.errs); Store_field (rv, 4, v);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_interface_stats (value domv, value pathv)
{
  CAMLparam2 (domv, pathv);
  CAMLlocal2 (rv,v);
  virDomainPtr dom = Domain_val (domv);
  char *path = String_val (pathv);
  struct _virDomainInterfaceStats stats;
  int r;

  NONBLOCKING (r = virDomainInterfaceStats (dom, path, &stats, sizeof stats));
  CHECK_ERROR (r == -1, "virDomainInterfaceStats");

  rv = caml_alloc (8, 0);
  v = caml_copy_int64 (stats.rx_bytes); Store_field (rv, 0, v);
  v = caml_copy_int64 (stats.rx_packets); Store_field (rv, 1, v);
  v = caml_copy_int64 (stats.rx_errs); Store_field (rv, 2, v);
  v = caml_copy_int64 (stats.rx_drop); Store_field (rv, 3, v);
  v = caml_copy_int64 (stats.tx_bytes); Store_field (rv, 4, v);
  v = caml_copy_int64 (stats.tx_packets); Store_field (rv, 5, v);
  v = caml_copy_int64 (stats.tx_errs); Store_field (rv, 6, v);
  v = caml_copy_int64 (stats.tx_drop); Store_field (rv, 7, v);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_domain_block_peek_native (value domv, value pathv, value offsetv, value sizev, value bufferv, value boffv)
{
  CAMLparam5 (domv, pathv, offsetv, sizev, bufferv);
  CAMLxparam1 (boffv);
  virDomainPtr dom = Domain_val (domv);
  const char *path = String_val (pathv);
  unsigned long long offset = Int64_val (offsetv);
  size_t size = Int_val (sizev);
  char *buffer = String_val (bufferv);
  int boff = Int_val (boffv);
  int r;

  /* Check that the return buffer is big enough. */
  if (caml_string_length (bufferv) < boff + size)
    caml_failwith ("virDomainBlockPeek: return buffer too short");

  /* NB. not NONBLOCKING because buffer might move (XXX) */
  r = virDomainBlockPeek (dom, path, offset, size, buffer+boff, 0);
  CHECK_ERROR (r == -1, "virDomainBlockPeek");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_block_peek_bytecode (value *argv, int argn)
{
  return ocaml_libvirt_domain_block_peek_native (argv[0], argv[1], argv[2],
                                                 argv[3], argv[4], argv[5]);
}

CAMLprim value
ocaml_libvirt_domain_memory_peek_native (value domv, value flagsv, value offsetv, value sizev, value bufferv, value boffv)
{
  CAMLparam5 (domv, flagsv, offsetv, sizev, bufferv);
  CAMLxparam1 (boffv);
  CAMLlocal1 (flagv);
  virDomainPtr dom = Domain_val (domv);
  int flags = 0;
  unsigned long long offset = Int64_val (offsetv);
  size_t size = Int_val (sizev);
  char *buffer = String_val (bufferv);
  int boff = Int_val (boffv);
  int r;

  /* Check that the return buffer is big enough. */
  if (caml_string_length (bufferv) < boff + size)
    caml_failwith ("virDomainMemoryPeek: return buffer too short");

  /* Do flags. */
  for (; flagsv != Val_int (0); flagsv = Field (flagsv, 1))
    {
      flagv = Field (flagsv, 0);
      if (flagv == Val_int (0))
        flags |= VIR_MEMORY_VIRTUAL;
    }

  /* NB. not NONBLOCKING because buffer might move (XXX) */
  r = virDomainMemoryPeek (dom, offset, size, buffer+boff, flags);
  CHECK_ERROR (r == -1, "virDomainMemoryPeek");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_domain_memory_peek_bytecode (value *argv, int argn)
{
  return ocaml_libvirt_domain_memory_peek_native (argv[0], argv[1], argv[2],
                                                  argv[3], argv[4], argv[5]);
}

CAMLprim value
ocaml_libvirt_domain_get_xml_desc_flags (value domv, value flagsv)
{
  CAMLparam2 (domv, flagsv);
  CAMLlocal2 (rv, flagv);
  virDomainPtr dom = Domain_val (domv);
  int flags = 0;
  char *r;

  /* Do flags. */
  for (; flagsv != Val_int (0); flagsv = Field (flagsv, 1))
    {
      flagv = Field (flagsv, 0);
      if (flagv == Val_int (0))
        flags |= VIR_DOMAIN_XML_SECURE;
      else if (flagv == Val_int (1))
        flags |= VIR_DOMAIN_XML_INACTIVE;
      else if (flagv == Val_int (2))
        flags |= VIR_DOMAIN_XML_UPDATE_CPU;
      else if (flagv == Val_int (3))
        flags |= VIR_DOMAIN_XML_MIGRATABLE;
    }

  NONBLOCKING (r = virDomainGetXMLDesc (dom, flags));
  CHECK_ERROR (!r, "virDomainGetXMLDesc");

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
}

/*----------------------------------------------------------------------*/

/* Domain events */

CAMLprim value
ocaml_libvirt_event_register_default_impl (value unitv)
{
  CAMLparam1 (unitv);

  /* arg is of type unit = void */
  int r;

  NONBLOCKING (r = virEventRegisterDefaultImpl ());
  /* must be called before connection, therefore we can't use CHECK_ERROR */
  if (r == -1) caml_failwith("virEventRegisterDefaultImpl");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_event_run_default_impl (value unitv)
{
  CAMLparam1 (unitv);

  /* arg is of type unit = void */
  int r;

  NONBLOCKING (r = virEventRunDefaultImpl ());
  if (r == -1) caml_failwith("virEventRunDefaultImpl");

  CAMLreturn (Val_unit);
}

/* We register a single C callback function for every distinct
   callback signature. We encode the signature itself in the function
   name and also in the name of the assocated OCaml callback
   e.g.:
      a C function called
         i_i64_s_callback(virConnectPtr conn,
			  virDomainPtr dom,
			  int x,
			  long y,
			  char *z,
			  void *opaque)
      would correspond to an OCaml callback
         Libvirt.i_i64_s_callback :
	   int64 -> [`R] Domain.t -> int -> int64 -> string option -> unit
      where the initial int64 is a unique ID used by the OCaml to
      dispatch to the specific OCaml closure and stored by libvirt
      as the "opaque" data. */

/* Every one of the callbacks starts with a DOMAIN_CALLBACK_BEGIN(NAME)
   where NAME is the string name of the OCaml callback registered
   in libvirt.ml. */
#define DOMAIN_CALLBACK_BEGIN(NAME)                              \
  value connv, domv, callback_id, result;                        \
  connv = domv = callback_id = result = Val_int(0);              \
  static value *callback = NULL;                                 \
  caml_leave_blocking_section();                                 \
  if (callback == NULL)                                          \
    callback = caml_named_value(NAME);                           \
  if (callback == NULL)                                          \
    abort(); /* C code out of sync with OCaml code */            \
  if ((virDomainRef(dom) == -1) || (virConnectRef(conn) == -1))  \
    abort(); /* should never happen in practice? */              \
                                                                 \
  Begin_roots4(connv, domv, callback_id, result);                \
  connv = Val_connect(conn);                                     \
  domv = Val_domain(dom, connv);                                 \
  callback_id = caml_copy_int64(*(long *)opaque);

/* Every one of the callbacks ends with a CALLBACK_END */
#define DOMAIN_CALLBACK_END                                      \
  (void) caml_callback3(*callback, callback_id, domv, result);   \
  End_roots();                                                   \
  caml_enter_blocking_section();


static void
i_i_callback(virConnectPtr conn,
	     virDomainPtr dom,
	     int x,
	     int y,
	     void * opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.i_i_callback")
  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(x));
  Store_field(result, 1, Val_int(y));
  DOMAIN_CALLBACK_END
}

static void
u_callback(virConnectPtr conn,
	   virDomainPtr dom,
	   void *opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.u_callback")
  result = Val_int(0); /* () */
  DOMAIN_CALLBACK_END
}

static void
i64_callback(virConnectPtr conn,
	     virDomainPtr dom,
	     long long int64,
	     void *opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.i64_callback")
  result = caml_copy_int64(int64);
  DOMAIN_CALLBACK_END
}

static void
i_callback(virConnectPtr conn,
	   virDomainPtr dom,
	   int x,
	   void *opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.i_callback")
  result = Val_int(x);
  DOMAIN_CALLBACK_END
}

static void
s_i_callback(virConnectPtr conn,
	     virDomainPtr dom,
	     char *x,
	     int y,
	     void * opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.s_i_callback")
  result = caml_alloc_tuple(2);
  Store_field(result, 0, 
	      Val_opt(x, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1, Val_int(y));
  DOMAIN_CALLBACK_END
}

static void
s_i_i_callback(virConnectPtr conn,
	       virDomainPtr dom,
	       char *x,
	       int y,
	       int z,
	       void * opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.s_i_i_callback")
  result = caml_alloc_tuple(3);
  Store_field(result, 0, 
	      Val_opt(x, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1, Val_int(y));
  Store_field(result, 2, Val_int(z));
  DOMAIN_CALLBACK_END
}

static void
s_s_i_callback(virConnectPtr conn,
	       virDomainPtr dom,
	       char *x,
	       char *y,
	       int z,
	       void *opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.s_s_i_callback")
  result = caml_alloc_tuple(3);
  Store_field(result, 0, 
	      Val_opt(x, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1,
	      Val_opt(y, (Val_ptr_t) caml_copy_string));
  Store_field(result, 2, Val_int(z));
  DOMAIN_CALLBACK_END
}

static void
s_s_i_s_callback(virConnectPtr conn,
		 virDomainPtr dom,
		 char *x,
		 char *y,
		 int z,
		 char *a,
		 void *opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.s_s_i_s_callback")
  result = caml_alloc_tuple(4);
  Store_field(result, 0, 
	      Val_opt(x, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1,
	      Val_opt(y, (Val_ptr_t) caml_copy_string));
  Store_field(result, 2, Val_int(z));
  Store_field(result, 3,
	      Val_opt(a, (Val_ptr_t) caml_copy_string));
  DOMAIN_CALLBACK_END
}

static void
s_s_s_i_callback(virConnectPtr conn,
		 virDomainPtr dom,
		 char * x,
		 char * y,
		 char * z,
		 int a,
		 void * opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.s_s_s_i_callback")
  result = caml_alloc_tuple(4);
  Store_field(result, 0,
	      Val_opt(x, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1,
              Val_opt(y, (Val_ptr_t) caml_copy_string));
  Store_field(result, 2,
              Val_opt(z, (Val_ptr_t) caml_copy_string));
  Store_field(result, 3, Val_int(a));
  DOMAIN_CALLBACK_END
}

static value
Val_event_graphics_address(virDomainEventGraphicsAddressPtr x)
{
  CAMLparam0 ();
  CAMLlocal1(result);
  result = caml_alloc_tuple(3);
  Store_field(result, 0, Val_int(x->family));
  Store_field(result, 1,
	      Val_opt((void *) x->node, (Val_ptr_t) caml_copy_string));
  Store_field(result, 2,
	      Val_opt((void *) x->service, (Val_ptr_t) caml_copy_string));
  CAMLreturn(result);
}

static value
Val_event_graphics_subject_identity(virDomainEventGraphicsSubjectIdentityPtr x)
{
  CAMLparam0 ();
  CAMLlocal1(result);
  result = caml_alloc_tuple(2);
  Store_field(result, 0,
	      Val_opt((void *) x->type, (Val_ptr_t) caml_copy_string));
  Store_field(result, 1,
	      Val_opt((void *) x->name, (Val_ptr_t) caml_copy_string));
  CAMLreturn(result);

}

static value
Val_event_graphics_subject(virDomainEventGraphicsSubjectPtr x)
{
  CAMLparam0 ();
  CAMLlocal1(result);
  int i;
  result = caml_alloc_tuple(x->nidentity);
  for (i = 0; i < x->nidentity; i++ )
    Store_field(result, i,
		Val_event_graphics_subject_identity(x->identities + i));
  CAMLreturn(result);
}

static void
i_ga_ga_s_gs_callback(virConnectPtr conn,
		      virDomainPtr dom,
		      int i1,
		      virDomainEventGraphicsAddressPtr ga1,
		      virDomainEventGraphicsAddressPtr ga2,
		      char *s1,
		      virDomainEventGraphicsSubjectPtr gs1,
		      void * opaque)
{
  DOMAIN_CALLBACK_BEGIN("Libvirt.i_ga_ga_s_gs_callback")
  result = caml_alloc_tuple(5);
  Store_field(result, 0, Val_int(i1));
  Store_field(result, 1, Val_event_graphics_address(ga1));
  Store_field(result, 2, Val_event_graphics_address(ga2)); 
  Store_field(result, 3,
	      Val_opt(s1, (Val_ptr_t) caml_copy_string));
  Store_field(result, 4, Val_event_graphics_subject(gs1));
  DOMAIN_CALLBACK_END
}

static void
timeout_callback(int timer, void *opaque)
{
  value callback_id, result;
  callback_id = result = Val_int(0);
  static value *callback = NULL;
  caml_leave_blocking_section();
  if (callback == NULL)
    callback = caml_named_value("Libvirt.timeout_callback");
  if (callback == NULL)
    abort(); /* C code out of sync with OCaml code */

  Begin_roots2(callback_id, result);
  callback_id = caml_copy_int64(*(long *)opaque);

  (void)caml_callback_exn(*callback, callback_id);
  End_roots();
  caml_enter_blocking_section();
}

CAMLprim value
ocaml_libvirt_event_add_timeout (value connv, value ms, value callback_id)
{
  CAMLparam3 (connv, ms, callback_id);
  void *opaque;
  virFreeCallback freecb = free;
  virEventTimeoutCallback cb = timeout_callback;

  int r;

  /* Store the int64 callback_id as the opaque data so the OCaml
     callback can demultiplex to the correct OCaml handler. */
  if ((opaque = malloc(sizeof(long))) == NULL)
    caml_failwith ("virEventAddTimeout: malloc");
  *((long*)opaque) = Int64_val(callback_id);
  NONBLOCKING(r = virEventAddTimeout(Int_val(ms), cb, opaque, freecb));
  CHECK_ERROR(r == -1, "virEventAddTimeout");

  CAMLreturn(Val_int(r));
}

CAMLprim value
ocaml_libvirt_event_remove_timeout (value connv, value timer_id)
{
  CAMLparam2 (connv, timer_id);
  int r;

  NONBLOCKING(r = virEventRemoveTimeout(Int_val(timer_id)));
  CHECK_ERROR(r == -1, "virEventRemoveTimeout");

  CAMLreturn(Val_int(r));
}

CAMLprim value
ocaml_libvirt_connect_domain_event_register_any(value connv, value domv, value callback, value callback_id)
{
  CAMLparam4(connv, domv, callback, callback_id);

  virConnectPtr conn = Connect_val (connv);
  virDomainPtr dom = NULL;
  int eventID = Tag_val(callback);

  virConnectDomainEventGenericCallback cb;
  void *opaque;
  virFreeCallback freecb = free;
  int r;

  if (domv != Val_int(0))
    dom = Domain_val (Field(domv, 0));

  switch (eventID){
  case VIR_DOMAIN_EVENT_ID_LIFECYCLE:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_REBOOT:
    cb = VIR_DOMAIN_EVENT_CALLBACK(u_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_RTC_CHANGE:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i64_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_WATCHDOG:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_IO_ERROR:
    cb = VIR_DOMAIN_EVENT_CALLBACK(s_s_i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_GRAPHICS:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_ga_ga_s_gs_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_IO_ERROR_REASON:
    cb = VIR_DOMAIN_EVENT_CALLBACK(s_s_i_s_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_CONTROL_ERROR:
    cb = VIR_DOMAIN_EVENT_CALLBACK(u_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_BLOCK_JOB:
    cb = VIR_DOMAIN_EVENT_CALLBACK(s_i_i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_DISK_CHANGE:
    cb = VIR_DOMAIN_EVENT_CALLBACK(s_s_s_i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_TRAY_CHANGE:
    cb = VIR_DOMAIN_EVENT_CALLBACK(s_i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_PMWAKEUP:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_PMSUSPEND:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_BALLOON_CHANGE:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i64_callback);
    break;
  case VIR_DOMAIN_EVENT_ID_PMSUSPEND_DISK:
    cb = VIR_DOMAIN_EVENT_CALLBACK(i_callback);
    break;
  default:
    caml_failwith("vifConnectDomainEventRegisterAny: unimplemented eventID");
  }

  /* Store the int64 callback_id as the opaque data so the OCaml
     callback can demultiplex to the correct OCaml handler. */
  if ((opaque = malloc(sizeof(long))) == NULL)
    caml_failwith ("virConnectDomainEventRegisterAny: malloc");
  *((long*)opaque) = Int64_val(callback_id);
  NONBLOCKING(r = virConnectDomainEventRegisterAny(conn, dom, eventID, cb, opaque, freecb));
  CHECK_ERROR(r == -1, "virConnectDomainEventRegisterAny");

  CAMLreturn(Val_int(r));
}

CAMLprim value
ocaml_libvirt_storage_pool_get_info (value poolv)
{
  CAMLparam1 (poolv);
  CAMLlocal2 (rv, v);
  virStoragePoolPtr pool = Pool_val (poolv);
  virStoragePoolInfo info;
  int r;

  NONBLOCKING (r = virStoragePoolGetInfo (pool, &info));
  CHECK_ERROR (r == -1, "virStoragePoolGetInfo");

  rv = caml_alloc (4, 0);
  Store_field (rv, 0, Val_int (info.state));
  v = caml_copy_int64 (info.capacity); Store_field (rv, 1, v);
  v = caml_copy_int64 (info.allocation); Store_field (rv, 2, v);
  v = caml_copy_int64 (info.available); Store_field (rv, 3, v);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_storage_vol_get_info (value volv)
{
  CAMLparam1 (volv);
  CAMLlocal2 (rv, v);
  virStorageVolPtr vol = Volume_val (volv);
  virStorageVolInfo info;
  int r;

  NONBLOCKING (r = virStorageVolGetInfo (vol, &info));
  CHECK_ERROR (r == -1, "virStorageVolGetInfo");

  rv = caml_alloc (3, 0);
  Store_field (rv, 0, Val_int (info.type));
  v = caml_copy_int64 (info.capacity); Store_field (rv, 1, v);
  v = caml_copy_int64 (info.allocation); Store_field (rv, 2, v);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_secret_lookup_by_usage (value connv, value usagetypev, value usageidv)
{
  CAMLparam3 (connv, usagetypev, usageidv);
  CAMLlocal1 (rv);
  virConnectPtr conn = Connect_val (connv);
  int usageType = Int_val (usagetypev);
  const char *usageID = String_val (usageidv);
  virSecretPtr r;

  NONBLOCKING (r = virSecretLookupByUsage (conn, usageType, usageID));
  CHECK_ERROR (!r, "virSecretLookupByUsage");

  rv = Val_secret (r, connv);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_secret_set_value (value secv, value vv)
{
  CAMLparam2 (secv, vv);
  virSecretPtr sec = Secret_val (secv);
  const unsigned char *secval = (unsigned char *) String_val (vv);
  const size_t size = caml_string_length (vv);
  int r;

  NONBLOCKING (r = virSecretSetValue (sec, secval, size, 0));
  CHECK_ERROR (r == -1, "virSecretSetValue");

  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_secret_get_value (value secv)
{
  CAMLparam1 (secv);
  CAMLlocal1 (rv);
  virSecretPtr sec = Secret_val (secv);
  unsigned char *secval;
  size_t size = 0;

  NONBLOCKING (secval = virSecretGetValue (sec, &size, 0));
  CHECK_ERROR (secval == NULL, "virSecretGetValue");

  rv = caml_alloc_string (size);
  memcpy (String_val (rv), secval, size);
  free (secval);

  CAMLreturn (rv);
}

/*----------------------------------------------------------------------*/

CAMLprim value
ocaml_libvirt_virterror_get_last_error (value unitv)
{
  CAMLparam1 (unitv);
  CAMLlocal1 (rv);
  virErrorPtr err = virGetLastError ();

  rv = Val_opt (err, (Val_ptr_t) Val_virterror);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_virterror_get_last_conn_error (value connv)
{
  CAMLparam1 (connv);
  CAMLlocal1 (rv);
  virConnectPtr conn = Connect_val (connv);

  rv = Val_opt (conn, (Val_ptr_t) Val_connect);

  CAMLreturn (rv);
}

CAMLprim value
ocaml_libvirt_virterror_reset_last_error (value unitv)
{
  CAMLparam1 (unitv);
  virResetLastError ();
  CAMLreturn (Val_unit);
}

CAMLprim value
ocaml_libvirt_virterror_reset_last_conn_error (value connv)
{
  CAMLparam1 (connv);
  virConnectPtr conn = Connect_val (connv);
  virConnResetLastError (conn);
  CAMLreturn (Val_unit);
}

/*----------------------------------------------------------------------*/

static void
ignore_errors (void *user_data, virErrorPtr error)
{
  /* do nothing */
}

/* Initialise the library. */
CAMLprim value
ocaml_libvirt_init (value unit)
{
  CAMLparam1 (unit);

  virSetErrorFunc (NULL, ignore_errors);
  virInitialize ();

  CAMLreturn (Val_unit);
}
