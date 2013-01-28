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
#include <stdarg.h>
#include <string.h>
#include <errno.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"

const char *
guestfs_last_error (guestfs_h *g)
{
  return g->last_error;
}

int
guestfs_last_errno (guestfs_h *g)
{
  return g->last_errnum;
}

static void
set_last_error (guestfs_h *g, int errnum, const char *msg)
{
  free (g->last_error);
  g->last_error = strdup (msg);
  g->last_errnum = errnum;
}

/* Warning are printed unconditionally.  We try to make these rare.
 * Generally speaking, a warning should either be an error, or if it's
 * not important for end users then it should be a debug message.
 */
void
guestfs___warning (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL, *msg2 = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  len = asprintf (&msg2, _("warning: %s"), msg);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, msg2, len);
}

/* Debug messages. */
void
guestfs___debug (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int len;

  /* The cpp macro "debug" has already checked that g->verbose is true
   * before calling this function, but we check it again just in case
   * anyone calls this function directly.
   */
  if (!g->verbose)
    return;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, msg, len);
}

/* Call trace messages.  These are enabled by setting g->trace, and
 * calls to this function should only happen from the generated code
 * in src/actions.c
 */
void
guestfs___trace (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_TRACE, msg, len);
}

void
guestfs_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  /* set_last_error first so that the callback can access the error
   * message and errno through the handle if it wishes.
   */
  set_last_error (g, errnum, msg);
  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
}

void
guestfs_perrorf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int errnum = errno;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  char buf[256];
  strerror_r (errnum, buf, sizeof buf);

  msg = safe_realloc (g, msg, strlen (msg) + 2 + strlen (buf) + 1);
  strcat (msg, ": ");
  strcat (msg, buf);

  /* set_last_error first so that the callback can access the error
   * message and errno through the handle if it wishes.
   */
  set_last_error (g, errnum, msg);
  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
}

void
guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb cb)
{
  g->abort_cb = cb;
}

guestfs_abort_cb
guestfs_get_out_of_memory_handler (guestfs_h *g)
{
  return g->abort_cb;
}

void
guestfs_set_error_handler (guestfs_h *g,
                           guestfs_error_handler_cb cb, void *data)
{
  g->error_cb = cb;
  g->error_cb_data = data;
}

guestfs_error_handler_cb
guestfs_get_error_handler (guestfs_h *g, void **data_rtn)
{
  if (data_rtn) *data_rtn = g->error_cb_data;
  return g->error_cb;
}

void
guestfs_push_error_handler (guestfs_h *g,
                            guestfs_error_handler_cb cb, void *data)
{
  struct error_cb_stack *old_stack;

  old_stack = g->error_cb_stack;
  g->error_cb_stack = safe_malloc (g, sizeof (struct error_cb_stack));
  g->error_cb_stack->next = old_stack;
  g->error_cb_stack->error_cb = g->error_cb;
  g->error_cb_stack->error_cb_data = g->error_cb_data;

  guestfs_set_error_handler (g, cb, data);
}

void
guestfs_pop_error_handler (guestfs_h *g)
{
  struct error_cb_stack *next_stack;

  if (g->error_cb_stack) {
    next_stack = g->error_cb_stack->next;
    guestfs_set_error_handler (g, g->error_cb_stack->error_cb,
                               g->error_cb_stack->error_cb_data);
    free (g->error_cb_stack);
    g->error_cb_stack = next_stack;
  }
  else
    guestfs___init_error_handler (g);
}

static void default_error_cb (guestfs_h *g, void *data, const char *msg);

void
guestfs___init_error_handler (guestfs_h *g)
{
  g->error_cb = default_error_cb;
  g->error_cb_data = NULL;
}

static void
default_error_cb (guestfs_h *g, void *data, const char *msg)
{
  fprintf (stderr, _("libguestfs: error: %s\n"), msg);
}

/* When tracing, be careful how we print BufferIn parameters which
 * usually contain large amounts of binary data (RHBZ#646822).
 */
void
guestfs___print_BufferIn (FILE *out, const char *buf, size_t buf_size)
{
  size_t i;
  size_t orig_size = buf_size;

  if (buf_size > 256)
    buf_size = 256;

  fputc ('"', out);

  for (i = 0; i < buf_size; ++i) {
    if (c_isprint (buf[i]))
      fputc (buf[i], out);
    else
      fprintf (out, "\\x%02x", (unsigned char) buf[i]);
  }

  fputc ('"', out);

  if (orig_size > buf_size)
    fprintf (out,
             _("<truncated, original size %zu bytes>"), orig_size);
}

void
guestfs___print_BufferOut (FILE *out, const char *buf, size_t buf_size)
{
  guestfs___print_BufferIn (out, buf, buf_size);
}
