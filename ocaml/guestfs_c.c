/* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

#include <config.h>
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
#include <caml/printexc.h>
#include <caml/signals.h>

#include "guestfs_c.h"

static void clear_progress_callback (guestfs_h *g);
static void progress_callback (guestfs_h *g, void *data, int proc_nr, int serial, uint64_t position, uint64_t total);

/* This macro was added in OCaml 3.10.  Backport for earlier versions. */
#ifndef CAMLreturnT
#define CAMLreturnT(type, result) do{ \
  type caml__temp_result = (result); \
  caml_local_roots = caml__frame; \
  return (caml__temp_result); \
}while(0)
#endif

/* These prototypes are solely to quiet gcc warning.  */
CAMLprim value ocaml_guestfs_create (void);
CAMLprim value ocaml_guestfs_close (value gv);
CAMLprim value ocaml_guestfs_set_progress_callback (value gv, value closure);
CAMLprim value ocaml_guestfs_clear_progress_callback (value gv);

/* Allocate handles and deal with finalization. */
static void
guestfs_finalize (value gv)
{
  guestfs_h *g = Guestfs_val (gv);
  if (g) {
    clear_progress_callback (g);
    guestfs_close (g);
  }
}

static struct custom_operations guestfs_custom_operations = {
  (char *) "guestfs_custom_operations",
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

void
ocaml_guestfs_raise_closed (const char *func)
{
  CAMLparam0 ();
  CAMLlocal1 (v);

  v = caml_copy_string (func);
  caml_raise_with_arg (*caml_named_value ("ocaml_guestfs_closed"), v);
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

/* Copy string array value. */
char **
ocaml_guestfs_strings_val (guestfs_h *g, value sv)
{
  CAMLparam1 (sv);
  char **r;
  unsigned int i;

  r = guestfs_safe_malloc (g, sizeof (char *) * (Wosize_val (sv) + 1));
  for (i = 0; i < Wosize_val (sv); ++i)
    r[i] = guestfs_safe_strdup (g, String_val (Field (sv, i)));
  r[i] = NULL;

  CAMLreturnT (char **, r);
}

/* Free array of strings. */
void
ocaml_guestfs_free_strings (char **argv)
{
  unsigned int i;

  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

#define PROGRESS_ROOT_KEY "_ocaml_progress_root"

/* Guestfs.set_progress_callback */
CAMLprim value
ocaml_guestfs_set_progress_callback (value gv, value closure)
{
  CAMLparam2 (gv, closure);

  guestfs_h *g = Guestfs_val (gv);
  clear_progress_callback (g);

  value *root = guestfs_safe_malloc (g, sizeof *root);
  *root = closure;

  /* XXX This global root is generational, but we cannot rely on every
   * user having the OCaml 3.11 version which supports this.
   */
  caml_register_global_root (root);

  guestfs_set_private (g, PROGRESS_ROOT_KEY, root);

  guestfs_set_progress_callback (g, progress_callback, root);

  CAMLreturn (Val_unit);
}

/* Guestfs.clear_progress_callback */
CAMLprim value
ocaml_guestfs_clear_progress_callback (value gv)
{
  CAMLparam1 (gv);

  guestfs_h *g = Guestfs_val (gv);
  clear_progress_callback (g);

  CAMLreturn (Val_unit);
}

static void
clear_progress_callback (guestfs_h *g)
{
  guestfs_set_progress_callback (g, NULL, NULL);

  value *root = guestfs_get_private (g, PROGRESS_ROOT_KEY);
  if (root) {
    caml_remove_global_root (root);
    free (root);
    guestfs_set_private (g, PROGRESS_ROOT_KEY, NULL);
  }
}

static void
progress_callback (guestfs_h *g ATTRIBUTE_UNUSED, void *root,
                   int proc_nr, int serial, uint64_t position, uint64_t total)
{
  CAMLparam0 ();
  CAMLlocal5 (proc_nrv, serialv, positionv, totalv, rv);

  proc_nrv = Val_int (proc_nr);
  serialv = Val_int (serial);
  positionv = caml_copy_int64 (position);
  totalv = caml_copy_int64 (total);

  value args[4] = { proc_nrv, serialv, positionv, totalv };

  caml_leave_blocking_section ();
  rv = caml_callbackN_exn (*(value*)root, 4, args);
  caml_enter_blocking_section ();

  /* Callbacks shouldn't throw exceptions.  There's not much we can do
   * except to print it.
   */
  if (Is_exception_result (rv))
    fprintf (stderr, "libguestfs: uncaught OCaml exception in progress callback: %s",
             caml_format_exception (Extract_exception (rv)));

  CAMLreturn0;
}
