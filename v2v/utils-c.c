/* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "everrun_utils.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

value
v2v_utils_drive_name (value indexv)
{
  CAMLparam1 (indexv);
  CAMLlocal1 (namev);
  char name[64];

  guestfs_int_drive_name (Int_val (indexv), name);
  namev = caml_copy_string (name);

  CAMLreturn (namev);
}

value
v2v_utils_drive_index (value strv)
{
  CAMLparam1 (strv);
  ssize_t r;

  r = guestfs_int_drive_index (String_val (strv));
  if (r == -1)
    caml_invalid_argument ("drive_index: invalid parameter");

  CAMLreturn (Val_int (r));
}

value
v2v_utils_trim (value origin)
{
  CAMLparam1 (origin);
  CAMLlocal1 (modified_str);
  char result[strlen(String_val (origin))];

  everrun_trim(String_val (origin), result);
  modified_str = caml_copy_string (result);

  CAMLreturn (modified_str);
}

value
v2v_utils_get_everrun_obj_id (value mixed_id)
{
  CAMLparam1 (mixed_id);
  CAMLlocal1 (id);
  char result[strlen(String_val (mixed_id))];

  get_everrun_obj_id(String_val (mixed_id), result);
  id = caml_copy_string (result);

  CAMLreturn (id);
}

value
v2v_utils_get_everrun_passwd (value unit)
{
  CAMLparam1 (unit);
  CAMLlocal1 (passwd);
  char passwd_r[100];

  get_everrun_passwd(passwd_r);
  passwd = caml_copy_string (passwd_r);

  CAMLreturn (passwd);
}
