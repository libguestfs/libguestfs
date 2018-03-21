/* libguestfs
 * Copyright (C) 2015 Red Hat Inc.
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

/* Test that allocating lots of heap in the main program doesn't cause
 * libguestfs to fail when it runs qemu-img.  When we call qemu-img,
 * after forking but before execing, we set RLIMIT_AS to 1 GB.  If the
 * main program is using more than 1 GB, then any malloc or stack
 * extension will fail.  We get away with this by calling exec
 * immediately after setting the rlimit, but it only just works, and
 * this test is designed to catch any regressions.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>

#include "guestfs.h"
#include "guestfs-utils.h"

int
main (int argc, char *argv[])
{
  const char *s;
  guestfs_h *g;
  char *mem, *fmt;
  char tmpfile[32];
  int tmpfilefd;

  /* Allow the test to be skipped. */
  s = getenv ("SKIP_TEST_BIG_HEAP");
  if (s && STRNEQ (s, "")) {
    printf ("%s: test skipped because environment variable is set\n",
            argv[0]);
    exit (77);
  }

  snprintf (tmpfile, sizeof tmpfile, "test-big-heap.XXXXXX");

  /* Make sure we're using > 1GB in the main process.  This test won't
   * work on 32 bit platforms, because we can't allocate 2GB of
   * contiguous memory.  Therefore skip the test if the calloc call
   * fails.
   */
  /* XXX This test also fails for machines with ~ 2 GB of RAM,
   * because the 1.1 GB allocation succeeds here, but the fork
   * fails (since it will require around 2 * 1.1 GB).
   */
  mem = calloc (1100, 1024 * 1024);
  if (mem == NULL) {
    fprintf (stderr,
             "%s: test skipped because cannot allocate enough "
             "contiguous heap\n",
             argv[0]);
    exit (77);
  }

  /* Create an empty temporary file for qemu-img. */
  tmpfilefd = mkstemp (tmpfile);
  if (tmpfilefd == -1) {
    fprintf (stderr, "%s: mkstemp failed: %m\n", argv[0]);
    exit (EXIT_FAILURE);
  }
  close (tmpfilefd);

  g = guestfs_create ();

  /* Do something which forks qemu-img subprocess. */
  fmt = guestfs_disk_format (g, tmpfile);
  unlink (tmpfile);
  if (fmt == NULL) {
    /* Test failed. */
    fprintf (stderr, "%s: unexpected failure of test, see earlier messages\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }

  if (STRNEQ (fmt, "raw")) {
    /* Test failed. */
    fprintf (stderr, "%s: unexpected output: expected 'raw' actual '%s'\n",
             argv[0], fmt);
    exit (EXIT_FAILURE);
  }

  /* Test successful. */

  free (fmt);
  free (mem);
  exit (EXIT_SUCCESS);
}
