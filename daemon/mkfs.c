/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <fcntl.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

#define MAX_ARGS 64

enum fat_mbr_option {
  FMO_UNCHECKED,
  FMO_DOESNT_EXIST,
  FMO_EXISTS,
};

static enum fat_mbr_option fat_mbr_option = FMO_UNCHECKED;

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mkfs (const char *fstype, const char *device, int blocksize,
         const char *features, int inode, int sectorsize, const char *label)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char blocksize_str[32];
  char inode_str[32];
  char sectorsize_str[32];
  int r;
  CLEANUP_FREE char *err = NULL;
  int extfs = 0;

  if (fstype_is_extfs (fstype))
    extfs = 1;

  /* For ext2/3/4 run the mke2fs program directly.  This is because
   * the mkfs program "eats" some options, in particular the -F
   * option.
   */
  if (extfs)
    ADD_ARG (argv, i, "mke2fs");
  else
    ADD_ARG (argv, i, "mkfs");

  ADD_ARG (argv, i, "-t");
  ADD_ARG (argv, i, fstype);

  /* Force mke2fs to create a filesystem, even if it thinks it
   * shouldn't (RHBZ#690819).
   */
  if (extfs)
    ADD_ARG (argv, i, "-F");

  /* mkfs.ntfs requires the -Q argument otherwise it writes zeroes to
   * every block and does bad block detection, neither of which are
   * useful behaviour for virtual devices.  Also recent versions need
   * to be forced to create filesystems on non-partitions.
   */
  if (STREQ (fstype, "ntfs")) {
    ADD_ARG (argv, i, "-Q");
    ADD_ARG (argv, i, "-F");
  }

  /* mkfs.reiserfs produces annoying interactive prompts unless you
   * tell it to be quiet.
   * mkfs.jfs is the same
   * mkfs.xfs must force to make xfs filesystem when the device already
   * has a filesystem on it
   */
  if (STREQ (fstype, "reiserfs") || STREQ (fstype, "jfs") ||
      STREQ (fstype, "xfs"))
    ADD_ARG (argv, i, "-f");

  /* For GFS, GFS2, assume a single node. */
  if (STREQ (fstype, "gfs") || STREQ (fstype, "gfs2")) {
    ADD_ARG (argv, i, "-p");
    ADD_ARG (argv, i, "lock_nolock");
    /* The man page says this is default, but it doesn't seem to be: */
    ADD_ARG (argv, i, "-j");
    ADD_ARG (argv, i, "1");
    /* Don't ask questions: */
    ADD_ARG (argv, i, "-O");
  }

  /* Force mkfs.fat to create a whole disk filesystem (RHBZ#1039995). */
  if (STREQ (fstype, "fat") || STREQ (fstype, "vfat") ||
      STREQ (fstype, "msdos"))
    ADD_ARG (argv, i, "-I");

  /* Prevent mkfs.fat from creating a bogus partition table (RHBZ#1931821). */
  if (STREQ (fstype, "fat") || STREQ (fstype, "vfat") ||
      STREQ (fstype, "msdos")) {
    if (fat_mbr_option == FMO_UNCHECKED) {
      CLEANUP_FREE char *usage_err = NULL;

      fat_mbr_option = FMO_DOESNT_EXIST;
      /* Invoking either version 3 of version 4 of mkfs.fat without any options
       * will make it (a) print a usage summary to stderr, (b) exit with status
       * 1.
       */
      r = commandr (NULL, &usage_err, "mkfs.fat", (char *)NULL);
      if (r == 1 && strstr (usage_err, "--mbr[=") != NULL)
        fat_mbr_option = FMO_EXISTS;
    }
    if (fat_mbr_option == FMO_EXISTS)
      ADD_ARG (argv, i, "--mbr=n");
  }

  /* Process blocksize parameter if set. */
  if (optargs_bitmask & GUESTFS_MKFS_BLOCKSIZE_BITMASK) {
    if (blocksize <= 0 || !is_power_of_2 (blocksize)) {
      reply_with_error ("block size must be > 0 and a power of 2");
      return -1;
    }

    if (STREQ (fstype, "vfat") ||
        STREQ (fstype, "msdos")) {
      /* For VFAT map the blocksize into a cluster size.  However we
       * have to determine the block device sector size in order to do
       * this.
       */
      const int ss = do_blockdev_getss (device);
      if (ss == -1)
        return -1;

      const int sectors_per_cluster = blocksize / ss;
      if (sectors_per_cluster < 1 || sectors_per_cluster > 128) {
        reply_with_error ("unsupported cluster size for %s filesystem (requested cluster size = %d, sector size = %d, trying sectors per cluster = %d)",
                          fstype, blocksize, ss, sectors_per_cluster);
        return -1;
      }

      snprintf (blocksize_str, sizeof blocksize_str, "%d", sectors_per_cluster);
      ADD_ARG (argv, i, "-s");
      ADD_ARG (argv, i, blocksize_str);
    }
    else if (STREQ (fstype, "ntfs")) {
      /* For NTFS map the blocksize into a cluster size. */
      snprintf (blocksize_str, sizeof blocksize_str, "%d", blocksize);
      ADD_ARG (argv, i, "-c");
      ADD_ARG (argv, i, blocksize_str);
    }
    else if (STREQ (fstype, "btrfs")) {
      /* For btrfs, blocksize cannot be specified (RHBZ#807905). */
      reply_with_error ("blocksize cannot be set on btrfs filesystems, use 'mkfs-btrfs'");
      return -1;
    }
    else if (STREQ (fstype, "xfs")) {
      /* mkfs -t xfs -b size=<size> (RHBZ#981715). */
      snprintf (blocksize_str, sizeof blocksize_str, "size=%d", blocksize);
      ADD_ARG (argv, i, "-b");
      ADD_ARG (argv, i, blocksize_str);
    }
    else {
      /* For all other filesystem types, try the -b option. */
      snprintf (blocksize_str, sizeof blocksize_str, "%d", blocksize);
      ADD_ARG (argv, i, "-b");
      ADD_ARG (argv, i, blocksize_str);
    }
  }

  if (optargs_bitmask & GUESTFS_MKFS_FEATURES_BITMASK) {
    ADD_ARG (argv, i, "-O");
    ADD_ARG (argv, i, features);
  }

  if (optargs_bitmask & GUESTFS_MKFS_INODE_BITMASK) {
    if (!extfs) {
      reply_with_error ("inode size (-I) can only be set on ext2/3/4 filesystems");
      return -1;
    }

    if (inode <= 0) {
      reply_with_error ("inode size must be larger than zero");
      return -1;
    }

    snprintf (inode_str, sizeof inode_str, "%d", inode);
    ADD_ARG (argv, i, "-I");
    ADD_ARG (argv, i, inode_str);
  }

  if (optargs_bitmask & GUESTFS_MKFS_SECTORSIZE_BITMASK) {
    if (!STREQ (fstype, "ufs")) {
      reply_with_error ("sector size (-S) can only be set on ufs filesystems");
      return -1;
    }

    if (sectorsize <= 0) {
      reply_with_error ("sector size must be larger than zero");
      return -1;
    }

    snprintf (sectorsize_str, sizeof sectorsize_str, "%d", sectorsize);
    ADD_ARG (argv, i, "-S");
    ADD_ARG (argv, i, sectorsize_str);
  }

  if (optargs_bitmask & GUESTFS_MKFS_LABEL_BITMASK) {
    if (extfs) {
      if (strlen (label) > EXT2_LABEL_MAX) {
        reply_with_error ("%s: ext2/3/4 labels are limited to %d bytes",
                          label, EXT2_LABEL_MAX);
        return -1;
      }

      ADD_ARG (argv, i, "-L");
      ADD_ARG (argv, i, label);
    }
    else if (STREQ (fstype, "fat") || STREQ (fstype, "vfat") ||
             STREQ (fstype, "msdos")) {
      ADD_ARG (argv, i, "-n");
      ADD_ARG (argv, i, label);
    }
    else if (STREQ (fstype, "ntfs")) {
      ADD_ARG (argv, i, "-L");
      ADD_ARG (argv, i, label);
    }
    else if (STREQ (fstype, "xfs")) {
      if (strlen (label) > XFS_LABEL_MAX) {
        reply_with_error ("%s: xfs labels are limited to %d bytes",
                          label, XFS_LABEL_MAX);
        return -1;
      }

      ADD_ARG (argv, i, "-L");
      ADD_ARG (argv, i, label);
    }
    else if (STREQ (fstype, "btrfs")) {
      ADD_ARG (argv, i, "-L");
      ADD_ARG (argv, i, label);
    }
    else if (STREQ (fstype, "f2fs")) {
      ADD_ARG (argv, i, "-l");
      ADD_ARG (argv, i, label);
    }
    else {
      reply_with_error ("don't know how to set the label for '%s' filesystems",
                        fstype);
      return -1;
    }
  }

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  wipe_device_before_mkfs (device);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", fstype, device, err);
    return -1;
  }

  return 0;
}

int
do_mkfs_b (const char *fstype, int blocksize, const char *device)
{
  optargs_bitmask = GUESTFS_MKFS_BLOCKSIZE_BITMASK;
  return do_mkfs (fstype, device, blocksize, 0, 0, 0, NULL);
}
