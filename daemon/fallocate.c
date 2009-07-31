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

#include "daemon.h"
#include "actions.h"

int
do_fallocate (char *path, int len)
{
  int fd, r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0666);
  CHROOT_OUT;
  if (fd == -1) {
    reply_with_perror (path);
    return -1;
  }

  r = posix_fallocate (fd, 0, len);
  if (r == -1) {
    reply_with_perror ("posix_fallocate: %s", path);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}
