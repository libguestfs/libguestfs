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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_fill (int c, int len, const char *path)
{
  int fd;
  ssize_t r;
  size_t len_sz;
  size_t n;
  char buf[BUFSIZ];

  if (c < 0 || c > 255) {
    reply_with_error ("%d: byte number must be in range 0..255", c);
    return -1;
  }
  memset (buf, c, BUFSIZ);
  if (len < 0) {
    reply_with_error ("%d: length is < 0", len);
    return -1;
  }
  len_sz = (size_t) len;

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_NOCTTY, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  n = 0;
  while (n < len_sz) {
    r = write (fd, buf, len_sz - n < BUFSIZ ? len_sz - n : BUFSIZ);
    if (r == -1) {
      reply_with_perror ("write: %s", path);
      close (fd);
      return -1;
    }
    n += r;
    notify_progress ((uint64_t) n, (uint64_t) len_sz);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

int
do_fill_pattern (const char *pattern, int len, const char *path)
{
  size_t patlen = strlen (pattern);

  if (patlen < 1) {
    reply_with_error ("pattern string must be non-empty");
    return -1;
  }

  if (len < 0) {
    reply_with_error ("%d: length is < 0", len);
    return -1;
  }
  size_t len_sz = (size_t) len;

  int fd;
  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_NOCTTY, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  /* XXX This implementation won't be very efficient for large files. */
  size_t n = 0;
  while (n < len_sz) {
    size_t wrlen = len_sz - n < patlen ? len_sz - n : patlen;
    if (xwrite (fd, pattern, wrlen) == -1) {
      reply_with_perror ("write: %s", path);
      close (fd);
      return -1;
    }
    n += wrlen;
    notify_progress ((uint64_t) n, (uint64_t) len_sz);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}
