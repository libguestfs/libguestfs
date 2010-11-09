/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* List filesystems.
 *
 * The current implementation just uses guestfs_vfs_type and doesn't
 * try mounting anything, but we reserve the right in future to try
 * mounting filesystems.
 */

static void remove_from_list (char **list, const char *item);
static void check_with_vfs_type (guestfs_h *g, const char *dev, char ***ret, size_t *ret_size);

char **
guestfs__list_filesystems (guestfs_h *g)
{
  size_t i;
  char **ret;
  size_t ret_size;

  ret = safe_malloc (g, sizeof (char *));
  ret[0] = NULL;
  ret_size = 0;

  /* Look to see if any devices directly contain filesystems
   * (RHBZ#590167).  However vfs-type will fail to tell us anything
   * useful about devices which just contain partitions, so we also
   * get the list of partitions and exclude the corresponding devices
   * by using part-to-dev.
   */
  char **devices;
  devices = guestfs_list_devices (g);
  if (devices == NULL) {
    guestfs___free_string_list (ret);
    return NULL;
  }
  char **partitions;
  partitions = guestfs_list_partitions (g);
  if (partitions == NULL) {
    guestfs___free_string_list (devices);
    guestfs___free_string_list (ret);
    return NULL;
  }

  for (i = 0; partitions[i] != NULL; ++i) {
    char *dev = guestfs_part_to_dev (g, partitions[i]);
    if (dev)
      remove_from_list (devices, dev);
    free (dev);
  }

  /* Use vfs-type to check for filesystems on devices. */
  for (i = 0; devices[i] != NULL; ++i)
    check_with_vfs_type (g, devices[i], &ret, &ret_size);
  guestfs___free_string_list (devices);

  /* Use vfs-type to check for filesystems on partitions. */
  for (i = 0; partitions[i] != NULL; ++i)
    check_with_vfs_type (g, partitions[i], &ret, &ret_size);
  guestfs___free_string_list (partitions);

  if (guestfs___feature_available (g, "lvm2")) {
    /* Use vfs-type to check for filesystems on LVs. */
    char **lvs;
    lvs = guestfs_lvs (g);
    if (lvs == NULL) {
      guestfs___free_string_list (ret);
      return NULL;
    }

    for (i = 0; lvs[i] != NULL; ++i)
      check_with_vfs_type (g, lvs[i], &ret, &ret_size);
    guestfs___free_string_list (lvs);
  }

  return ret;
}

/* If 'item' occurs in 'list', remove and free it. */
static void
remove_from_list (char **list, const char *item)
{
  size_t i;

  for (i = 0; list[i] != NULL; ++i)
    if (STREQ (list[i], item)) {
      free (list[i]);
      for (; list[i+1] != NULL; ++i)
        list[i] = list[i+1];
      list[i] = NULL;
      return;
    }
}

/* Use vfs-type to look for a filesystem of some sort on 'dev'.
 * Apart from some types which we ignore, add the result to the
 * 'ret' string list.
 */
static void
check_with_vfs_type (guestfs_h *g, const char *device,
                     char ***ret, size_t *ret_size)
{
  char *v;

  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;
  char *vfs_type = guestfs_vfs_type (g, device);
  g->error_cb = old_error_cb;

  if (!vfs_type)
    v = safe_strdup (g, "unknown");
  else {
    /* Ignore all "*_member" strings.  In libblkid these are returned
     * for things which are members of some RAID or LVM set, most
     * importantly "LVM2_member" which is a PV.
     */
    size_t n = strlen (vfs_type);
    if (n >= 7 && STREQ (&vfs_type[n-7], "_member")) {
      free (vfs_type);
      return;
    }

    /* Ignore LUKS-encrypted partitions.  These are also containers. */
    if (STREQ (vfs_type, "crypto_LUKS")) {
      free (vfs_type);
      return;
    }

    v = vfs_type;
  }

  /* Extend the return array. */
  size_t i = *ret_size;
  *ret_size += 2;
  *ret = safe_realloc (g, *ret, (*ret_size + 1) * sizeof (char *));
  (*ret)[i] = safe_strdup (g, device);
  (*ret)[i+1] = v;
  (*ret)[i+2] = NULL;
}
