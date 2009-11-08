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

  argv[i++] = "/sbin/mkfs";
  argv[i++] = "-t";
  argv[i++] = fstype;

  /* mkfs.ntfs requires the -Q argument otherwise it writes zeroes
   * to every block and does bad block detection, neither of which
   * are useful behaviour for virtual devices.
   */
  if (strcmp (fstype, "ntfs") == 0)
    argv[i++] = "-Q";

  /* mkfs.reiserfs produces annoying interactive prompts unless you
   * tell it to be quiet.
   */
  if (strcmp (fstype, "reiserfs") == 0)
    argv[i++] = "-f";

  /* Same for JFS. */
  if (strcmp (fstype, "jfs") == 0)
    argv[i++] = "-f";

  /* For GFS, GFS2, assume a single node. */
  if (strcmp (fstype, "gfs") == 0 || strcmp (fstype, "gfs2") == 0) {
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
    reply_with_error ("mkfs: %s: %s: %s", fstype, device, err);
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
  char blocksize_s[32];

  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  extra[0] = "-b";
  extra[1] = blocksize_s;

  return mkfs (fstype, device, extra, 2);
}
