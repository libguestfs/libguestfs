/* libguestfs
 * Copyright (C) 2016 SUSE LLC
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>
#include <string.h>
#include <errno.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "structs-cleanups.h"

char *
guestfs_impl_mountable_device (guestfs_h *g, const char *mountable)
{
  CLEANUP_FREE_INTERNAL_MOUNTABLE struct guestfs_internal_mountable *mnt = NULL;

  mnt = guestfs_internal_parse_mountable (g, mountable);
  if (mnt == NULL)
    return NULL;

  return safe_strdup (g, mnt->im_device);
}

char *
guestfs_impl_mountable_subvolume (guestfs_h *g, const char *mountable)
{
  CLEANUP_FREE_INTERNAL_MOUNTABLE struct guestfs_internal_mountable *mnt = NULL;

  mnt = guestfs_internal_parse_mountable (g, mountable);
  if (mnt == NULL || STREQ (mnt->im_volume, "")) {
    guestfs_int_error_errno (g, EINVAL, "not a btrfs subvolume identifier");
    return NULL;
  }

  return safe_strdup (g, mnt->im_volume);
}
