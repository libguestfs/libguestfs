/* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <guestfs.h>

#include <caml/config.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "guestfs_c.h"

/* Allocate handles and deal with finalization. */
static void
guestfs_finalize (value gv)
{
  guestfs_h *g = Guestfs_val (gv);
  if (g) guestfs_close (g);
}

static struct custom_operations guestfs_custom_operations = {
  "guestfs_custom_operations",
  guestfs_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static value
Val_guestfs (guestfs_h *g)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  rv = caml_alloc_custom (&guestfs_custom_operations,
                          sizeof (guestfs_h *), 0, 1);
  Guestfs_val (rv) = g;

  CAMLreturn (rv);
}

void
ocaml_guestfs_raise_error (guestfs_h *g, const char *func)
{
  CAMLparam0 ();
  CAMLlocal1 (v);
  const char *msg;

  msg = guestfs_last_error (g);

  if (msg)
    v = caml_copy_string (msg);
  else
    v = caml_copy_string (func);
  caml_raise_with_arg (*caml_named_value ("ocaml_guestfs_error"), v);
  CAMLnoreturn;
}

/* Guestfs.create */
CAMLprim value
ocaml_guestfs_create (void)
{
  CAMLparam0 ();
  CAMLlocal1 (gv);
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL)
    caml_failwith ("failed to create guestfs handle");

  guestfs_set_error_handler (g, NULL, NULL);

  gv = Val_guestfs (g);
  CAMLreturn (gv);
}

/* Guestfs.close */
CAMLprim value
ocaml_guestfs_close (value gv)
{
  CAMLparam1 (gv);

  guestfs_finalize (gv);

  /* So we don't double-free in the finalizer. */
  Guestfs_val (gv) = NULL;

  CAMLreturn (Val_unit);
}

/* Copy string array value.
 * The return value is only 'safe' provided we don't allocate anything
 * further on the OCaml heap (ie. cannot trigger the OCaml GC) because
 * that could move the strings around.
 */
char **
ocaml_guestfs_strings_val (guestfs_h *g, value sv)
{
  CAMLparam1 (sv);
  char **r;
  int i;

  r = guestfs_safe_malloc (g, sizeof (char *) * (Wosize_val (sv) + 1));
  for (i = 0; i < Wosize_val (sv); ++i)
    r[i] = String_val (Field (sv, i));
  r[i] = NULL;

  CAMLreturnT (char **, r);
}

/* Free array of strings. */
void
ocaml_guestfs_free_strings (char **argv)
{
  /* Don't free the actual strings - they are String_vals on
   * the OCaml heap.
   */
  free (argv);
}
