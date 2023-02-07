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

/**
 * Helper functions for the actions code in F<lib/actions-*.c>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

/* Check the return message from a call for validity. */
int
guestfs_int_check_reply_header (guestfs_h *g,
				const struct guestfs_message_header *hdr,
				unsigned int proc_nr, unsigned int serial)
{
  if (hdr->prog != GUESTFS_PROGRAM) {
    error (g, "wrong program (%u/%d)", hdr->prog, GUESTFS_PROGRAM);
    return -1;
  }
  if (hdr->vers != GUESTFS_PROTOCOL_VERSION) {
    error (g, "wrong protocol version (%u/%d)",
           hdr->vers, GUESTFS_PROTOCOL_VERSION);
    return -1;
  }
  if (hdr->direction != GUESTFS_DIRECTION_REPLY) {
    error (g, "unexpected message direction (%d/%d)",
           (int) hdr->direction, GUESTFS_DIRECTION_REPLY);
    return -1;
  }
  if (hdr->proc != proc_nr) {
    error (g, "unexpected procedure number (%d/%u)", (int) hdr->proc, proc_nr);
    return -1;
  }
  if (hdr->serial != serial) {
    error (g, "unexpected serial (%u/%u)", hdr->serial, serial);
    return -1;
  }

  return 0;
}

/* Check the appliance is up when running a daemon_function. */
int
guestfs_int_check_appliance_up (guestfs_h *g, const char *caller)
{
  if (g->state == CONFIG || g->state == LAUNCHING) {
    error (g, "%s: call launch before using this function\n(in guestfish, don't forget to use the 'run' command)",
           caller);
    return -1;
  }
  return 0;
}

/* Convenience wrapper for tracing. */
void
guestfs_int_trace_open (struct trace_buffer *tb)
{
  tb->buf = NULL;
  tb->len = 0;
  tb->fp = open_memstream (&tb->buf, &tb->len);
  if (tb->fp)
    tb->opened = true;
  else {
    tb->opened = false;
    /* Fall back to writing messages to stderr. */
    free (tb->buf);
    tb->buf = NULL;
    tb->fp = stderr;
  }
}

void
guestfs_int_trace_send_line (guestfs_h *g, struct trace_buffer *tb)
{
  if (tb->opened) {
    fclose (tb->fp);
    tb->fp = NULL;
    guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_TRACE, tb->buf, tb->len);
    free (tb->buf);
    tb->buf = NULL;
  }
}
