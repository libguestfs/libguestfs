/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
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

#define MAX_ARGS 16

static int
mkfs (const char *fstype, const char *device,
      const char **extra, size_t nr_extra)
{
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  int r;
  char *err;

  argv[i++] = "mkfs";
  argv[i++] = "-t";
  argv[i++] = fstype;

  /* mkfs.ntfs requires the -Q argument otherwise it writes zeroes
   * to every block and does bad block detection, neither of which
   * are useful behaviour for virtual devices.
   */
  if (STREQ (fstype, "ntfs"))
    argv[i++] = "-Q";

  /* mkfs.reiserfs produces annoying interactive prompts unless you
   * tell it to be quiet.
   */
  if (STREQ (fstype, "reiserfs"))
    argv[i++] = "-f";

  /* Same for JFS. */
  if (STREQ (fstype, "jfs"))
    argv[i++] = "-f";

  /* For GFS, GFS2, assume a single node. */
  if (STREQ (fstype, "gfs") || STREQ (fstype, "gfs2")) {
    argv[i++] = "-p";
    argv[i++] = "lock_nolock";
    /* The man page says this is default, but it doesn't seem to be: */
    argv[i++] = "-j";
    argv[i++] = "1";
    /* Don't ask questions: */
    argv[i++] = "-O";
  }

  for (j = 0; j < nr_extra; ++j)
    argv[i++] = extra[j];

  argv[i++] = device;
  argv[i++] = NULL;

  if (i > MAX_ARGS)
    abort ();

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
  return mkfs (fstype, device, NULL, 0);
}

int
do_mkfs_b (const char *fstype, int blocksize, const char *device)
{
  const char *extra[2];
  char n[32];

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

    snprintf (n, sizeof n, "%d", sectors_per_cluster);
    extra[0] = "-s";
    extra[1] = n;
  }
  else if (STREQ (fstype, "ntfs")) {
    /* For NTFS map the blocksize into a cluster size. */
    snprintf (n, sizeof n, "%d", blocksize);
    extra[0] = "-c";
    extra[1] = n;
  }
  else {
    /* For all other filesystem types, try the -b option. */
    snprintf (n, sizeof n, "%d", blocksize);
    extra[0] = "-b";
    extra[1] = n;
  }

  return mkfs (fstype, device, extra, 2);
}
