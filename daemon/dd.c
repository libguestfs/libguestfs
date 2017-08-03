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
  CLEANUP_FREE char *if_arg = NULL, *of_arg = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  src_is_dev = is_device_parameter (src);

  if (src_is_dev)
    r = asprintf (&if_arg, "if=%s", src);
  else
    r = asprintf (&if_arg, "if=%s%s", sysroot, src);
  if (r == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  dest_is_dev = is_device_parameter (dest);

  if (dest_is_dev)
    r = asprintf (&of_arg, "of=%s", dest);
  else
    r = asprintf (&of_arg, "of=%s%s", sysroot, dest);
  if (r == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  r = command (NULL, &err, "dd", "bs=1024K", if_arg, of_arg, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", src, dest, err);
    return -1;
  }

  return 0;
}

int
do_copy_size (const char *src, const char *dest, int64_t ssize)
{
  int src_fd, dest_fd;

  if (is_device_parameter (src))
    src_fd = open (src, O_RDONLY | O_CLOEXEC);
  else {
    CLEANUP_FREE char *buf = sysroot_path (src);
    if (!buf) {
      reply_with_perror ("malloc");
      return -1;
    }
    src_fd = open (buf, O_RDONLY | O_CLOEXEC);
  }
  if (src_fd == -1) {
    reply_with_perror ("%s", src);
    return -1;
  }

  if (is_device_parameter (dest))
    dest_fd = open (dest, O_WRONLY | O_CLOEXEC);
  else {
    CLEANUP_FREE char *buf = sysroot_path (dest);
    if (!buf) {
      reply_with_perror ("malloc");
      close (src_fd);
      return -1;
    }
    dest_fd = open (buf, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0666);
  }
  if (dest_fd == -1) {
    reply_with_perror ("%s", dest);
    close (src_fd);
    return -1;
  }

  uint64_t position = 0, size = (uint64_t) ssize;
  CLEANUP_FREE char *buf = NULL;
  buf = malloc (BUFSIZ);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    close (src_fd);
    close (dest_fd);
    return -1;
  }

  while (position < size) {
    /* Calculate bytes to copy. */
    uint64_t n64 = size - position;
    size_t n;
    if (n64 > BUFSIZ)
      n = BUFSIZ;
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
