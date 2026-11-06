/* libguestfs
 * Copyright (C) 2009-2026 Red Hat Inc.
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

/* Test the kill-procs API. */

#include <config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  /* This API only works on Linux. */
#ifndef __linux__
  fprintf (stderr, "%s: Test skipped because not Linux\n", argv[0]);
  exit (77);
#else /* __linux__ */
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_scratch (g, 1024*1024*1024, -1) == -1 ||
      guestfs_launch (g) == -1 ||
      guestfs_mkfs (g, "ext4", "/dev/sda") == -1 ||
      guestfs_mount (g, "/dev/sda", "/") == -1 ||
      guestfs_upload (g, "c-api/test-sleep", "/sleep") == -1 ||
      guestfs_chmod (g, 0777, "/sleep") == -1)
    exit (EXIT_FAILURE);

  /* Create a long-lived process. */
  char *cmd1[] = { "/sleep", NULL };
  char *out;
  out = guestfs_command (g, cmd1);
  if (out == NULL)
    exit (EXIT_FAILURE);
  free (out);

  /* Check it exists. */
  char *cmd2[] =
    { "ps ax > /tmp/procs && grep '[s]leep' /tmp/procs ||:", NULL };
  out = guestfs_debug (g, "sh", cmd2);
  if (!out || strlen (out) == 0) {
    fprintf (stderr, "%s: ERROR: 'sleep' is not running\n", argv[0]);
    exit (EXIT_FAILURE);
  }
  free (out);

  /* Kill procs. */
  if (guestfs_kill_procs (g) == -1)
    exit (EXIT_FAILURE);

  /* Wait a bit in case kill takes some time. */
  sleep (5);
  out = guestfs_debug (g, "sh", cmd2);
  if (out == NULL)
    exit (EXIT_FAILURE);
  if (strlen (out) > 0) {
    fprintf (stderr, "%s", out);
    fprintf (stderr,
             "%s: ERROR: 'sleep' is running, expected it to be killed\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }
  free (out);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
#endif /* __linux__ */
}
