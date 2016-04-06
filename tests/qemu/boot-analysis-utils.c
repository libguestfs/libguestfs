/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <error.h>
#include <errno.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "boot-analysis-utils.h"

void
get_time (struct timespec *ts)
{
  if (clock_gettime (CLOCK_REALTIME, ts) == -1)
    error (EXIT_FAILURE, errno, "clock_gettime: CLOCK_REALTIME");
}

int64_t
timespec_diff (const struct timespec *x, const struct timespec *y)
{
  int64_t nsec;

  nsec = (y->tv_sec - x->tv_sec) * UINT64_C(1000000000);
  nsec += y->tv_nsec - x->tv_nsec;
  return nsec;
}

void
test_info (guestfs_h *g, int nr_test_passes)
{
  const char *qemu = guestfs_get_hv (g);
  CLEANUP_FREE char *cmd = NULL;
  CLEANUP_FREE char *backend = NULL;

  /* Related to the test program. */
  printf ("test version: %s %s\n", PACKAGE_NAME, PACKAGE_VERSION_FULL);
  printf (" test passes: %d\n", nr_test_passes);

  /* Related to the host. */
  printf ("host version: ");
  fflush (stdout);
  ignore_value (system ("uname -a"));
  printf ("    host CPU: ");
  fflush (stdout);
  ignore_value (system ("perl -n -e 'if (/^model name.*: (.*)/) { print \"$1\\n\"; exit }' /proc/cpuinfo"));

  /* Related to qemu. */
  backend = guestfs_get_backend (g);
  printf ("     backend: %s\n", backend);
  printf ("        qemu: %s\n", qemu);
  printf ("qemu version: ");
  fflush (stdout);
  if (asprintf (&cmd, "%s -version", qemu) == -1)
    error (EXIT_FAILURE, errno, "asprintf");
  ignore_value (system (cmd));
  printf ("         smp: %d\n", guestfs_get_smp (g));
  printf ("     memsize: %d\n", guestfs_get_memsize (g));

  /* Related to the guest kernel.  Be nice to get the guest
   * kernel version here somehow (XXX).
   */
  printf ("      append: %s\n", guestfs_get_append (g) ? : "");
}
