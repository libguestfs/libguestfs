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
#include <fcntl.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_dd (const char *src, const char *dest)
{
  int src_is_dev, dest_is_dev;
  char *if_arg, *of_arg;
  char *err;
  int r;

  src_is_dev = STRPREFIX (src, "/dev/");

  if (src_is_dev)
    r = asprintf (&if_arg, "if=%s", src);
  else
    r = asprintf (&if_arg, "if=%s%s", sysroot, src);
  if (r == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  dest_is_dev = STRPREFIX (dest, "/dev/");

  if (dest_is_dev)
    r = asprintf (&of_arg, "of=%s", dest);
  else
    r = asprintf (&of_arg, "of=%s%s", sysroot, dest);
  if (r == -1) {
    reply_with_perror ("asprintf");
    free (if_arg);
    return -1;
  }

  r = command (NULL, &err, "dd", "bs=1024K", if_arg, of_arg, NULL);
  free (if_arg);
  free (of_arg);

  if (r == -1) {
    reply_with_error ("%s: %s: %s", src, dest, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_copy_size (const char *src, const char *dest, int64_t ssize)
{
  char *buf;
  int src_fd, dest_fd;

  if (STRPREFIX (src, "/dev/"))
    src_fd = open (src, O_RDONLY);
  else {
    buf = sysroot_path (src);
    if (!buf) {
      reply_with_perror ("malloc");
      return -1;
    }
    src_fd = open (buf, O_RDONLY);
    free (buf);
  }
  if (src_fd == -1) {
    reply_with_perror ("%s", src);
    return -1;
  }

  if (STRPREFIX (dest, "/dev/"))
    dest_fd = open (dest, O_WRONLY);
  else {
    buf = sysroot_path (dest);
    if (!buf) {
      reply_with_perror ("malloc");
      close (src_fd);
      return -1;
    }
    dest_fd = open (buf, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
    free (buf);
  }
  if (dest_fd == -1) {
    reply_with_perror ("%s", dest);
    close (src_fd);
    return -1;
  }

  uint64_t position = 0, size = (uint64_t) ssize;

  while (position < size) {
    char buf[1024*1024];

    /* Calculate bytes to copy. */
    uint64_t n64 = size - position;
    size_t n;
    if (n64 > sizeof buf)
      n = sizeof buf;
    else
      n = (size_t) n64; /* safe because of if condition */

    ssize_t r = read (src_fd, buf, n);
    if (r == -1) {
      reply_with_perror ("%s: read", src);
      close (src_fd);
      close (dest_fd);
      return -1;
    }
    if (r == 0) {
      reply_with_error ("%s: input file too short", src);
      close (src_fd);
      close (dest_fd);
      return -1;
    }

    if (xwrite (dest_fd, buf, r) == -1) {
      reply_with_perror ("%s: write", dest);
      close (src_fd);
      close (dest_fd);
      return -1;
    }

    position += r;
    notify_progress ((uint64_t) position, (uint64_t) size);
  }

  if (close (src_fd) == -1) {
    reply_with_perror ("%s: close", src);
    close (dest_fd);
    return -1;
  }
  if (close (dest_fd) == -1) {
    reply_with_perror ("%s: close", dest);
    return -1;
  }

  return 0;
}
