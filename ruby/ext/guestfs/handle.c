/* libguestfs ruby bindings
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
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include "actions.h"

/* Ruby has a mark-sweep garbage collector and performs imprecise
 * scanning of the stack to look for pointers.  Some implications
 * of this:
 * (1) Any VALUE stored in a stack location must be marked as
 *     volatile so that the compiler doesn't put it in a register.
 * (2) Anything at all on the stack that "looks like" a Ruby
 *     pointer could be followed, eg. buffers of random data.
 *     (See: https://bugzilla.redhat.com/show_bug.cgi?id=843188#c6)
 * We fix (1) by marking everything possible as volatile.
 */

static void event_callback_wrapper (guestfs_h *g, void *data, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);
static VALUE event_callback_wrapper_wrapper (VALUE argv);
static VALUE event_callback_handle_exception (VALUE not_used, VALUE exn);
static VALUE **get_all_event_callbacks (guestfs_h *g, size_t *len_rtn);

static void
free_handle (void *gvp)
{
  guestfs_h *g = gvp;

  if (g) {
    /* As in the OCaml binding, there is a nasty, difficult to
     * solve case here where the user deletes events in one of
     * the callbacks that we are about to invoke, resulting in
     * a double-free.  XXX
     */
    size_t len;
    VALUE **roots = get_all_event_callbacks (g, &len);

    /* Close the handle: this could invoke callbacks from the list
     * above, which is why we don't want to delete them before
     * closing the handle.
     */
    guestfs_close (g);

    /* Now unregister the global roots. */
    if (len > 0) {
      size_t i;
      for (i = 0; i < len; ++i) {
        rb_gc_unregister_address (roots[i]);
        free (roots[i]);
      }
      free (roots);
    }
  }
}

/* This is the ruby internal alloc function for the class.  We do nothing
 * here except allocate an object containing a NULL guestfs handle.
 * Note we cannot call guestfs_create here because we need the extra
 * parameters, which ruby passes via the initialize method (see next
 * function).
 */
VALUE
guestfs_int_ruby_alloc_handle (VALUE klass)
{
  guestfs_h *g = NULL;

  /* Wrap it, and make sure the close function is called when the
   * handle goes away.
   */
  return Data_Wrap_Struct (c_guestfs, NULL, free_handle, g);
}

static unsigned
parse_flags (int argc, VALUE *argv)
{
  volatile VALUE optargsv;
  unsigned flags = 0;
  volatile VALUE v;

  optargsv = argc == 1 ? argv[0] : rb_hash_new ();
  Check_Type (optargsv, T_HASH);

  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern ("environment")));
  if (v != Qnil && !RTEST (v))
    flags |= GUESTFS_CREATE_NO_ENVIRONMENT;
  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern ("close_on_exit")));
  if (v != Qnil && !RTEST (v))
    flags |= GUESTFS_CREATE_NO_CLOSE_ON_EXIT;

  return flags;
}

/*
 * call-seq:
 *   Guestfs::Guestfs.new([{:environment => false, :close_on_exit => false}]) -> Guestfs::Guestfs
 *
 * Call
 * {guestfs_create_flags}[http://libguestfs.org/guestfs.3.html#guestfs_create_flags]
 * to create a new libguestfs handle.  The handle is represented in
 * Ruby as an instance of the Guestfs::Guestfs class.
 */
VALUE
guestfs_int_ruby_initialize_handle (int argc, VALUE *argv, VALUE m)
{
  guestfs_h *g;
  unsigned flags;

  if (argc > 1)
    rb_raise (rb_eArgError, "expecting 0 or 1 arguments");

  /* Should have been set to NULL by prior call to alloc function. */
  assert (DATA_PTR (m) == NULL);

  flags = parse_flags (argc, argv);

  g = guestfs_create_flags (flags);
  if (!g)
    rb_raise (e_Error, "failed to create guestfs handle");

  DATA_PTR (m) = g;

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  return m;
}

/* For backwards compatibility. */
VALUE
guestfs_int_ruby_compat_create_handle (int argc, VALUE *argv, VALUE module)
{
  guestfs_h *g;
  unsigned flags;

  if (argc > 1)
    rb_raise (rb_eArgError, "expecting 0 or 1 arguments");

  flags = parse_flags (argc, argv);

  g = guestfs_create_flags (flags);
  if (!g)
    rb_raise (e_Error, "failed to create guestfs handle");

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  return Data_Wrap_Struct (c_guestfs, NULL, free_handle, g);
}

/*
 * call-seq:
 *   g.close() -> nil
 *
 * Call
 * {guestfs_close}[http://libguestfs.org/guestfs.3.html#guestfs_close]
 * to close the libguestfs handle.
 */
VALUE
guestfs_int_ruby_close_handle (VALUE gv)
{
  guestfs_h *g;
  Data_Get_Struct (gv, guestfs_h, g);

  /* Clear the data pointer first so there's no chance of a double
   * close if a close callback does something bad like calling exit.
   */
  DATA_PTR (gv) = NULL;
  free_handle (g);

  return Qnil;
}

/*
 * call-seq:
 *   g.set_event_callback(cb, event_bitmask) -> event_handle
 *
 * Call
 * {guestfs_set_event_callback}[http://libguestfs.org/guestfs.3.html#guestfs_set_event_callback]
 * to register an event callback.  This returns an event handle.
 */
