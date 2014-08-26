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
#include <errno.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#endif

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

#ifdef HAVE_LIBVIRT

static void raise_error (const char *fs, ...)
  __attribute__((noreturn))
  __attribute__((format (printf,1,2)));

/* Note we rely on libvirt printing errors to stderr, so the exception
 * doesn't need to contain the actual error from libvirt.
 */
static void
raise_error (const char *fs, ...)
{
  va_list args;
  /* We have to assemble the error on the stack because a dynamic
   * string couldn't be freed.
   */
  char msg[256];
  int len;

  va_start (args, fs);
  len = vsnprintf (msg, sizeof msg, fs , args);
  va_end (args);

  if (len < 0) caml_failwith (fs);

  caml_invalid_argument (msg);
}

value
v2v_dumpxml (value connv, value domnamev)
{
  CAMLparam2 (connv, domnamev);
  CAMLlocal1 (retv);
  const char *conn_uri = NULL;
  const char *domname;
  virConnectPtr conn;
  virDomainPtr dom;
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
      raise_error ("cannot open libvirt connection '%s'", conn_uri);
    else
      raise_error ("cannot open libvirt connection");
  }

  /* Look up the domain. */
  domname = String_val (domnamev);

  dom = virDomainLookupByName (conn, domname);
  if (!dom) {
    virConnectClose (conn);
    raise_error ("cannot find libvirt domain '%s'", domname);
  }

  xml = virDomainGetXMLDesc (dom, 0);
  virDomainFree (dom);
  virConnectClose (conn);
  if (xml == NULL)
    raise_error ("cannot fetch XML description of guest '%s'", domname);

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
      raise_error ("cannot open libvirt connection '%s'", conn_uri);
    else
      raise_error ("cannot open libvirt connection");
  }

  /* Look up the pool. */
  poolname = String_val (poolnamev);

  pool = virStoragePoolLookupByName (conn, poolname);
  if (!pool) {
    virConnectClose (conn);
    raise_error ("cannot find libvirt pool '%s'", poolname);
  }

  xml = virStoragePoolGetXMLDesc (pool, 0);
  virStoragePoolFree (pool);
  virConnectClose (conn);
  if (xml == NULL)
    raise_error ("cannot fetch XML description of guest '%s'", poolname);

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
