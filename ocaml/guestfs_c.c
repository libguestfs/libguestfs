/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

static value **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);
static void event_callback_wrapper (guestfs_h *g, void *data, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

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
CAMLprim value ocaml_guestfs_set_event_callback (value gv, value closure, value events);
CAMLprim value ocaml_guestfs_delete_event_callback (value gv, value eh);
value ocaml_guestfs_last_errno (value gv);
value ocaml_guestfs_user_cancel (value gv);

/* Allocate handles and deal with finalization. */
static void
guestfs_finalize (value gv)
{
  guestfs_h *g = Guestfs_val (gv);

  if (g) {
    /* There is a nasty, difficult to solve case here where the
     * user deletes events in one of the callbacks that we are
     * about to invoke, resulting in a double-free.  XXX
     */
    size_t len, i;
    value **roots = get_all_event_callbacks (g, &len);

    value *v = guestfs_get_private (g, "_ocaml_g");

    /* Close the handle: this could invoke callbacks from the list
     * above, which is why we don't want to delete them before
     * closing the handle.
     */
    guestfs_close (g);

    /* Now unregister the global roots. */
    for (i = 0; i < len; ++i) {
      caml_remove_global_root (roots[i]);
      free (roots[i]);
    }
    free (roots);

    caml_remove_global_root (v);
    free (v);
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
  value *v;

  g = guestfs_create ();
  if (g == NULL)
    caml_failwith ("failed to create guestfs handle");

  guestfs_set_error_handler (g, NULL, NULL);

  gv = Val_guestfs (g);

  /* Store the OCaml handle into the C handle.  This is only so we can
   * map the C handle to the OCaml handle in event_callback_wrapper.
   */
  v = guestfs_safe_malloc (g, sizeof *v);
  *v = gv;
  /* XXX This global root is generational, but we cannot rely on every
   * user having the OCaml 3.11 version which supports this.
   */
  caml_register_global_root (v);
  guestfs_set_private (g, "_ocaml_g", v);

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
  size_t i;

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
  size_t i;

  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

static uint64_t
event_bitmask_of_event_list (value events)
{
  uint64_t r = 0;

  while (events != Val_int (0)) {
    r |= UINT64_C(1) << Int_val (Field (events, 0));
    events = Field (events, 1);
  }

  return r;
}

/* Guestfs.set_event_callback */
CAMLprim value
ocaml_guestfs_set_event_callback (value gv, value closure, value events)
{
  CAMLparam3 (gv, closure, events);
  char key[64];
  int eh;
  uint64_t event_bitmask;

  guestfs_h *g = Guestfs_val (gv);

  event_bitmask = event_bitmask_of_event_list (events);

  value *root = guestfs_safe_malloc (g, sizeof *root);
  *root = closure;

  eh = guestfs_set_event_callback (g, event_callback_wrapper,
                                   event_bitmask, 0, root);

  if (eh == -1) {
    free (root);
    ocaml_guestfs_raise_error (g, "set_event_callback");
  }

  /* XXX This global root is generational, but we cannot rely on every
   * user having the OCaml 3.11 version which supports this.
   */
  caml_register_global_root (root);

  snprintf (key, sizeof key, "_ocaml_event_%d", eh);
  guestfs_set_private (g, key, root);

  CAMLreturn (Val_int (eh));
}

/* Guestfs.delete_event_callback */
CAMLprim value
ocaml_guestfs_delete_event_callback (value gv, value ehv)
{
  CAMLparam2 (gv, ehv);
  char key[64];
  int eh = Int_val (ehv);

  guestfs_h *g = Guestfs_val (gv);

  snprintf (key, sizeof key, "_ocaml_event_%d", eh);

  value *root = guestfs_get_private (g, key);
  if (root) {
    caml_remove_global_root (root);
    free (root);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }

  CAMLreturn (Val_unit);
}

static value **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  value **r;
  size_t i;
  const char *key;
  value *root;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, "_ocaml_event_", strlen ("_ocaml_event_")) == 0)
      (*len_rtn)++;
    root = guestfs_next_private (g, &key);
  }

  /* Copy them into the return array. */
  r = guestfs_safe_malloc (g, sizeof (value *) * (*len_rtn));

  i = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, "_ocaml_event_", strlen ("_ocaml_event_")) == 0) {
      r[i] = root;
      i++;
    }
    root = guestfs_next_private (g, &key);
  }

  return r;
}

/* Could do better: http://graphics.stanford.edu/~seander/bithacks.html */
static int
event_bitmask_to_event (uint64_t event)
{
  int r = 0;

  while (event >>= 1)
    r++;

  return r;
}

static void
event_callback_wrapper_locked (guestfs_h *g,
                               void *data,
                               uint64_t event,
                               int event_handle,
                               int flags,
                               const char *buf, size_t buf_len,
                               const uint64_t *array, size_t array_len)
{
  CAMLparam0 ();
  CAMLlocal5 (gv, evv, ehv, bufv, arrayv);
  CAMLlocal2 (rv, v);
  value *root;
  size_t i;

  root = guestfs_get_private (g, "_ocaml_g");
  gv = *root;

  /* Only one bit should be set in 'event'.  Which one? */
  evv = Val_int (event_bitmask_to_event (event));

  ehv = Val_int (event_handle);

  bufv = caml_alloc_string (buf_len);
  memcpy (String_val (bufv), buf, buf_len);

  arrayv = caml_alloc (array_len, 0);
  for (i = 0; i < array_len; ++i) {
    v = caml_copy_int64 (array[i]);
    Store_field (arrayv, i, v);
  }

  value args[5] = { gv, evv, ehv, bufv, arrayv };

  rv = caml_callbackN_exn (*(value*)data, 5, args);

  /* Callbacks shouldn't throw exceptions.  There's not much we can do
   * except to print it.
   */
  if (Is_exception_result (rv))
    fprintf (stderr,
             "libguestfs: uncaught OCaml exception in event callback: %s",
             caml_format_exception (Extract_exception (rv)));

  CAMLreturn0;
}

static void
event_callback_wrapper (guestfs_h *g,
                        void *data,
                        uint64_t event,
                        int event_handle,
                        int flags,
                        const char *buf, size_t buf_len,
                        const uint64_t *array, size_t array_len)
{
  /* Ensure we are holding the GC lock before any GC operations are
   * possible. (RHBZ#725824)
   */
  caml_leave_blocking_section ();

  event_callback_wrapper_locked (g, data, event, event_handle, flags,
                                 buf, buf_len, array, array_len);

  caml_enter_blocking_section ();
}

value
ocaml_guestfs_last_errno (value gv)
{
  CAMLparam1 (gv);
  CAMLlocal1 (rv);
  int r;
  guestfs_h *g;

  g = Guestfs_val (gv);
  if (g == NULL)
    ocaml_guestfs_raise_closed ("last_errno");

  r = guestfs_last_errno (g);

  rv = Val_int (r);
  CAMLreturn (rv);
}

/* NB: This is and must remain a "noalloc" function. */
value
ocaml_guestfs_user_cancel (value gv)
{
  guestfs_h *g = Guestfs_val (gv);
  if (g)
    guestfs_user_cancel (g);
  return Val_unit;
}
