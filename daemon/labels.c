/* libguestfs - the guestfsd daemon
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

static int
dosfslabel (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, "dosfslabel", device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static int
xfslabel (const char *device, const char *label)
{
  /* Don't allow the special value "---".  If people want to clear
   * the label we'll have to add another call to do that.
   */
  if (STREQ (label, "---")) {
    reply_with_error ("xfs: invalid new label");
    return -1;
  }

  return xfs_set_label (device, label);
}

int
do_set_label (const mountable_t *mountable, const char *label)
{
  int r;

  /* How we set the label depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = do_vfs_type (mountable);
  if (vfs_type == NULL)
    return -1;

  if (STREQ (vfs_type, "btrfs"))
    r = btrfs_set_label (mountable->device, label);

  else if (STREQ (vfs_type, "msdos") ||
           STREQ (vfs_type, "fat") ||
           STREQ (vfs_type, "vfat"))
    r = dosfslabel (mountable->device, label);

  else if (fstype_is_extfs (vfs_type))
    r = do_set_e2label (mountable->device, label);

  else if (STREQ (vfs_type, "ntfs"))
    r = ntfs_set_label (mountable->device, label);

  else if (STREQ (vfs_type, "xfs"))
    r = xfslabel (mountable->device, label);

  else if (STREQ (vfs_type, "swap"))
    r = swap_set_label (mountable->device, label);

  else
    NOT_SUPPORTED (-1, "don't know how to set the label for '%s' filesystems",
                   vfs_type);

  return r;
}
