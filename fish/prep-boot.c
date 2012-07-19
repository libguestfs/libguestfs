/* guestfish - the filesystem interactive shell
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>

#include "fish.h"
#include "prepopts.h"

void
prep_prelaunch_bootroot (const char *filename, prep_data *data)
{
  if (alloc_disk (filename, data->params[2], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

void
prep_postlaunch_bootroot (const char *filename, prep_data *data, const char *device)
{
  off_t bootsize;
  if (parse_size (data->params[3], &bootsize) == -1)
    prep_error (data, filename, _("could not parse boot size"));

  int sector = guestfs_blockdev_getss (g, device);
  if (sector == -1)
    prep_error (data, filename, _("failed to get sector size of disk: %s"),
                guestfs_last_error (g));

  if (guestfs_part_init (g, device, data->params[4]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
                guestfs_last_error (g));

  off_t lastbootsect = 64 + bootsize/sector - 1;
  if (guestfs_part_add (g, device, "primary", 64, lastbootsect) == -1)
    prep_error (data, filename, _("failed to add boot partition: %s"),
                guestfs_last_error (g));

  if (guestfs_part_add (g, device, "primary", lastbootsect+1, -64) == -1)
    prep_error (data, filename, _("failed to add root partition: %s"),
                guestfs_last_error (g));

  char *part;
  if (asprintf (&part, "%s1", device) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (guestfs_mkfs (g, data->params[0], part) == -1)
    prep_error (data, filename, _("failed to create boot filesystem: %s"),
                guestfs_last_error (g));
  free (part);

  if (asprintf (&part, "%s2", device) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (guestfs_mkfs (g, data->params[1], part) == -1)
    prep_error (data, filename, _("failed to create root filesystem: %s"),
                guestfs_last_error (g));
  free (part);
}

void
prep_prelaunch_bootrootlv (const char *filename, prep_data *data)
{
  if (vg_lv_parse (data->params[0], NULL, NULL) == -1)
    prep_error (data, filename, _("incorrect format for LV name, use '/dev/VG/LV'"));

  if (alloc_disk (filename, data->params[3], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

void
prep_postlaunch_bootrootlv (const char *filename, prep_data *data, const char *device)
{
  off_t bootsize;
  if (parse_size (data->params[4], &bootsize) == -1)
    prep_error (data, filename, _("could not parse boot size"));

  int sector = guestfs_blockdev_getss (g, device);
  if (sector == -1)
    prep_error (data, filename, _("failed to get sector size of disk: %s"),
                guestfs_last_error (g));

  if (guestfs_part_init (g, device, data->params[5]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
                guestfs_last_error (g));

  off_t lastbootsect = 64 + bootsize/sector - 1;
  if (guestfs_part_add (g, device, "primary", 64, lastbootsect) == -1)
    prep_error (data, filename, _("failed to add boot partition: %s"),
                guestfs_last_error (g));

  if (guestfs_part_add (g, device, "primary", lastbootsect+1, -64) == -1)
    prep_error (data, filename, _("failed to add root partition: %s"),
                guestfs_last_error (g));

  char *vg;
  char *lv;
  if (vg_lv_parse (data->params[0], &vg, &lv) == -1)
    prep_error (data, filename, _("incorrect format for LV name, use '/dev/VG/LV'"));

  char *part;
  if (asprintf (&part, "%s1", device) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (guestfs_mkfs (g, data->params[1], part) == -1)
    prep_error (data, filename, _("failed to create boot filesystem: %s"),
                guestfs_last_error (g));
  free (part);

  if (asprintf (&part, "%s2", device) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (guestfs_pvcreate (g, part) == -1)
    prep_error (data, filename, _("failed to create PV: %s: %s"),
                part, guestfs_last_error (g));

  char *parts[] = { part, NULL };
  if (guestfs_vgcreate (g, vg, parts) == -1)
    prep_error (data, filename, _("failed to create VG: %s: %s"),
                vg, guestfs_last_error (g));

  /* Create the largest possible LV. */
  if (guestfs_lvcreate_free (g, lv, vg, 100) == -1)
    prep_error (data, filename, _("failed to create LV: /dev/%s/%s: %s"),
                vg, lv, guestfs_last_error (g));

  if (guestfs_mkfs (g, data->params[2], data->params[0]) == -1)
    prep_error (data, filename, _("failed to create root filesystem: %s"),
                guestfs_last_error (g));

  free (part);
  free (vg);
  free (lv);
}
