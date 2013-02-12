/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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

#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "guestfs.h"
#include "guestfs-internal-all.h"

#define IMG "test.img"

int
main (int argc, char *argv[])
{
  int fd = open (IMG, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd == -1) {
    perror ("open " IMG);
    exit (EXIT_FAILURE);
  }

  int r = posix_fallocate (fd, 0, 1024*1024*1024);
  if (r != 0) {
    fprintf (stderr, "posix_fallocate " IMG " 1G: %s\n", strerror (r));
    unlink (IMG);
    exit (EXIT_FAILURE);
  }

  if (close (fd) == -1) {
    perror ("close " IMG);
    unlink (IMG);
    exit (EXIT_FAILURE);
  }

  guestfs_h *g = guestfs_create ();
  if (g == NULL) {
    perror ("could not create handle");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_opts (g, IMG,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1) == -1) {
  error:
    guestfs_close (g);
    unlink (IMG);
    exit (EXIT_FAILURE);
  }

  if (guestfs_launch (g) == -1) goto error;

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1) goto error;

  if (guestfs_pvcreate (g, "/dev/sda1") == -1) goto error;

  const char *pvs[] = { "/dev/sda1", NULL };
  if (guestfs_vgcreate (g, "VG", (char **) pvs) == -1) goto error;

  if (guestfs_lvcreate (g, "LV", "VG", 900) == -1) goto error;

  const char *devices[] = { "/dev/VG/LV", NULL };
  if (guestfs_mkfs_btrfs (g, (char * const *)devices, -1) == -1) goto error;

  if (guestfs_mount (g, "/dev/VG/LV", "/") == -1) goto error;

  if (guestfs_btrfs_subvolume_create (g, "/sv") == -1) goto error;

  struct guestfs_internal_mountable *mountable =
    guestfs_internal_parse_mountable (g, "/dev/VG/LV");
  if (mountable == NULL) goto error;

  if (mountable->im_type != MOUNTABLE_DEVICE ||
      !STREQ ("/dev/VG/LV", mountable->im_device))
  {
    fprintf (stderr, "incorrectly parsed /dev/VG/LV");
    goto error;
  }

  guestfs_free_internal_mountable (mountable);

  mountable =
    guestfs_internal_parse_mountable (g, "btrfsvol:/dev/VG/LV/sv");
  if (mountable == NULL) goto error;

  if (mountable->im_type != MOUNTABLE_BTRFSVOL ||
      !STREQ ("/dev/VG/LV", mountable->im_device) ||
      !STREQ ("sv", mountable->im_volume))
  {
    fprintf (stderr, "incorrectly parsed /dev/VG/LV/sv");
    goto error;
  }
  guestfs_free_internal_mountable (mountable);

  guestfs_close (g);
  unlink (IMG);

  exit (EXIT_SUCCESS);
}
