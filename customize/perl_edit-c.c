/* virt-customize - interface to edit_file_perl
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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "file-edit.h"

/**
 * We try to reuse the internals of the OCaml binding (for extracting
 * the guestfs handle, and raising errors); hopefully this should be safe,
 * as long as it's kept internal within the libguestfs sources.
 */
#include "../ocaml/guestfs-c.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

value
virt_customize_edit_file_perl (value verbosev, value guestfsv, value filev,
                               value exprv)
{
  CAMLparam4 (verbosev, guestfsv, filev, exprv);
  int r;
  guestfs_h *g;

  g = Guestfs_val (guestfsv);
  r = edit_file_perl (g, String_val (filev), String_val (exprv), NULL,
                      Bool_val (verbosev));
  if (r == -1)
    ocaml_guestfs_raise_error (g, "edit_file_perl");

  CAMLreturn (Val_unit);
}
