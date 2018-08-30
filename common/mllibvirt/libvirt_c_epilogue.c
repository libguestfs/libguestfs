/* OCaml bindings for libvirt.
 * (C) Copyright 2007 Richard W.M. Jones, Red Hat Inc.
 * https://libvirt.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version,
 * with the OCaml linking exception described in ../COPYING.LIB.
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

static const char *
Optstring_val (value strv)
{
  if (strv == Val_int (0))	/* None */
    return NULL;
  else				/* Some string */
    return String_val (Field (strv, 0));
}

static value
Val_opt (void *ptr, Val_ptr_t Val_ptr)
{
  CAMLparam0 ();
  CAMLlocal2 (optv, ptrv);

  if (ptr) {			/* Some ptr */
    optv = caml_alloc (1, 0);
    ptrv = Val_ptr (ptr);
    Store_field (optv, 0, ptrv);
  } else			/* None */
    optv = Val_int (0);

  CAMLreturn (optv);
}

static value
Val_opt_const (const void *ptr, Val_const_ptr_t Val_ptr)
{
  CAMLparam0 ();
  CAMLlocal2 (optv, ptrv);

  if (ptr) {			/* Some ptr */
    optv = caml_alloc (1, 0);
    ptrv = Val_ptr (ptr);
    Store_field (optv, 0, ptrv);
  } else			/* None */
    optv = Val_int (0);

  CAMLreturn (optv);
}

#if 0
static value
option_default (value option, value deflt)
{
  if (option == Val_int (0))    /* "None" */
    return deflt;
  else                          /* "Some 'a" */
    return Field (option, 0);
}
#endif

static void
_raise_virterror (const char *fn)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  virErrorPtr errp;
  struct _virError err;

  errp = virGetLastError ();

  if (!errp) {
    /* Fake a _virError structure. */
    memset (&err, 0, sizeof err);
    err.code = VIR_ERR_INTERNAL_ERROR;
    err.domain = VIR_FROM_NONE;
    err.level = VIR_ERR_ERROR;
    err.message = (char *) fn;
    errp = &err;
  }

  rv = Val_virterror (errp);
  caml_raise_with_arg (*caml_named_value ("ocaml_libvirt_virterror"), rv);

  /*NOTREACHED*/
  /* Suppresses a compiler warning. */
  (void) caml__frame;
}

static int
_list_length (value listv)
{
  CAMLparam1 (listv);
  int len = 0;

  for (; listv != Val_emptylist; listv = Field (listv, 1), ++len) {}

  CAMLreturnT (int, len);
}

static value
Val_virconnectcredential (const virConnectCredentialPtr cred)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  rv = caml_alloc (4, 0);
  Store_field (rv, 0, Val_int (cred->type - 1));
  Store_field (rv, 1, caml_copy_string (cred->prompt));
  Store_field (rv, 2,
               Val_opt_const (cred->challenge,
                              (Val_const_ptr_t) caml_copy_string));
  Store_field (rv, 3,
               Val_opt_const (cred->defresult,
                              (Val_const_ptr_t) caml_copy_string));

  CAMLreturn (rv);
}

/* Convert the virErrorNumber, virErrorDomain and virErrorLevel enums
 * into values (longs because they are variants in OCaml).
 *
 * The enum values are part of the libvirt ABI so they cannot change,
 * which means that we can convert these numbers directly into
 * OCaml variants (which use the same ordering) very fast.
 *
 * The tricky part here is when we are linked to a newer version of
 * libvirt than the one we were compiled against.  If the newer libvirt
 * generates an error code which we don't know about then we need
 * to convert it into VIR_*_UNKNOWN (code).
 */

#define MAX_VIR_CODE 104 /* VIR_ERR_NO_DOMAIN_BACKUP */
#define MAX_VIR_DOMAIN 69 /* VIR_FROM_DOMAIN_CHECKPOINT */
#define MAX_VIR_LEVEL VIR_ERR_ERROR

static inline value
Val_err_number (virErrorNumber code)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  if (0 <= (int) code && code <= MAX_VIR_CODE)
    rv = Val_int (code);
  else {
    rv = caml_alloc (1, 0);	/* VIR_ERR_UNKNOWN (code) */
    Store_field (rv, 0, Val_int (code));
  }

  CAMLreturn (rv);
}

static inline value
Val_err_domain (virErrorDomain code)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  if (0 <= (int) code && code <= MAX_VIR_DOMAIN)
    rv = Val_int (code);
  else {
    rv = caml_alloc (1, 0);	/* VIR_FROM_UNKNOWN (code) */
    Store_field (rv, 0, Val_int (code));
  }

  CAMLreturn (rv);
}

static inline value
Val_err_level (virErrorLevel code)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  if (0 <= (int) code && code <= MAX_VIR_LEVEL)
    rv = Val_int (code);
  else {
    rv = caml_alloc (1, 0);	/* VIR_ERR_UNKNOWN_LEVEL (code) */
    Store_field (rv, 0, Val_int (code));
  }

  CAMLreturn (rv);
}

