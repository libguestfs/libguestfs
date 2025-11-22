/* libguestfs - the guestfsd daemon
 * Copyright (C) 2013 Red Hat Inc.
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
e2uuid (const char *device, const char *uuid)
{
  /* Don't allow the magic values here.  If callers want to do this
   * we'll add alternate set_uuid_* calls.
   */
  if (STREQ (uuid, "clear") || STREQ (uuid, "random") ||
      STREQ (uuid, "time")) {
    reply_with_error ("e2: invalid new UUID");
    return -1;
  }

  return do_set_e2uuid (device, uuid);
}

static int
xfsuuid (const char *device, const char *uuid)
{
  /* Don't allow special values. */
  if (STREQ (uuid, "nil") || STREQ (uuid, "generate")) {
    reply_with_error ("xfs: invalid new UUID");
    return -1;
  }

  return xfs_set_uuid (device, uuid);
}

int
do_set_uuid (const char *device, const char *uuid)
{
  /* How we set the UUID depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = get_blkid_tag (device, "TYPE");
  if (vfs_type == NULL)
    return -1;

  /* Fast path: ext2/3/4 family */
  if (fstype_is_extfs (vfs_type))
    return e2uuid (device, uuid);

  /* Table-driven dispatch — struct + array in one perfect declaration */
  static const struct {
    const char *fs_name;
    int (*setter)(const char *device, const char *uuid);
  } handlers[] = {
    { "xfs",    xfsuuid        },
    { "swap",   swap_set_uuid  },
    { "btrfs",  btrfs_set_uuid },
    { NULL,     NULL           }  /* sentinel */
  };

  /* Lookup and call */
  for (size_t i = 0; handlers[i].fs_name; ++i) {
    if (STREQ (vfs_type, handlers[i].fs_name))
      return handlers[i].setter (device, uuid);
  }

  NOT_SUPPORTED (-1,
                 "don't know how to set the UUID for '%s' filesystems",
                 vfs_type);
}

int
do_set_uuid_random (const char *device)
{
  int r;

  /* How we set the UUID depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = get_blkid_tag (device, "TYPE");
  if (vfs_type == NULL)
    return -1;

  CLEANUP_FREE char *uuid_random = get_random_uuid ();
  if (uuid_random == NULL)
    return -1;

  if (fstype_is_extfs (vfs_type))
    r = ext_set_uuid_random (device);

  else if (STREQ (vfs_type, "xfs"))
    r = xfs_set_uuid_random (device);

  else if (STREQ (vfs_type, "swap"))
    r = swap_set_uuid (device, uuid_random);

  else if (STREQ (vfs_type, "btrfs"))
    r = btrfs_set_uuid_random (device);

  else
    NOT_SUPPORTED (-1, "don't know how to set the random UUID for '%s' filesystems",
		   vfs_type);
  return r;
}
