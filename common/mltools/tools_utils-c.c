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
#include <error.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#include <guestfs.h>

#include "options.h"

extern value guestfs_int_mllib_inspect_decrypt (value gv, value gpv, value keysv);
extern value guestfs_int_mllib_set_echo_keys (value unitv);
extern value guestfs_int_mllib_set_keys_from_stdin (value unitv);

/* Interface with the guestfish inspection and decryption code. */
int echo_keys = 0;
int keys_from_stdin = 0;

value
guestfs_int_mllib_inspect_decrypt (value gv, value gpv, value keysv)
{
  CAMLparam3 (gv, gpv, keysv);
  CAMLlocal2 (elemv, v);
  guestfs_h *g = (guestfs_h *) (intptr_t) Int64_val (gpv);
  struct key_store *ks = NULL;

  while (keysv != Val_emptylist) {
    struct key_store_key key;

    elemv = Field (keysv, 0);
    key.device = strdup (String_val (Field (elemv, 0)));
    if (!key.device)
      caml_raise_out_of_memory ();

    v = Field (elemv, 1);
    switch (Tag_val (v)) {
    case 0:  /* KeyString of string */
      key.type = key_string;
      key.string.s = strdup (String_val (Field (v, 0)));
      if (!key.string.s)
        caml_raise_out_of_memory ();
      break;
    case 1:  /* KeyFileName of string */
      key.type = key_file;
      key.file.name = strdup (String_val (Field (v, 0)));
      if (!key.file.name)
        caml_raise_out_of_memory ();
      break;
    default:
      error (EXIT_FAILURE, 0,
             "internal error: unhandled Tag_val (v) = %d",
             Tag_val (v));
    }

    ks = key_store_import_key (ks, &key);

    keysv = Field (keysv, 1);
  }

  inspect_do_decrypt (g, ks);

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
