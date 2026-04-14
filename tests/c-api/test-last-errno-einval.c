/* libguestfs
 * Copyright (C) 2010-2026 Red Hat Inc.
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

/* Test that OCaml Invalid_argument exceptions return EINVAL. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int r, err;
  const char *feature[] = { "xfs", NULL };

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  guestfs_set_verbose (g, 1);
  guestfs_set_trace (g, 1);

  if (guestfs_add_drive_scratch (g, 524288000, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  if (!guestfs_feature_available (g, (char **) feature)) {
    printf ("skipping test because xfs is not available\n");
    guestfs_close (g);
    exit (77);
  }

  if (guestfs_mkfs (g, "xfs", "/dev/sda") == -1)
    exit (EXIT_FAILURE);

  /* Run xfs_repair with some bogus parameters.  We expect that it
   * will fail with EINVAL.
   */
  r = guestfs_xfs_repair (g, "/dev/sda",
                          GUESTFS_XFS_REPAIR_MAXMEM, UINT64_C(-100),
                          -1);
  if (r != -1)
    error (EXIT_FAILURE, 0,
           "guestfs_xfs_repair: expected failure because of bogus %s",
           "maxmem");
  err = guestfs_last_errno (g);
  if (err != EINVAL)
    error (EXIT_FAILURE, 0,
           "guestfs_xfs_repair: expected errno == EINVAL, but got %d", err);

  r = guestfs_xfs_repair (g, "/dev/sda",
                          GUESTFS_XFS_REPAIR_BHASHSIZE, UINT64_C(-1),
                          -1);
  if (r != -1)
    error (EXIT_FAILURE, 0,
           "guestfs_xfs_repair: expected failure because of bogus %s",
           "bhashsize");
  err = guestfs_last_errno (g);
  if (err != EINVAL)
    error (EXIT_FAILURE, 0,
           "guestfs_xfs_repair: expected errno == EINVAL, but got %d", err);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
