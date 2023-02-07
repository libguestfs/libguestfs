/* libguestfs
 * Copyright (C) 2012-2023 Red Hat Inc.
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
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"
#include "guestfs-internal-all.h"

int
main (int argc, char *argv[])
{
  const char *s;
  guestfs_h *g;
  struct guestfs_internal_mountable *mountable;
  const char *devices[] = { "/dev/VG/LV", NULL };
  const char *feature[] = { "btrfs", NULL };

  s = getenv ("SKIP_TEST_INTERNAL_PARSE_MOUNTABLE");
  if (s && STRNEQ (s, "")) {
    printf ("%s: test skipped because environment variable is set\n",
            argv[0]);
    exit (77);
  }

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_scratch (g, 1024*1024*1024, -1) == -1) {
  error:
    guestfs_close (g);
    exit (EXIT_FAILURE);
  }

  if (guestfs_launch (g) == -1) goto error;

  if (!guestfs_feature_available (g, (char **) feature)) {
    printf ("skipping test because btrfs is not available\n");
    guestfs_close (g);
    exit (77);
  }

  if (!guestfs_filesystem_available (g, "btrfs")) {
    printf ("skipping test because btrfs filesystem is not available\n");
    guestfs_close (g);
    exit (77);
  }

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1) goto error;

  if (guestfs_pvcreate (g, "/dev/sda1") == -1) goto error;

  const char *pvs[] = { "/dev/sda1", NULL };
  if (guestfs_vgcreate (g, "VG", (char **) pvs) == -1) goto error;

  if (guestfs_lvcreate (g, "LV", "VG", 900) == -1) goto error;

  if (guestfs_mkfs_btrfs (g, (char * const *)devices, -1) == -1) goto error;

  if (guestfs_mount (g, "/dev/VG/LV", "/") == -1) goto error;

  if (guestfs_btrfs_subvolume_create (g, "/sv") == -1) goto error;

  mountable = guestfs_internal_parse_mountable (g, "/dev/VG/LV");
  if (mountable == NULL) goto error;

  if (mountable->im_type != MOUNTABLE_DEVICE ||
      STRNEQ ("/dev/VG/LV", mountable->im_device)) {
    fprintf (stderr, "incorrectly parsed /dev/VG/LV: im_device=%s\n",
             mountable->im_device);
    goto error;
  }

  guestfs_free_internal_mountable (mountable);

  mountable = guestfs_internal_parse_mountable (g, "btrfsvol:/dev/VG/LV/sv");
  if (mountable == NULL) goto error;

  if (mountable->im_type != MOUNTABLE_BTRFSVOL ||
      STRNEQ ("/dev/VG/LV", mountable->im_device) ||
      STRNEQ ("sv", mountable->im_volume)) {
    fprintf (stderr, "incorrectly parsed /dev/VG/LV/sv: im_device=%s, im_volume=%s\n",
             mountable->im_device, mountable->im_volume);
    goto error;
    }
  guestfs_free_internal_mountable (mountable);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
