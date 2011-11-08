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
#include <errno.h>

#include "daemon.h"
#include "actions.h"

int
do_fallocate (const char *path, int len)
{
  if (len < 0) {
    reply_with_error ("length < 0");
    return -1;
  }

  return do_fallocate64 (path, len);
}

int
do_fallocate64 (const char *path, int64_t len)
{
  int fd;

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0666);
  CHROOT_OUT;
  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

#ifdef HAVE_POSIX_FALLOCATE
  int err = posix_fallocate (fd, 0, len);
  if (err != 0) {
    errno = err;
    reply_with_perror ("%s", path);
    close (fd);
    return -1;
  }
#else
  ssize_t r;
  char buf[BUFSIZ];
  const size_t len_sz = (size_t) len;
  size_t n;

  memset (buf, 0, BUFSIZ);
  n = 0;
  while (n < len_sz) {
    r = write (fd, buf, len_sz - n < BUFSIZ ? len_sz - n : BUFSIZ);
    if (r == -1) {
      reply_with_perror ("write: %s", path);
      close (fd);
      return -1;
    }
    n += r;
  }
#endif

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}
