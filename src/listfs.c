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
static int check_with_vfs_type (guestfs_h *g, const char *dev, struct stringsbuf *sb);
static int is_mbr_partition_type_42 (guestfs_h *g, const char *partition);

char **
guestfs__list_filesystems (guestfs_h *g)
{
  size_t i;
  DECLARE_STRINGSBUF (ret);

  const char *lvm2[] = { "lvm2", NULL };
  int has_lvm2 = guestfs_feature_available (g, (char **) lvm2);
  const char *ldm[] = { "ldm", NULL };
  int has_ldm = guestfs_feature_available (g, (char **) ldm);

  CLEANUP_FREE_STRING_LIST char **devices = NULL;
  CLEANUP_FREE_STRING_LIST char **partitions = NULL;
  CLEANUP_FREE_STRING_LIST char **mds = NULL;
  CLEANUP_FREE_STRING_LIST char **lvs = NULL;
  CLEANUP_FREE_STRING_LIST char **ldmvols = NULL;
  CLEANUP_FREE_STRING_LIST char **ldmparts = NULL;

  /* Look to see if any devices directly contain filesystems
   * (RHBZ#590167).  However vfs-type will fail to tell us anything
   * useful about devices which just contain partitions, so we also
   * get the list of partitions and exclude the corresponding devices
   * by using part-to-dev.
   */
  devices = guestfs_list_devices (g);
  if (devices == NULL) goto error;
  partitions = guestfs_list_partitions (g);
  if (partitions == NULL) goto error;
  mds = guestfs_list_md_devices (g);
  if (mds == NULL) goto error;

  for (i = 0; partitions[i] != NULL; ++i) {
    CLEANUP_FREE char *dev = guestfs_part_to_dev (g, partitions[i]);
    if (dev)
      remove_from_list (devices, dev);
  }

  /* Use vfs-type to check for filesystems on devices. */
  for (i = 0; devices[i] != NULL; ++i)
    if (check_with_vfs_type (g, devices[i], &ret) == -1)
      goto error;

  /* Use vfs-type to check for filesystems on partitions. */
  for (i = 0; partitions[i] != NULL; ++i) {
    if (has_ldm == 0 || ! is_mbr_partition_type_42 (g, partitions[i])) {
      if (check_with_vfs_type (g, partitions[i], &ret) == -1)
        goto error;
    }
  }

  /* Use vfs-type to check for filesystems on md devices. */
  for (i = 0; mds[i] != NULL; ++i)
    if (check_with_vfs_type (g, mds[i], &ret) == -1)
      goto error;

  if (has_lvm2 > 0) {
    /* Use vfs-type to check for filesystems on LVs. */
    lvs = guestfs_lvs (g);
    if (lvs == NULL) goto error;

    for (i = 0; lvs[i] != NULL; ++i)
      if (check_with_vfs_type (g, lvs[i], &ret) == -1)
        goto error;
  }

  if (has_ldm > 0) {
    /* Use vfs-type to check for filesystems on Windows dynamic disks. */
    ldmvols = guestfs_list_ldm_volumes (g);
    if (ldmvols == NULL) goto error;

    for (i = 0; ldmvols[i] != NULL; ++i)
      if (check_with_vfs_type (g, ldmvols[i], &ret) == -1)
        goto error;

    ldmparts = guestfs_list_ldm_partitions (g);
    if (ldmparts == NULL) goto error;

    for (i = 0; ldmparts[i] != NULL; ++i)
      if (check_with_vfs_type (g, ldmparts[i], &ret) == -1)
        goto error;
  }

  /* Finish off the list and return it. */
  guestfs_int_end_stringsbuf (g, &ret);
  return ret.argv;

 error:
  guestfs_int_free_stringsbuf (&ret);
  return NULL;
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
static int
check_with_vfs_type (guestfs_h *g, const char *device, struct stringsbuf *sb)
{
  const char *v;
  CLEANUP_FREE char *vfs_type = NULL;

  guestfs_push_error_handler (g, NULL, NULL);
  vfs_type = guestfs_vfs_type (g, device);
  guestfs_pop_error_handler (g);

  if (!vfs_type)
    v = "unknown";
  else if (STREQ (vfs_type, ""))
    v = "unknown";
  else if (STREQ (vfs_type, "btrfs")) {
    CLEANUP_FREE_BTRFSSUBVOLUME_LIST struct guestfs_btrfssubvolume_list *vols =
      guestfs_btrfs_subvolume_list (g, device);

    if (vols == NULL)
      return -1;

    for (size_t i = 0; i < vols->len; i++) {
      struct guestfs_btrfssubvolume *this = &vols->val[i];
      guestfs_int_add_sprintf (g, sb,
                             "btrfsvol:%s/%s",
                             device, this->btrfssubvolume_path);
      guestfs_int_add_string (g, sb, "btrfs");
    }

    v = vfs_type;
  }
  else {
    /* Ignore all "*_member" strings.  In libblkid these are returned
     * for things which are members of some RAID or LVM set, most
     * importantly "LVM2_member" which is a PV.
     */
    size_t n = strlen (vfs_type);
    if (n >= 7 && STREQ (&vfs_type[n-7], "_member"))
      return 0;

    /* Ignore LUKS-encrypted partitions.  These are also containers. */
    if (STREQ (vfs_type, "crypto_LUKS"))
      return 0;

    v = vfs_type;
  }

  guestfs_int_add_string (g, sb, device);
  guestfs_int_add_string (g, sb, v);

  return 0;
}

/* We should ignore partitions that have MBR type byte 0x42, because
 * these are members of a Windows dynamic disk group.  Trying to read
 * them will cause errors (RHBZ#887520).  Assuming that libguestfs was
 * compiled with ldm support, we'll get the filesystems on these later.
 */
static int
is_mbr_partition_type_42 (guestfs_h *g, const char *partition)
{
  CLEANUP_FREE char *device = NULL;
  int partnum;
  int mbr_id;
  int ret = 0;

  guestfs_push_error_handler (g, NULL, NULL);

  partnum = guestfs_part_to_partnum (g, partition);
  if (partnum == -1)
    goto out;

  device = guestfs_part_to_dev (g, partition);
  if (device == NULL)
    goto out;

  mbr_id = guestfs_part_get_mbr_id (g, device, partnum);

  ret = mbr_id == 0x42;

 out:
  guestfs_pop_error_handler (g);

  return ret;
}
