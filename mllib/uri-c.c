/* virt-resize - interface to -a URI option parsing mini library
 * Copyright (C) 2013 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <locale.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <guestfs.h>
#include "guestfs-internal-frontend.h"
#include "uri.h"

value
virt_resize_parse_uri (value argv /* arg value, not an array! */)
{
  CAMLparam1 (argv);
  CAMLlocal4 (rv, sv, ssv, ov);
  struct uri uri;
  int r;

  r = parse_uri (String_val (argv), &uri);
  if (r == -1)
    caml_invalid_argument ("URI.parse_uri");

  /* Convert the struct into an OCaml tuple. */
  rv = caml_alloc_tuple (5);

  /* path : string */
  sv = caml_copy_string (uri.path);
  free (uri.path);
  Store_field (rv, 0, sv);

  /* protocol : string */
  sv = caml_copy_string (uri.protocol);
  free (uri.protocol);
  Store_field (rv, 1, sv);

  /* server : string array option */
  if (uri.server) {
    ssv = caml_copy_string_array ((const char **) uri.server);
    guestfs_int_free_string_list (uri.server);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, ssv);
  }
  else
    ov = Val_int (0);
  Store_field (rv, 2, ov);

  /* username : string option */
  if (uri.username) {
    sv = caml_copy_string (uri.username);
    free (uri.username);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else
    ov = Val_int (0);
  Store_field (rv, 3, ov);

  /* password : string option */
  if (uri.password) {
    sv = caml_copy_string (uri.password);
    free (uri.password);
    ov = caml_alloc (1, 0);
    Store_field (ov, 0, sv);
  }
  else
    ov = Val_int (0);
  Store_field (rv, 4, ov);

  CAMLreturn (rv);
}
