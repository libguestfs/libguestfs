/* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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
guestfs_int_warning (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_WARNING, msg, len);
}

/* Debug messages. */
void
guestfs_int_debug (guestfs_h *g, const char *fs, ...)
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

  guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, msg, len);
}

/* Call trace messages.  These are enabled by setting g->trace, and
 * calls to this function should only happen from the generated code
 * in src/actions.c
 */
void
guestfs_int_trace (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_TRACE, msg, len);
}

void
guestfs_int_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int err;

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  /* set_last_error first so that the callback can access the error
   * message and errno through the handle if it wishes.
   */
  set_last_error (g, errnum, msg);
  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
}

void
guestfs_int_perrorf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *msg = NULL;
  int errnum = errno;
  int err;
  char buf[256];

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

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
    guestfs_int_init_error_handler (g);
}

static void default_error_cb (guestfs_h *g, void *data, const char *msg);

void
guestfs_int_init_error_handler (guestfs_h *g)
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
guestfs_int_print_BufferIn (FILE *out, const char *buf, size_t buf_size)
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
guestfs_int_print_BufferOut (FILE *out, const char *buf, size_t buf_size)
{
  guestfs_int_print_BufferIn (out, buf, buf_size);
}

/* Some standard error messages for common failures. */

/* Launch failed.  Since this is the most common error seen by people
 * who have installation problems, buggy qemu, etc, and since no one
 * reads the FAQ, describe in this error message what resources are
 * available to debug launch problems.
 */
void
guestfs_int_launch_failed_error (guestfs_h *g)
{
  if (g->verbose)
    error (g, _("guestfs_launch failed, see earlier error messages"));
  else
    error (g, _(
"guestfs_launch failed.\n"
"This usually means the libguestfs appliance failed to start or crashed.\n"
"See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs\n"
"or run 'libguestfs-test-tool' and post the *complete* output into a\n"
"bug report or message to the libguestfs mailing list."));
}

/* As above, but for crashes that occur after launch. */
void
guestfs_int_unexpected_close_error (guestfs_h *g)
{
  if (g->verbose)
    error (g, _("appliance closed the connection unexpectedly, see earlier error messages"));
  else
    error (g, _(
"appliance closed the connection unexpectedly.\n"
"This usually means the libguestfs appliance crashed.\n"
"See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs\n"
"for information about how to debug libguestfs and report bugs."));
}

/* As above, but for appliance kernel hanging. */
void
guestfs_int_launch_timeout (guestfs_h *g)
{
  if (g->verbose)
    error (g, _("appliance launch timed out, see earlier error messages"));
  else
    error (g, _(
"appliance launch timed out.\n"
"This usually means the kernel or appliance hung during launch.\n"
"See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs\n"
"for information about how to debug libguestfs and report bugs."));
}

/* External command failed. */
void
guestfs_int_external_command_failed (guestfs_h *g, int status,
                                   const char *cmd_name, const char *extra)
{
  size_t len = 80 + strlen (cmd_name);
  char status_string[len];

  guestfs_int_exit_status_to_string (status, cmd_name, status_string, len);

  if (g->verbose) {
    if (!extra)
      error (g, _("%s, see debug messages above"), status_string);
    else
      error (g, _("%s: %s: %s, see debug messages above"),
             cmd_name, extra, status_string);
  }
  else {
    if (!extra)
      error (g, _(
"%s.\n"
"To see full error messages you may need to enable debugging.\n"
"See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs"),
             status_string);
    else
      error (g, _(
"%s: %s: %s.\n"
"To see full error messages you may need to enable debugging.\n"
"See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs"),
             cmd_name, extra, status_string);
  }
}
