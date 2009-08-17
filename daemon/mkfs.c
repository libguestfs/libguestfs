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

int
do_mkfs (const char *fstype, const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err, "/sbin/mkfs", "-t", fstype, device, NULL);
  if (r == -1) {
    reply_with_error ("mkfs: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mkfs_b (const char *fstype, int blocksize, const char *device)
{
  char *err;
  int r;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  r = command (NULL, &err,
               "/sbin/mkfs", "-t", fstype, "-b", blocksize_s, device, NULL);
  if (r == -1) {
    reply_with_error ("mkfs_b: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
