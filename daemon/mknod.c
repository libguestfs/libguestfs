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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#ifdef HAVE_MKNOD
int
optgroup_mknod_available (void)
{
  return 1;
}

int
do_mknod (int mode, int devmajor, int devminor, const char *path)
{
  int r;

  if (mode < 0) {
    reply_with_error ("%s: mode is negative", path);
    return -1;
  }

  CHROOT_IN;
  r = mknod (path, mode, makedev (devmajor, devminor));
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

int
do_mkfifo (int mode, const char *path)
{
  return do_mknod (mode | S_IFIFO, 0, 0, path);
}

int
do_mknod_b (int mode, int devmajor, int devminor, const char *path)
{
  return do_mknod (mode | S_IFBLK, devmajor, devminor, path);
}

int
do_mknod_c (int mode, int devmajor, int devminor, const char *path)
{
  return do_mknod (mode | S_IFCHR, devmajor, devminor, path);
}

#else

int
optgroup_mknod_available (void)
{
  return 0;
}

int
do_mknod (int mode, int devmajor, int devminor, const char *path)
{
  abort ();
}

int
do_mkfifo (int mode, const char *path)
{
  abort ();
}

int
do_mknod_b (int mode, int devmajor, int devminor, const char *path)
{
  abort ();
}

int
do_mknod_c (int mode, int devmajor, int devminor, const char *path)
{
  abort ();
}

#endif
