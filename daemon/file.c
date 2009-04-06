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

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_touch (const char *path)
{
  int fd;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_NOCTTY | O_NONBLOCK, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
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

char *
do_cat (const char *path)
{
  int fd;
  int alloc, size, r, max;
  char *buf, *buf2;

  NEED_ROOT (NULL);
  ABS_PATH (path,NULL);

  CHROOT_IN;
  fd = open (path, O_RDONLY);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return NULL;
  }

  /* Read up to GUESTFS_MESSAGE_MAX - <overhead> bytes.  If it's
   * larger than that, we need to return an error instead (for
   * correctness).
   */
  max = GUESTFS_MESSAGE_MAX - 1000;
  buf = NULL;
  size = alloc = 0;

  for (;;) {
    if (size >= alloc) {
      alloc += 8192;
      if (alloc > max) {
	reply_with_error ("cat: %s: file is too large for message buffer",
			  path);
	free (buf);
	close (fd);
	return NULL;
      }
      buf2 = realloc (buf, alloc);
      if (buf2 == NULL) {
	reply_with_perror ("realloc");
	free (buf);
	close (fd);
	return NULL;
      }
      buf = buf2;
    }

    r = read (fd, buf + size, alloc - size);
    if (r == -1) {
      reply_with_perror ("read: %s", path);
      free (buf);
      close (fd);
      return NULL;
    }
    if (r == 0) {
      buf[size] = '\0';
      break;
    }
    if (r > 0)
      size += r;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    free (buf);
    return NULL;
  }

  return buf;			/* caller will free */
}
