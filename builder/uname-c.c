/* virt-builder
 * Copyright (C) 2014 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <errno.h>
#include <sys/utsname.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

value
virt_builder_uname (value unit)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  struct utsname u;

  if (uname (&u) < 0)
    unix_error (errno, (char *) "uname", Val_int (0));

  rv = caml_alloc (5, 0);

  Store_field (rv, 0, caml_copy_string (u.sysname));
  Store_field (rv, 1, caml_copy_string (u.nodename));
  Store_field (rv, 2, caml_copy_string (u.release));
  Store_field (rv, 3, caml_copy_string (u.version));
  Store_field (rv, 4, caml_copy_string (u.machine));

  CAMLreturn (rv);
}
