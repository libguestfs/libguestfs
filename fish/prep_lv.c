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

#include "fish.h"
#include "prepopts.h"

/* Split "/dev/VG/LV" into "VG" and "LV".  This function should
 * probably do more checks.
 */
int
vg_lv_parse (const char *device, char **vg, char **lv)
{
  if (STRPREFIX (device, "/dev/"))
    device += 5;

  const char *p = strchr (device, '/');
  if (p == NULL)
    return -1;

  if (vg) {
    *vg = strndup (device, p - device);
    if (*vg == NULL) {
      perror ("strndup");
      exit (EXIT_FAILURE);
    }
  }

  if (lv) {
    *lv = strdup (p+1);
    if (*lv == NULL) {
      perror ("strndup");
      exit (EXIT_FAILURE);
    }
  }

  return 0;
}

void
prep_prelaunch_lv (const char *filename, prep_data *data)
{
  if (vg_lv_parse (data->params[0], NULL, NULL) == -1)
    prep_error (data, filename, _("incorrect format for LV name, use '/dev/VG/LV'"));

  if (alloc_disk (filename, data->params[1], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

void
prep_postlaunch_lv (const char *filename, prep_data *data, const char *device)
{
  if (guestfs_part_disk (g, device, data->params[2]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
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

  if (guestfs_pvcreate (g, part) == -1)
    prep_error (data, filename, _("failed to create PV: %s: %s"),
                part, guestfs_last_error (g));

  char *parts[] = { part, NULL };
  if (guestfs_vgcreate (g, vg, parts) == -1)
    prep_error (data, filename, _("failed to create VG: %s: %s"),
                vg, guestfs_last_error (g));

  /* Create the smallest possible LV, then resize it to fill
   * all available space.
   */
  if (guestfs_lvcreate (g, lv, vg, 1) == -1)
    prep_error (data, filename, _("failed to create LV: /dev/%s/%s: %s"),
                vg, lv, guestfs_last_error (g));
  if (guestfs_lvresize_free (g, data->params[0], 100) == -1)
    prep_error (data, filename,
                _("failed to resize LV to full size: %s: %s"),
                data->params[0], guestfs_last_error (g));

  free (part);
  free (vg);
  free (lv);
}

void
prep_prelaunch_lvfs (const char *filename, prep_data *data)
{
  if (vg_lv_parse (data->params[0], NULL, NULL) == -1)
    prep_error (data, filename, _("incorrect format for LV name, use '/dev/VG/LV'"));

  if (alloc_disk (filename, data->params[2], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

void
prep_postlaunch_lvfs (const char *filename, prep_data *data, const char *device)
{
  if (guestfs_part_disk (g, device, data->params[3]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
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

  if (guestfs_pvcreate (g, part) == -1)
    prep_error (data, filename, _("failed to create PV: %s: %s"),
                part, guestfs_last_error (g));

  char *parts[] = { part, NULL };
  if (guestfs_vgcreate (g, vg, parts) == -1)
    prep_error (data, filename, _("failed to create VG: %s: %s"),
                vg, guestfs_last_error (g));

  /* Create the smallest possible LV, then resize it to fill
   * all available space.
   */
  if (guestfs_lvcreate (g, lv, vg, 1) == -1)
    prep_error (data, filename, _("failed to create LV: /dev/%s/%s: %s"),
                vg, lv, guestfs_last_error (g));
  if (guestfs_lvresize_free (g, data->params[0], 100) == -1)
    prep_error (data, filename,
                _("failed to resize LV to full size: %s: %s"),
                data->params[0], guestfs_last_error (g));

  /* Create the filesystem. */
  if (guestfs_mkfs (g, data->params[1], data->params[0]) == -1)
    prep_error (data, filename, _("failed to create filesystem (%s): %s"),
                data->params[1], guestfs_last_error (g));

  free (part);
  free (vg);
  free (lv);
}
