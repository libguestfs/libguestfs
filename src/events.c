/* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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

#define _BSD_SOURCE /* for mkdtemp, usleep */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <assert.h>
#include <string.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"

int
guestfs_set_event_callback (guestfs_h *g,
                            guestfs_event_callback cb,
                            uint64_t event_bitmask,
                            int flags,
                            void *opaque)
{
  if (flags != 0) {
    error (g, "flags parameter should be passed as 0 to this function");
    return -1;
  }

  /* We cast size_t to int which is not always safe for large numbers,
   * and in any case if a program is registering a huge number of
   * callbacks then we'd want to look at using an alternate data
   * structure in place of a linear list.
   */
  if (g->nr_events >= 1000) {
    error (g, "too many event callbacks registered");
    return -1;
  }

  int event_handle = (int) g->nr_events;
  g->events =
    guestfs_safe_realloc (g, g->events,
                          (g->nr_events+1) * sizeof (struct event));
  g->nr_events++;

  g->events[event_handle].event_bitmask = event_bitmask;
  g->events[event_handle].cb = cb;
  g->events[event_handle].opaque = opaque;
  g->events[event_handle].opaque2 = NULL;

  return event_handle;
}

void
guestfs_delete_event_callback (guestfs_h *g, int event_handle)
{
  if (event_handle < 0 || event_handle >= (int) g->nr_events)
    return;

  /* Set the event_bitmask to 0, which will ensure that this callback
   * cannot match any event and therefore cannot be called.
   */
  g->events[event_handle].event_bitmask = 0;
}

/* Functions to generate an event with various payloads. */

void
guestfs___call_callbacks_void (guestfs_h *g, uint64_t event)
{
  size_t i;

  for (i = 0; i < g->nr_events; ++i)
    if ((g->events[i].event_bitmask & event) != 0)
      g->events[i].cb (g, g->events[i].opaque, event, i, 0, NULL, 0, NULL, 0);

  /* All events with payload type void are discarded if no callback
   * was registered.
   */
}

void
guestfs___call_callbacks_message (guestfs_h *g, uint64_t event,
                                  const char *buf, size_t buf_len)
{
  size_t i, count = 0;

  for (i = 0; i < g->nr_events; ++i)
    if ((g->events[i].event_bitmask & event) != 0) {
      g->events[i].cb (g, g->events[i].opaque, event, i, 0,
                       buf, buf_len, NULL, 0);
      count++;
    }

  /* Emulate the old-style handlers.  Callers can override
   * print-on-stderr simply by registering a callback.
   */
  if (count == 0 &&
      (event == GUESTFS_EVENT_APPLIANCE ||
       event == GUESTFS_EVENT_LIBRARY ||
       event == GUESTFS_EVENT_TRACE) &&
      (g->verbose || event == GUESTFS_EVENT_TRACE)) {
    int from_appliance = event == GUESTFS_EVENT_APPLIANCE;
    size_t i, i0;

    /* APPLIANCE =>  <buf>
     * LIBRARY =>    libguestfs: <buf>\n
     * TRACE =>      libguestfs: trace: <buf>\n  (RHBZ#673479)
     */

    if (event != GUESTFS_EVENT_APPLIANCE)
      fputs ("libguestfs: ", stderr);

    if (event == GUESTFS_EVENT_TRACE)
      fputs ("trace: ", stderr);

    /* Special or non-printing characters in the buffer must be
     * escaped (RHBZ#731744).  The buffer can contain any 8 bit
     * character, even \0.
     *
     * Handling of \n and \r characters is complex:
     *
     * Case 1: Messages from the appliance: These messages already
     * contain \n and \r characters at logical positions, so we just
     * echo those out directly.
     *
     * Case 2: Messages from other sources: These messages should NOT
     * contain \n or \r.  If they do, it is escaped.  However we also
     * need to print a real end of line after these messages.
     *
     * RHBZ#802109: Because stderr is usually not buffered, avoid
     * single 'putc' calls (which translate to a 1 byte write), and
     * try to send longest possible strings in single fwrite calls
     * (thanks to Jim Meyering for the basic approach).
     */
#define NO_ESCAPING(c) \
      (c_isprint ((c)) || (from_appliance && ((c) == '\n' || (c) == '\r')))

    for (i = 0; i < buf_len; ++i) {
      if (NO_ESCAPING (buf[i])) {
        i0 = i;
        while (i < buf_len && NO_ESCAPING (buf[i]))
          ++i;
        fwrite (&buf[i0], 1, i-i0, stderr);
        /* Adjust i so that next time around the loop, the next
         * non-printing character will be displayed.
         */
        if (i < buf_len)
          --i;
      } else {
        switch (buf[i]) {
        case '\0': fputs ("\\0", stderr); break;
        case '\a': fputs ("\\a", stderr); break;
        case '\b': fputs ("\\b", stderr); break;
        case '\f': fputs ("\\f", stderr); break;
        case '\n': fputs ("\\n", stderr); break;
        case '\r': fputs ("\\r", stderr); break;
        case '\t': fputs ("\\t", stderr); break;
        case '\v': fputs ("\\v", stderr); break;
        default:
          fprintf (stderr, "\\x%x", (unsigned char) buf[i]);
        }
      }
    }

    if (!from_appliance)
      putc ('\n', stderr);
  }
}

