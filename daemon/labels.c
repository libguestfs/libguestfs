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
  /* How we set the label depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = do_vfs_type (mountable);
  if (vfs_type == NULL)
    return -1;

  struct {
    const char *fs;
    int (*func)(const char *device, const char *label);
  } const setters[] = {
    { "btrfs", btrfs_set_label },
    { "msdos", dosfslabel       },
    { "vfat",  dosfslabel       },
    { "fat",   dosfslabel       },
    { "ntfs",  ntfs_set_label   },
    { "xfs",   xfslabel         },
    { "swap",  swap_set_label   },
    { NULL,    NULL             }
  };

  /* Special case: ext2/ext3/ext4 */
  if (fstype_is_extfs (vfs_type))
    return do_set_e2label (mountable->device, label);

  for (size_t i = 0; setters[i].fs; ++i) {
    if (STREQ (vfs_type, setters[i].fs))
      return setters[i].func (mountable->device, label);
  }

  /* Not supported */
  NOT_SUPPORTED (-1,
                 "don't know how to set the label for '%s' filesystems",
                 vfs_type);
}
