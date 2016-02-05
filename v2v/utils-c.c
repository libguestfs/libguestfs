/* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

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

static value
get_firmware (char **firmware)
{
  CAMLparam0 ();
  CAMLlocal5 (rv, v, v1, v2, cons);
  size_t i, len;

  rv = Val_int (0);

  /* Build the list backwards so we don't have to reverse it at the end. */
  len = guestfs_int_count_strings (firmware);

  for (i = len; i > 0; i -= 2) {
    v1 = caml_copy_string (firmware[i-2]);
    v2 = caml_copy_string (firmware[i-1]);
    v = caml_alloc (2, 0);
    Store_field (v, 0, v1);
    Store_field (v, 1, v2);
    cons = caml_alloc (2, 0);
    Store_field (cons, 1, rv);
    rv = cons;
    Store_field (cons, 0, v);
  }

  CAMLreturn (rv);
}

value
v2v_utils_ovmf_i386_firmware (value unitv)
{
  return get_firmware ((char **) guestfs_int_ovmf_i386_firmware);
}

value
v2v_utils_ovmf_x86_64_firmware (value unitv)
{
  return get_firmware ((char **) guestfs_int_ovmf_x86_64_firmware);
}

value
v2v_utils_aavmf_firmware (value unitv)
{
  return get_firmware ((char **) guestfs_int_aavmf_firmware);
}
