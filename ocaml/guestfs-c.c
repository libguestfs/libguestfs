/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <errno.h>

#include <guestfs.h>
#include "guestfs-utils.h"

#include <caml/config.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/printexc.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>

#include "guestfs-c.h"

static value **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);
static void event_callback_wrapper (guestfs_h *g, void *data, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

/* This macro was added in OCaml 3.10.  Backport for earlier versions. */
#ifndef CAMLreturnT
#define CAMLreturnT(type, result) do{		\
    type caml__temp_result = (result);		\
    caml_local_roots = caml__frame;		\
    return (caml__temp_result);			\
  }while(0)
#endif

/* These prototypes are solely to quiet gcc warning.  */
value guestfs_int_ocaml_create (value environmentv, value close_on_exitv, value unitv);
value guestfs_int_ocaml_close (value gv);
value guestfs_int_ocaml_set_event_callback (value gv, value closure, value events);
value guestfs_int_ocaml_delete_event_callback (value gv, value eh);
value guestfs_int_ocaml_event_to_string (value events);
value guestfs_int_ocaml_last_errno (value gv);

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
    size_t len;
    value **roots = get_all_event_callbacks (g, &len);

    /* Close the handle: this could invoke callbacks from the list
     * above, which is why we don't want to delete them before
     * closing the handle.
     */
    guestfs_close (g);

    /* Now unregister the global roots. */
    if (roots && len > 0) {
      size_t i;
      for (i = 0; i < len; ++i) {
        caml_remove_generational_global_root (roots[i]);
        free (roots[i]);
      }
      free (roots);
    }
  }
}

static struct custom_operations guestfs_custom_operations = {
  (char *) "guestfs_custom_operations",
  guestfs_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
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
guestfs_int_ocaml_raise_error (guestfs_h *g, const char *func)
{
  CAMLparam0 ();
  CAMLlocal1 (v);
  const char *msg;

  msg = guestfs_last_error (g);

  if (msg)
    v = caml_copy_string (msg);
  else
    v = caml_copy_string (func);
  caml_raise_with_arg (*caml_named_value ("guestfs_int_ocaml_error"), v);
  CAMLnoreturn;
}

void
guestfs_int_ocaml_raise_closed (const char *func)
{
  CAMLparam0 ();
  CAMLlocal1 (v);

  v = caml_copy_string (func);
  caml_raise_with_arg (*caml_named_value ("guestfs_int_ocaml_closed"), v);
  CAMLnoreturn;
}

/* Guestfs.create */
value
guestfs_int_ocaml_create (value environmentv, value close_on_exitv, value unitv)
{
  CAMLparam3 (environmentv, close_on_exitv, unitv);
  CAMLlocal1 (gv);
  unsigned flags = 0;
  guestfs_h *g;

  if (environmentv != Val_int (0) &&
      !Bool_val (Field (environmentv, 0)))
    flags |= GUESTFS_CREATE_NO_ENVIRONMENT;

  if (close_on_exitv != Val_int (0) &&
      !Bool_val (Field (close_on_exitv, 0)))
    flags |= GUESTFS_CREATE_NO_CLOSE_ON_EXIT;

  g = guestfs_create_flags (flags);
  if (g == NULL)
    caml_failwith ("failed to create guestfs handle");

  guestfs_set_error_handler (g, NULL, NULL);

  gv = Val_guestfs (g);

  CAMLreturn (gv);
}

/* Guestfs.close */
value
guestfs_int_ocaml_close (value gv)
{
  CAMLparam1 (gv);

  guestfs_finalize (gv);

  /* So we don't double-free in the finalizer. */
  Guestfs_val (gv) = NULL;

  CAMLreturn (Val_unit);
}

/* Copy string array value. */
char **
guestfs_int_ocaml_strings_val (guestfs_h *g, value sv)
{
  CAMLparam1 (sv);
  char **r;
  size_t i;

  r = malloc (sizeof (char *) * (Wosize_val (sv) + 1));
  if (r == NULL) caml_raise_out_of_memory ();
  for (i = 0; i < Wosize_val (sv); ++i) {
    r[i] = strdup (String_val (Field (sv, i)));
    if (r[i] == NULL) caml_raise_out_of_memory ();
  }
  r[i] = NULL;

  CAMLreturnT (char **, r);
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
value
guestfs_int_ocaml_set_event_callback (value gv, value closure, value events)
{
  CAMLparam3 (gv, closure, events);
  char key[64];
  int eh;
  uint64_t event_bitmask;

  guestfs_h *g = Guestfs_val (gv);

  event_bitmask = event_bitmask_of_event_list (events);

  value *root = malloc (sizeof *root);
  if (root == NULL) caml_raise_out_of_memory ();
  *root = closure;

  eh = guestfs_set_event_callback (g, event_callback_wrapper,
                                   event_bitmask, 0, root);

  if (eh == -1) {
    free (root);
    guestfs_int_ocaml_raise_error (g, "set_event_callback");
  }

  caml_register_generational_global_root (root);

  snprintf (key, sizeof key, "_ocaml_event_%d", eh);
  guestfs_set_private (g, key, root);

  CAMLreturn (Val_int (eh));
}

/* Guestfs.delete_event_callback */
value
guestfs_int_ocaml_delete_event_callback (value gv, value ehv)
{
  CAMLparam2 (gv, ehv);
  char key[64];
  const int eh = Int_val (ehv);

  guestfs_h *g = Guestfs_val (gv);

  snprintf (key, sizeof key, "_ocaml_event_%d", eh);

  value *root = guestfs_get_private (g, key);
  if (root) {
    caml_remove_generational_global_root (root);
    free (root);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }

  CAMLreturn (Val_unit);
}

/* Guestfs.event_to_string */
value
guestfs_int_ocaml_event_to_string (value events)
{
  CAMLparam1 (events);
  CAMLlocal1 (rv);
  char *r;
  uint64_t event_bitmask;

  event_bitmask = event_bitmask_of_event_list (events);

  r = guestfs_event_to_string (event_bitmask);
  if (r == NULL)
    unix_error (errno, (char *) "Guestfs.event_to_string", Nothing);

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
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

  /* No events, so no need to allocate anything. */
  if (*len_rtn == 0)
    return NULL;

  /* Copy them into the return array. */
  r = malloc (sizeof (value *) * (*len_rtn));
  if (r == NULL) caml_raise_out_of_memory ();

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
  CAMLlocal4 (evv, ehv, bufv, arrayv);
  CAMLlocal2 (rv, v);
  size_t i;

  /* Only one bit should be set in 'event'.  Which one? */
  evv = Val_int (event_bitmask_to_event (event));

  ehv = Val_int (event_handle);

  bufv = caml_alloc_initialized_string (buf_len, buf);

  arrayv = caml_alloc (array_len, 0);
  for (i = 0; i < array_len; ++i) {
    v = caml_copy_int64 (array[i]);
    Store_field (arrayv, i, v);
  }

  value args[4] = { evv, ehv, bufv, arrayv };

  rv = caml_callbackN_exn (*(value*)data, 4, args);

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
guestfs_int_ocaml_last_errno (value gv)
{
  CAMLparam1 (gv);
  CAMLlocal1 (rv);
  int r;
  guestfs_h *g;

  g = Guestfs_val (gv);
  if (g == NULL)
    guestfs_int_ocaml_raise_closed ("last_errno");

  r = guestfs_last_errno (g);

  rv = Val_int (r);
  CAMLreturn (rv);
}