/* Convert a virterror to a value. */
static value
Val_virterror (virErrorPtr err)
{
  CAMLparam0 ();
  CAMLlocal3 (rv, connv, optv);

  rv = caml_alloc (9, 0);
  Store_field (rv, 0, Val_err_number (err->code));
  Store_field (rv, 1, Val_err_domain (err->domain));
  Store_field (rv, 2,
	       Val_opt (err->message, (Val_ptr_t) caml_copy_string));
  Store_field (rv, 3, Val_err_level (err->level));

  Store_field (rv, 4,
	       Val_opt (err->str1, (Val_ptr_t) caml_copy_string));
  Store_field (rv, 5,
	       Val_opt (err->str2, (Val_ptr_t) caml_copy_string));
  Store_field (rv, 6,
	       Val_opt (err->str3, (Val_ptr_t) caml_copy_string));
  Store_field (rv, 7, caml_copy_int32 (err->int1));
  Store_field (rv, 8, caml_copy_int32 (err->int2));

  CAMLreturn (rv);
}

static void conn_finalize (value);
static void dom_finalize (value);
static void net_finalize (value);
static void pol_finalize (value);
static void vol_finalize (value);
static void sec_finalize (value);

static struct custom_operations conn_custom_operations = {
  (char *) "conn_custom_operations",
  conn_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static struct custom_operations dom_custom_operations = {
  (char *) "dom_custom_operations",
  dom_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default

};

static struct custom_operations net_custom_operations = {
  (char *) "net_custom_operations",
  net_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static struct custom_operations pol_custom_operations = {
  (char *) "pol_custom_operations",
  pol_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static struct custom_operations vol_custom_operations = {
  (char *) "vol_custom_operations",
  vol_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static struct custom_operations sec_custom_operations = {
  (char *) "sec_custom_operations",
  sec_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static value
Val_connect (virConnectPtr conn)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&conn_custom_operations,
			  sizeof (virConnectPtr), 0, 1);
  Connect_val (rv) = conn;
  CAMLreturn (rv);
}

static value
Val_dom (virDomainPtr dom)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&dom_custom_operations,
			  sizeof (virDomainPtr), 0, 1);
  Dom_val (rv) = dom;
  CAMLreturn (rv);
}

static value
Val_net (virNetworkPtr net)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&net_custom_operations,
			  sizeof (virNetworkPtr), 0, 1);
  Net_val (rv) = net;
  CAMLreturn (rv);
}

static value
Val_pol (virStoragePoolPtr pol)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&pol_custom_operations,
			  sizeof (virStoragePoolPtr), 0, 1);
  Pol_val (rv) = pol;
  CAMLreturn (rv);
}

static value
Val_vol (virStorageVolPtr vol)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&vol_custom_operations,
			  sizeof (virStorageVolPtr), 0, 1);
  Vol_val (rv) = vol;
  CAMLreturn (rv);
}

static value
Val_sec (virSecretPtr sec)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  rv = caml_alloc_custom (&sec_custom_operations,
			  sizeof (virSecretPtr), 0, 1);
  Sec_val (rv) = sec;
  CAMLreturn (rv);
}

/* This wraps up the (dom, conn) pair (Domain.t). */
static value
Val_domain (virDomainPtr dom, value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);

  rv = caml_alloc_tuple (2);
  v = Val_dom (dom);
  Store_field (rv, 0, v);
  Store_field (rv, 1, connv);
  CAMLreturn (rv);
}

/* This wraps up the (net, conn) pair (Network.t). */
static value
Val_network (virNetworkPtr net, value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);

  rv = caml_alloc_tuple (2);
  v = Val_net (net);
  Store_field (rv, 0, v);
  Store_field (rv, 1, connv);
  CAMLreturn (rv);
}

/* This wraps up the (pol, conn) pair (Pool.t). */
static value
Val_pool (virStoragePoolPtr pol, value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);

  rv = caml_alloc_tuple (2);
  v = Val_pol (pol);
  Store_field (rv, 0, v);
  Store_field (rv, 1, connv);
  CAMLreturn (rv);
}

/* This wraps up the (vol, conn) pair (Volume.t). */
static value
Val_volume (virStorageVolPtr vol, value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);

  rv = caml_alloc_tuple (2);
  v = Val_vol (vol);
  Store_field (rv, 0, v);
  Store_field (rv, 1, connv);
  CAMLreturn (rv);
}

/* This wraps up the (sec, conn) pair (Secret.t). */
static value
Val_secret (virSecretPtr sec, value connv)
{
  CAMLparam1 (connv);
  CAMLlocal2 (rv, v);

  rv = caml_alloc_tuple (2);
  v = Val_sec (sec);
  Store_field (rv, 0, v);
  Store_field (rv, 1, connv);
  CAMLreturn (rv);
}

static void
conn_finalize (value connv)
{
  virConnectPtr conn = Connect_val (connv);
  if (conn) (void) virConnectClose (conn);
}

static void
dom_finalize (value domv)
{
  virDomainPtr dom = Dom_val (domv);
  if (dom) (void) virDomainFree (dom);
}

static void
net_finalize (value netv)
{
  virNetworkPtr net = Net_val (netv);
  if (net) (void) virNetworkFree (net);
}

static void
pol_finalize (value polv)
{
  virStoragePoolPtr pol = Pol_val (polv);
  if (pol) (void) virStoragePoolFree (pol);
}

static void
vol_finalize (value volv)
{
  virStorageVolPtr vol = Vol_val (volv);
  if (vol) (void) virStorageVolFree (vol);
}

static void
sec_finalize (value secv)
{
  virSecretPtr sec = Sec_val (secv);
  if (sec) (void) virSecretFree (sec);
}
