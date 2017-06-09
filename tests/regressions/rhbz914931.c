/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Regression test for RHBZ#914931.  Simulate an appliance crash
 * during a FileIn operation.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>
#include <signal.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"
#include "guestfs-utils.h"

#include "getprogname.h"

int
main (int argc, char *argv[])
{
  struct sigaction sa;
  guestfs_h *g;
  int r;
  char *str;

  /* Allow this test to be skipped. */
  str = getenv ("SKIP_TEST_RHBZ914931");
  if (str && guestfs_int_is_true (str) > 0) {
    printf ("%s: test skipped because environment variable is set.\n",
            getprogname ());
    exit (77);
  }

  /* This test can fail with SIGPIPE (shows up as exit code 141)
   * unless we ignore that signal.
   */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGPIPE, &sa, NULL);

  g = guestfs_create ();
  if (!g)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Perform the upload-with-crash.  Prior to RHBZ#914931 being fixed,
   * this would also cause libguestfs (ie. us) to segfault.
   */
  r = guestfs_internal_rhbz914931 (g, "/dev/zero",
                                   5 /* seconds before appliance crash */);

  /* We expect that call to fail, not segfault. */
  assert (r == -1);

  /* Close the handle. */
  guestfs_close (g);

  /* It's success if we get this far without the program segfaulting. */
  exit (EXIT_SUCCESS);
}
