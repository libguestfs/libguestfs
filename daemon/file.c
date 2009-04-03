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

#define _GNU_SOURCE		/* for futimens(2) */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

int
do_touch (const char *path)
{
  int fd;

  NEED_ROOT;

  if (path[0] != '/') {
    reply_with_error ("touch: path must start with a / character");
    return -1;
  }

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_NOCTTY | O_NONBLOCK, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    close (fd);
    return -1;
  }

  if (futimens (fd, NULL) == -1) {
    reply_with_perror ("futimens: %s", path);
    close (fd);
    return -1;
  }

  close (fd);
  return 0;
}
