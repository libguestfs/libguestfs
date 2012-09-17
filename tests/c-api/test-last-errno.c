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

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int fd, r, err;
  struct guestfs_stat *stat;
  const char *filename = "test1.img";

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 524288000) == -1) {
    perror (filename);
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_opts (g, filename,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1) == -1)
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
  if (r != -1) {
    fprintf (stderr,
             "guestfs_touch: expected error for read-only filesystem\n");
    exit (EXIT_FAILURE);
  }

  err = guestfs_last_errno (g);
  if (err != EROFS) {
    fprintf (stderr,
             "guestfs_touch: expected errno == EROFS, but got %d\n", err);
    exit (EXIT_FAILURE);
  }

  if (guestfs_umount (g, "/") == -1)
    exit (EXIT_FAILURE);

  /* Mount it writable and test some other errors. */
  if (guestfs_mount_options (g, "", "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  stat = guestfs_lstat (g, "/nosuchfile");
  if (stat != NULL) {
    fprintf (stderr,
             "guestfs_lstat: expected error for missing file\n");
    exit (EXIT_FAILURE);
  }

  err = guestfs_last_errno (g);
  if (err != ENOENT) {
    fprintf (stderr,
             "guestfs_lstat: expected errno == ENOENT, but got %d\n", err);
    exit (EXIT_FAILURE);
  }

  if (guestfs_touch (g, "/test") == -1)
    exit (EXIT_FAILURE);

  r = guestfs_mkdir (g, "/test");
  if (r != -1) {
    fprintf (stderr,
             "guestfs_mkdir: expected error for file which exists\n");
    exit (EXIT_FAILURE);
  }

  err = guestfs_last_errno (g);
  if (err != EEXIST) {
    fprintf (stderr,
             "guestfs_mkdir: expected errno == EEXIST, but got %d\n", err);
    exit (EXIT_FAILURE);
  }

  guestfs_close (g);

  unlink (filename);

  exit (EXIT_SUCCESS);
}