void
guestfs___call_callbacks_array (guestfs_h *g, uint64_t event,
                                const uint64_t *array, size_t array_len)
{
  size_t i;

  for (i = 0; i < g->nr_events; ++i)
    if ((g->events[i].event_bitmask & event) != 0)
      g->events[i].cb (g, g->events[i].opaque, event, i, 0,
                       NULL, 0, array, array_len);

  /* All events with payload type array are discarded if no callback
   * was registered.
   */
}

/* Emulate old-style callback API.
 *
 * There were no event handles, so multiple callbacks per event were
 * not supported.  Calling the same 'guestfs_set_*_callback' function
 * would replace the existing event.  Calling it with cb == NULL meant
 * that the caller wanted to remove the callback.
 */

static void
replace_old_style_event_callback (guestfs_h *g,
                                  guestfs_event_callback cb,
                                  uint64_t event_bitmask,
                                  void *opaque,
                                  void *opaque2)
{
  size_t i;

  /* Use 'cb' pointer as a sentinel to replace the existing callback
   * for this event if one was registered previously.  Else append a
   * new event.
   */

  for (i = 0; i < g->nr_events; ++i)
    if (g->events[i].cb == cb) {
      if (opaque2 == NULL) {
        /* opaque2 (the original callback) is NULL, which in the
         * old-style API meant remove the callback.
         */
        guestfs_delete_event_callback (g, i);
        return;
      }

      goto replace;
    }

  if (opaque2 == NULL)
    return; /* see above */

  /* i == g->nr_events */
  g->events =
    guestfs_safe_realloc (g, g->events,
                          (g->nr_events+1) * sizeof (struct event));
  g->nr_events++;

 replace:
  g->events[i].event_bitmask = event_bitmask;
  g->events[i].cb = cb;
  g->events[i].opaque = opaque;
  g->events[i].opaque2 = opaque2;
}

static void
log_message_callback_wrapper (guestfs_h *g,
                              void *opaque,
                              uint64_t event,
                              int event_handle,
                              int flags,
                              const char *buf, size_t buf_len,
                              const uint64_t *array, size_t array_len)
{
  guestfs_log_message_cb cb = g->events[event_handle].opaque2;
  /* Note that the old callback declared the message buffer as
   * (char *, int).  I sure hope message buffers aren't too large
   * and that callers aren't writing to them. XXX
   */
  cb (g, opaque, (char *) buf, (int) buf_len);
}

void
guestfs_set_log_message_callback (guestfs_h *g,
                                  guestfs_log_message_cb cb, void *opaque)
{
  replace_old_style_event_callback (g, log_message_callback_wrapper,
                                    GUESTFS_EVENT_APPLIANCE,
                                    opaque, cb);
}

static void
subprocess_quit_callback_wrapper (guestfs_h *g,
                                  void *opaque,
                                  uint64_t event,
                                  int event_handle,
                                  int flags,
                                  const char *buf, size_t buf_len,
                                  const uint64_t *array, size_t array_len)
{
  guestfs_subprocess_quit_cb cb = g->events[event_handle].opaque2;
  cb (g, opaque);
}

void
guestfs_set_subprocess_quit_callback (guestfs_h *g,
                                      guestfs_subprocess_quit_cb cb, void *opaque)
{
  replace_old_style_event_callback (g, subprocess_quit_callback_wrapper,
                                    GUESTFS_EVENT_SUBPROCESS_QUIT,
                                    opaque, cb);
}

static void
launch_done_callback_wrapper (guestfs_h *g,
                              void *opaque,
                              uint64_t event,
                              int event_handle,
                              int flags,
                              const char *buf, size_t buf_len,
                              const uint64_t *array, size_t array_len)
{
  guestfs_launch_done_cb cb = g->events[event_handle].opaque2;
  cb (g, opaque);
}

void
guestfs_set_launch_done_callback (guestfs_h *g,
                                  guestfs_launch_done_cb cb, void *opaque)
{
  replace_old_style_event_callback (g, launch_done_callback_wrapper,
                                    GUESTFS_EVENT_LAUNCH_DONE,
                                    opaque, cb);
}

static void
close_callback_wrapper (guestfs_h *g,
                        void *opaque,
                        uint64_t event,
                        int event_handle,
                        int flags,
                        const char *buf, size_t buf_len,
                        const uint64_t *array, size_t array_len)
{
  guestfs_close_cb cb = g->events[event_handle].opaque2;
  cb (g, opaque);
}

void
guestfs_set_close_callback (guestfs_h *g,
                            guestfs_close_cb cb, void *opaque)
{
  replace_old_style_event_callback (g, close_callback_wrapper,
                                    GUESTFS_EVENT_CLOSE,
                                    opaque, cb);
}

static void
progress_callback_wrapper (guestfs_h *g,
                           void *opaque,
                           uint64_t event,
                           int event_handle,
                           int flags,
                           const char *buf, size_t buf_len,
                           const uint64_t *array, size_t array_len)
{
  guestfs_progress_cb cb = g->events[event_handle].opaque2;
  assert (array_len >= 4);
  cb (g, opaque, (int) array[0], (int) array[1], array[2], array[3]);
}

void
guestfs_set_progress_callback (guestfs_h *g,
                               guestfs_progress_cb cb, void *opaque)
{
  replace_old_style_event_callback (g, progress_callback_wrapper,
                                    GUESTFS_EVENT_PROGRESS,
                                    opaque, cb);
}
