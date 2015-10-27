/* libguestfs - the guestfsd daemon
 * Copyright (C) 2015 Maxim Perevedentsev mperevedentsev@virtuozzo.com
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
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

static char*
get_mount_point (const char *device)
{
  CLEANUP_FREE_STRING_LIST char **mountpoints = do_mountpoints();
  size_t i;
  char *path;

  if (mountpoints == NULL) {
    reply_with_error ("cannot get mountpoints");
    return NULL;
  }

  for (i = 0; mountpoints[i] != NULL; i += 2) {
    if (STREQ (mountpoints[i], device)) {
      path = strdup (mountpoints[i + 1]);
      if (path == NULL)
        reply_with_perror ("strdup");
      return path;
    }
  }

  reply_with_error ("device not mounted: %s", device);
  return NULL;
}

int64_t
do_vfs_minimum_size (const mountable_t *mountable)
{
  int64_t r;

  /* How we get minimum size depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = do_vfs_type (mountable);
  if (vfs_type == NULL)
    return -1;

  else if (fstype_is_extfs (vfs_type))
    r = ext_minimum_size (mountable->device);

  else if (STREQ (vfs_type, "ntfs"))
    r = ntfs_minimum_size (mountable->device);

  else if (STREQ (vfs_type, "btrfs")) {
    CLEANUP_FREE char *path = get_mount_point (mountable->device);
    if (path == NULL)
      return -1;
    r = btrfs_minimum_size (path);
  }

  else if (STREQ (vfs_type, "xfs")) {
    CLEANUP_FREE char *path = get_mount_point (mountable->device);
    if (path == NULL)
      return -1;
    r = xfs_minimum_size (path);
  }

  else
    NOT_SUPPORTED (-1, "don't know how to get minimum size of '%s' filesystems",
                   vfs_type);

  return r;
}