VALUE
guestfs_int_ruby_set_event_callback (VALUE gv, VALUE cbv, VALUE event_bitmaskv)
{
  guestfs_h *g;
  uint64_t event_bitmask;
  int eh;
  VALUE *root;
  char key[64];

  Data_Get_Struct (gv, guestfs_h, g);

  event_bitmask = NUM2ULL (event_bitmaskv);

  root = malloc (sizeof *root);
  if (root == NULL)
    rb_raise (rb_eNoMemError, "malloc: %m");
  *root = cbv;

  eh = guestfs_set_event_callback (g, event_callback_wrapper,
                                   event_bitmask, 0, root);
  if (eh == -1) {
    free (root);
    rb_raise (e_Error, "%s", guestfs_last_error (g));
  }

  rb_gc_register_address (root);

  snprintf (key, sizeof key, "_ruby_event_%d", eh);
  guestfs_set_private (g, key, root);

  return INT2NUM (eh);
}

/*
 * call-seq:
 *   g.delete_event_callback(event_handle) -> nil
 *
 * Call
 * {guestfs_delete_event_callback}[http://libguestfs.org/guestfs.3.html#guestfs_delete_event_callback]
 * to delete an event callback.
 */
VALUE
guestfs_int_ruby_delete_event_callback (VALUE gv, VALUE event_handlev)
{
  guestfs_h *g;
  char key[64];
  const int eh = NUM2INT (event_handlev);
  VALUE *root;

  Data_Get_Struct (gv, guestfs_h, g);

  snprintf (key, sizeof key, "_ruby_event_%d", eh);

  root = guestfs_get_private (g, key);
  if (root) {
    rb_gc_unregister_address (root);
    free (root);
    guestfs_set_private (g, key, NULL);
    guestfs_delete_event_callback (g, eh);
  }

  return Qnil;
}

/*
 * call-seq:
 *   Guestfs::Guestfs.event_to_string(events) -> string
 *
 * Call
 * {guestfs_event_to_string}[http://libguestfs.org/guestfs.3.html#guestfs_event_to_string]
 * to convert an event or event bitmask into a printable string.
 */
VALUE
guestfs_int_ruby_event_to_string (VALUE modulev, VALUE eventsv)
{
  uint64_t events;
  char *str;

  events = NUM2ULL (eventsv);
  str = guestfs_event_to_string (events);
  if (str == NULL)
    rb_raise (e_Error, "%s", strerror (errno));

  volatile VALUE rv = rb_str_new2 (str);
  free (str);

  return rv;
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
  size_t i;
  volatile VALUE eventv, event_handlev, bufv, arrayv;
  volatile VALUE argv[5];

  eventv = ULL2NUM (event);
  event_handlev = INT2NUM (event_handle);

  bufv = rb_str_new (buf, buf_len);

  arrayv = rb_ary_new2 (array_len);
  for (i = 0; i < array_len; ++i)
    rb_ary_push (arrayv, ULL2NUM (array[i]));

  /* This is a crap limitation of rb_rescue.
   * http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/~poffice/mail/ruby-talk/65698
   */
  argv[0] = * (VALUE *) data; /* function */
  argv[1] = eventv;
  argv[2] = event_handlev;
  argv[3] = bufv;
  argv[4] = arrayv;

  rb_rescue (event_callback_wrapper_wrapper, (VALUE) argv,
             event_callback_handle_exception, Qnil);
}

static VALUE
event_callback_wrapper_wrapper (VALUE argvv)
{
  VALUE *argv = (VALUE *) argvv;
  volatile VALUE fn, eventv, event_handlev, bufv, arrayv;

  fn = argv[0];

  /* Check the Ruby callback still exists.  For reasons which are not
   * fully understood, even though we registered this as a global root,
   * it is still possible for the callback to go away (fn value remains
   * but its type changes from T_DATA to T_NONE or T_ZOMBIE).
   * (RHBZ#733297, RHBZ#843188)
   */
  if (rb_type (fn) != T_NONE
#ifdef T_ZOMBIE
      && rb_type (fn) != T_ZOMBIE
#endif
      ) {
    eventv = argv[1];
    event_handlev = argv[2];
    bufv = argv[3];
    arrayv = argv[4];

    rb_funcall (fn, rb_intern ("call"), 4,
                eventv, event_handlev, bufv, arrayv);
  }

  return Qnil;
}

/* Callbacks aren't supposed to throw exceptions.  We just print the
 * exception on stderr and hope for the best.
 */
static VALUE
event_callback_handle_exception (VALUE not_used, VALUE exn)
{
  volatile VALUE message;

  message = rb_funcall (exn, rb_intern ("to_s"), 0);
  fprintf (stderr, "libguestfs: exception in callback: %s\n",
           StringValueCStr (message));

  return Qnil;
}

static VALUE **
get_all_event_callbacks (guestfs_h *g, size_t *len_rtn)
{
  VALUE **r;
  size_t i;
  const char *key;
  VALUE *root;

  /* Count the length of the array that will be needed. */
  *len_rtn = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, "_ruby_event_", strlen ("_ruby_event_")) == 0)
      (*len_rtn)++;
    root = guestfs_next_private (g, &key);
  }

  /* No events, so no need to allocate anything. */
  if (*len_rtn == 0)
    return NULL;

  /* Copy them into the return array. */
  r = malloc (sizeof (VALUE *) * (*len_rtn));
  if (r == NULL)
    rb_raise (rb_eNoMemError, "malloc: %m");

  i = 0;
  root = guestfs_first_private (g, &key);
  while (root != NULL) {
    if (strncmp (key, "_ruby_event_", strlen ("_ruby_event_")) == 0) {
      r[i] = root;
      i++;
    }
    root = guestfs_next_private (g, &key);
  }

  return r;
}
