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
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_utimens (const char *path,
            int64_t atsecs, int64_t atnsecs,
            int64_t mtsecs, int64_t mtnsecs)
{
  int r;

  if (atnsecs == -1)
    atnsecs = UTIME_NOW;
  if (atnsecs == -2)
    atnsecs = UTIME_OMIT;
  if (mtnsecs == -1)
    mtnsecs = UTIME_NOW;
  if (mtnsecs == -2)
    mtnsecs = UTIME_OMIT;

  struct timespec times[2];
  times[0].tv_sec = atsecs;
  times[0].tv_nsec = atnsecs;
  times[1].tv_sec = mtsecs;
  times[1].tv_nsec = mtnsecs;

  CHROOT_IN;
  r = utimensat (-1, path, times, AT_SYMLINK_NOFOLLOW);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("utimensat: %s", path);
    return -1;
  }

  return 0;
}
