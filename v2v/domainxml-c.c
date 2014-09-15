/* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* [virsh dumpxml] but with non-broken authentication handling. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <libintl.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

#ifdef HAVE_LIBVIRT

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

/* Get the remote domain state (running, etc.).  Use virDomainGetState
 * which is most efficient, but if it's not implemented, fall back to
 * virDomainGetInfo.  See equivalent code in virsh.
 */
static int
get_dom_state (virDomainPtr dom)
{
  int state, reason;
  virErrorPtr err;
  virDomainInfo info;

  if (virDomainGetState (dom, &state, &reason, 0) == 0)
    return state;

  err = virGetLastError ();
  if (!err || err->code != VIR_ERR_NO_SUPPORT)
    return -1;

  if (virDomainGetInfo (dom, &info) == 0)
    return info.state;

  return -1;
}

value
v2v_dumpxml (value connv, value domnamev)
{
  CAMLparam2 (connv, domnamev);
  CAMLlocal1 (retv);
  const char *conn_uri = NULL;
  const char *domname;
  /* We have to assemble the error on the stack because a dynamic
   * string couldn't be freed.
   */
  char errmsg[256];
  virErrorPtr err;
  virConnectPtr conn;
  virDomainPtr dom;
  int is_test_uri = 0;
  char *xml;

  if (connv != Val_int (0)) {
    conn_uri = String_val (Field (connv, 0)); /* Some conn */
    is_test_uri = STRPREFIX (conn_uri, "test:");
  }

  /* We have to call the default authentication handler, not least
   * since it handles all the PolicyKit crap.  However it also makes
   * coding this simpler.
   */
  conn = virConnectOpenAuth (conn_uri, virConnectAuthPtrDefault, VIR_CONNECT_RO);
  if (conn == NULL) {
    if (conn_uri)
      snprintf (errmsg, sizeof errmsg,
                _("cannot open libvirt connection '%s'"), conn_uri);
    else
      snprintf (errmsg, sizeof errmsg, _("cannot open libvirt connection"));
    caml_invalid_argument (errmsg);
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  /* Look up the domain. */
  domname = String_val (domnamev);

  dom = virDomainLookupByUUIDString (conn, domname);

  if (!dom)
    dom = virDomainLookupByName (conn, domname);

  if (!dom) {
    err = virGetLastError ();
    snprintf (errmsg, sizeof errmsg,
              _("cannot find libvirt domain '%s': %s"), domname, err->message);
    virConnectClose (conn);
    caml_invalid_argument (errmsg);
  }

  /* As a side-effect we check that the domain is shut down.  Of course
   * this is only appropriate for virt-v2v.  (RHBZ#1138586)
   */
  if (!is_test_uri) {
    int state = get_dom_state (dom);

    if (state == VIR_DOMAIN_RUNNING) {
      snprintf (errmsg, sizeof errmsg,
                _("libvirt domain '%s' is running, it must be shut down in order to perform virt-v2v conversion"),
                domname);
      virDomainFree (dom);
      virConnectClose (conn);
      caml_invalid_argument (errmsg);
    }
  }

  xml = virDomainGetXMLDesc (dom, 0);
  if (xml == NULL) {
    err = virGetLastError ();
    snprintf (errmsg, sizeof errmsg,
              _("cannot fetch XML description of guest '%s': %s"),
              domname, err->message);
    virDomainFree (dom);
    virConnectClose (conn);
    caml_invalid_argument (errmsg);
  }
  virDomainFree (dom);
  virConnectClose (conn);

  retv = caml_copy_string (xml);
  free (xml);

  CAMLreturn (retv);
}

value
v2v_pool_dumpxml (value connv, value poolnamev)
{
  CAMLparam2 (connv, poolnamev);
  CAMLlocal1 (retv);
  const char *conn_uri = NULL;
  const char *poolname;
  /* We have to assemble the error on the stack because a dynamic
   * string couldn't be freed.
   */
  char errmsg[256];
  virErrorPtr err;
  virConnectPtr conn;
  virStoragePoolPtr pool;
  char *xml;

  if (connv != Val_int (0))
    conn_uri = String_val (Field (connv, 0)); /* Some conn */

  /* We have to call the default authentication handler, not least
   * since it handles all the PolicyKit crap.  However it also makes
   * coding this simpler.
   */
  conn = virConnectOpenAuth (conn_uri, virConnectAuthPtrDefault, VIR_CONNECT_RO);
  if (conn == NULL) {
    if (conn_uri)
      snprintf (errmsg, sizeof errmsg,
                _("cannot open libvirt connection '%s'"), conn_uri);
    else
      snprintf (errmsg, sizeof errmsg, _("cannot open libvirt connection"));
    caml_invalid_argument (errmsg);
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  /* Look up the pool. */
  poolname = String_val (poolnamev);

  pool = virStoragePoolLookupByName (conn, poolname);
  if (!pool) {
    err = virGetLastError ();
    snprintf (errmsg, sizeof errmsg,
              _("cannot find libvirt pool '%s': %s"), poolname, err->message);
    virConnectClose (conn);
    caml_invalid_argument (errmsg);
  }

  xml = virStoragePoolGetXMLDesc (pool, 0);
  if (xml == NULL) {
    err = virGetLastError ();
    snprintf (errmsg, sizeof errmsg,
              _("cannot fetch XML description of pool '%s': %s"),
              poolname, err->message);
    virStoragePoolFree (pool);
    virConnectClose (conn);
    caml_invalid_argument (errmsg);
  }
  virStoragePoolFree (pool);
  virConnectClose (conn);

  retv = caml_copy_string (xml);
  free (xml);

  CAMLreturn (retv);
}

#else /* !HAVE_LIBVIRT */

value
v2v_dumpxml (value connv, value domv)
{
  caml_invalid_argument ("virt-v2v was compiled without libvirt support");
}

value
v2v_pool_dumpxml (value connv, value poolv)
{
  caml_invalid_argument ("virt-v2v was compiled without libvirt support");
}

#endif /* !HAVE_LIBVIRT */
