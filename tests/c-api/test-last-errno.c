/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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

/* Test that we can get correct errnos all the way back from the
 * appliance, translated to the local operating system.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int r, err;
  struct guestfs_statns *stat;

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_scratch (g, 524288000, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    exit (EXIT_FAILURE);

  /* Mount read-only, and check that errno == EROFS is passed back when
   * we create a file.
   */
  if (guestfs_mount_ro (g, "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  r = guestfs_touch (g, "/test");
  if (r != -1)
    error (EXIT_FAILURE, 0,
           "guestfs_touch: expected error for read-only filesystem");

  err = guestfs_last_errno (g);
  if (err != EROFS)
    error (EXIT_FAILURE, 0,
           "guestfs_touch: expected errno == EROFS, but got %d", err);

  if (guestfs_umount (g, "/") == -1)
    exit (EXIT_FAILURE);

  /* Mount it writable and test some other errors. */
  if (guestfs_mount (g, "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  stat = guestfs_lstatns (g, "/nosuchfile");
  if (stat != NULL)
    error (EXIT_FAILURE, 0,
           "guestfs_lstat: expected error for missing file");

  err = guestfs_last_errno (g);
  if (err != ENOENT)
    error (EXIT_FAILURE, 0,
           "guestfs_lstat: expected errno == ENOENT, but got %d", err);

  if (guestfs_touch (g, "/test") == -1)
    exit (EXIT_FAILURE);

  r = guestfs_mkdir (g, "/test");
  if (r != -1)
    error (EXIT_FAILURE, 0,
           "guestfs_mkdir: expected error for file which exists");

  err = guestfs_last_errno (g);
  if (err != EEXIST)
    error (EXIT_FAILURE, 0,
           "guestfs_mkdir: expected errno == EEXIST, but got %d", err);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
