/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <dirent.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

#define MAX_ARGS 64

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mkfs_opts (const char *fstype, const char *device, int blocksize,
              const char *features, int inode, int sectorsize)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char blocksize_str[32];
  char inode_str[32];
  char sectorsize_str[32];
  int r;
  char *err;
  char mke2fs[] = "mke2fs";
  int extfs = 0;

  if (STREQ (fstype, "ext2") || STREQ (fstype, "ext3") ||
      STREQ (fstype, "ext4"))
    extfs = 1;

  /* For ext2/3/4 run the mke2fs program directly.  This is because
   * the mkfs program "eats" some options, in particular the -F
   * option.
   */
  if (extfs) {
    if (e2prog (mke2fs) == -1)
      return -1;
    ADD_ARG (argv, i, mke2fs);
  }
  else
    ADD_ARG (argv, i, "mkfs");

  ADD_ARG (argv, i, "-t");
  ADD_ARG (argv, i, fstype);

  /* Force mke2fs to create a filesystem, even if it thinks it
   * shouldn't (RHBZ#690819).
   */
  if (extfs)
    ADD_ARG (argv, i, "-F");

  /* mkfs.ntfs requires the -Q argument otherwise it writes zeroes
   * to every block and does bad block detection, neither of which
   * are useful behaviour for virtual devices.
   */
  if (STREQ (fstype, "ntfs"))
    ADD_ARG (argv, i, "-Q");

  /* mkfs.reiserfs produces annoying interactive prompts unless you
   * tell it to be quiet.
   * mkfs.jfs is the same
   * mkfs.xfs must force to make xfs filesystem when the device already
   * has a filesystem on it
   */
  if (STREQ (fstype, "reiserfs") || STREQ (fstype, "jfs") ||
      STREQ (fstype, "xfs"))
    ADD_ARG(argv, i, "-f");

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

  /* Process blocksize parameter if set. */
  if (optargs_bitmask & GUESTFS_MKFS_OPTS_BLOCKSIZE_BITMASK) {
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
      int sectorsize = do_blockdev_getss (device);
      if (sectorsize == -1)
        return -1;

      int sectors_per_cluster = blocksize / sectorsize;
      if (sectors_per_cluster < 1 || sectors_per_cluster > 128) {
        reply_with_error ("unsupported cluster size for %s filesystem (requested cluster size = %d, sector size = %d, trying sectors per cluster = %d)",
                          fstype, blocksize, sectorsize, sectors_per_cluster);
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
    else {
      /* For all other filesystem types, try the -b option. */
      snprintf (blocksize_str, sizeof blocksize_str, "%d", blocksize);
      ADD_ARG (argv, i, "-b");
      ADD_ARG (argv, i, blocksize_str);
    }
  }

  if (optargs_bitmask & GUESTFS_MKFS_OPTS_FEATURES_BITMASK) {
    ADD_ARG (argv, i, "-O");
    ADD_ARG (argv, i, features);
  }

  if (optargs_bitmask & GUESTFS_MKFS_OPTS_INODE_BITMASK) {
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

  if (optargs_bitmask & GUESTFS_MKFS_OPTS_SECTORSIZE_BITMASK) {
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

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", fstype, device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mkfs (const char *fstype, const char *device)
{
  optargs_bitmask = 0;
  return do_mkfs_opts (fstype, device, 0, 0, 0, 0);
}

int
do_mkfs_b (const char *fstype, int blocksize, const char *device)
{
  optargs_bitmask = GUESTFS_MKFS_OPTS_BLOCKSIZE_BITMASK;
  return do_mkfs_opts (fstype, device, blocksize, 0, 0, 0);
}
