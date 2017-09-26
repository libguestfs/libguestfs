/* libguestfs OCaml tools common code
 * Copyright (C) 2016 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#include <guestfs.h>

#include "options.h"

extern value guestfs_int_mllib_inspect_decrypt (value gv, value gpv);
extern value guestfs_int_mllib_set_echo_keys (value unitv);
extern value guestfs_int_mllib_set_keys_from_stdin (value unitv);

/* Interface with the guestfish inspection and decryption code. */
int echo_keys = 0;
int keys_from_stdin = 0;

value
guestfs_int_mllib_inspect_decrypt (value gv, value gpv)
{
  CAMLparam2 (gv, gpv);
  guestfs_h *g = (guestfs_h *) (intptr_t) Int64_val (gpv);

  inspect_do_decrypt (g);

  CAMLreturn (Val_unit);
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_set_echo_keys (value unitv)
{
  echo_keys = 1;
  return Val_unit;
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_set_keys_from_stdin (value unitv)
{
  keys_from_stdin = 1;
  return Val_unit;
}
