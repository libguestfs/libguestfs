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
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

int
do_zero (const char *device)
{
  int fd, i;
  char buf[4096];

  fd = open (device, O_WRONLY);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return -1;
  }

  memset (buf, 0, sizeof buf);

  for (i = 0; i < 32; ++i) {
    if (write (fd, buf, sizeof buf) != sizeof buf) {
      reply_with_perror ("write: %s", device);
      close (fd);
      return -1;
    }
    notify_progress ((uint64_t) i, 32);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", device);
    return -1;
  }

  return 0;
}

int
do_zero_device (const char *device)
{
  int64_t size = do_blockdev_getsize64 (device);
  if (size == -1)
    return -1;

  int fd = open (device, O_WRONLY);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return -1;
  }

  char buf[1024*1024];
  memset (buf, 0, sizeof buf);

  while (size > 0) {
    size_t n = (size_t) size > sizeof buf ? sizeof buf : (size_t) size;
    ssize_t r = write (fd, buf, n);
    if (r == -1) {
      reply_with_perror ("write: %s (with %" PRId64 " bytes left to write)",
                         device, size);
      close (fd);
      return -1;
    }
    size -= r;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", device);
    return -1;
  }

  return 0;
}
