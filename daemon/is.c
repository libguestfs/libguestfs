/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010 Red Hat Inc.
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
#include <sys/types.h>
#include <sys/stat.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_exists (const char *path)
{
  int r;

  CHROOT_IN;
  r = access (path, F_OK);
  CHROOT_OUT;

  return r == 0;
}

int
do_is_file (const char *path)
{
  int r;
  struct stat buf;

  CHROOT_IN;
  r = lstat (path, &buf);
  CHROOT_OUT;

  if (r == -1) {
    if (errno != ENOENT && errno != ENOTDIR) {
      reply_with_perror ("stat: %s", path);
      return -1;
    }
    else
      return 0;			/* Not a file. */
  }

  return S_ISREG (buf.st_mode);
}

int
do_is_dir (const char *path)
{
  int r;
  struct stat buf;

  CHROOT_IN;
  r = lstat (path, &buf);
  CHROOT_OUT;

  if (r == -1) {
    if (errno != ENOENT && errno != ENOTDIR) {
      reply_with_perror ("stat: %s", path);
      return -1;
    }
    else
      return 0;			/* Not a directory. */
  }

  return S_ISDIR (buf.st_mode);
}
