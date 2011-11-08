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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
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

static int get_mode (const char *path, mode_t *mode);

int
do_is_file (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISREG (mode);
}

int
do_is_dir (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISDIR (mode);
}

int
do_is_chardev (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISCHR (mode);
}

int
do_is_blockdev (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISBLK (mode);
}

int
do_is_fifo (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISFIFO (mode);
}

int
do_is_symlink (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISLNK (mode);
}

int
do_is_socket (const char *path)
{
  mode_t mode;
  int r = get_mode (path, &mode);
  if (r <= 0) return r;
  return S_ISSOCK (mode);
}

static int
get_mode (const char *path, mode_t *mode)
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
      return 0;			/* Doesn't exist, means return false. */
  }

  *mode = buf.st_mode;
  return 1;
}
