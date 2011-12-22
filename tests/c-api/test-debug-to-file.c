/* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Test that we can use the new event API to capture all debugging
 * messages to a file.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ignore-value.h"

#include "guestfs.h"

static void
debug_to_file (guestfs_h *g,
               void *opaque,
               uint64_t event,
               int event_handle,
               int flags,
               const char *buf, size_t buf_len,
               const uint64_t *array, size_t array_len)
{
  FILE *fp = opaque;

  ignore_value (fwrite (buf, 1, buf_len, fp));
}

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  const char *filename = "test.log";
  FILE *debugfp;

  debugfp = fopen (filename, "w");
  if (debugfp == NULL) {
    perror (filename);
    exit (EXIT_FAILURE);
  }

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  if (guestfs_set_event_callback
      (g, debug_to_file,
       GUESTFS_EVENT_LIBRARY|GUESTFS_EVENT_APPLIANCE|GUESTFS_EVENT_TRACE,
       0, debugfp) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_set_verbose (g, 1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_set_trace (g, 1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
