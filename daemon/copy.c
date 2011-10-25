/* libguestfs - the guestfsd daemon
 * Copyright (C) 2011 Red Hat Inc.
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
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#define DEST_FILE_FLAGS O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666
#define DEST_DEVICE_FLAGS O_WRONLY, 0

/* NB: We cheat slightly by assuming that optargs_bitmask is
 * compatible for all four of the calls.  This is true provided they
 * all take the same set of optional arguments.
 */

/* Takes optional arguments, consult optargs_bitmask. */
static int
copy (const char *src, const char *src_display,
      const char *dest, const char *dest_display,
      int wrflags, int wrmode,
      int64_t srcoffset, int64_t destoffset, int64_t size)
{
  int64_t saved_size = size;
  int src_fd, dest_fd;
  char buf[BUFSIZ];
  size_t n;
  ssize_t r;

  if ((optargs_bitmask & GUESTFS_COPY_DEVICE_TO_DEVICE_SRCOFFSET_BITMASK)) {
    if (srcoffset < 0) {
      reply_with_error ("srcoffset is negative");
      return -1;
    }
  }
  else
    srcoffset = 0;

  if ((optargs_bitmask & GUESTFS_COPY_DEVICE_TO_DEVICE_DESTOFFSET_BITMASK)) {
    if (destoffset < 0) {
      reply_with_error ("destoffset is negative");
      return -1;
    }
  }
  else
    destoffset = 0;

  if ((optargs_bitmask & GUESTFS_COPY_DEVICE_TO_DEVICE_SIZE_BITMASK)) {
    if (size < 0) {
      reply_with_error ("size is negative");
      return -1;
    }
  }
  else
    size = -1;

  /* Open source and destination. */
  src_fd = open (src, O_RDONLY);
  if (src_fd == -1) {
    reply_with_perror ("%s", src_display);
    return -1;
  }

  if (srcoffset > 0 && lseek (src_fd, srcoffset, SEEK_SET) == (off_t) -1) {
    reply_with_perror ("lseek: %s", src_display);
    close (src_fd);
    return -1;
  }

  dest_fd = open (dest, wrflags, wrmode);
  if (dest_fd == -1) {
    reply_with_perror ("%s", dest_display);
    close (src_fd);
    return -1;
  }

  if (destoffset > 0 && lseek (dest_fd, destoffset, SEEK_SET) == (off_t) -1) {
    reply_with_perror ("lseek: %s", dest_display);
    close (src_fd);
    close (dest_fd);
    return -1;
  }

  if (size == -1)
    pulse_mode_start ();

  while (size != 0) {
    /* Calculate bytes to copy. */
    if (size == -1 || size > (int64_t) sizeof buf)
      n = sizeof buf;
    else
      n = size;

    r = read (src_fd, buf, n);
    if (r == -1) {
      if (size == -1)
        pulse_mode_cancel ();
      reply_with_perror ("read: %s", src_display);
      close (src_fd);
      close (dest_fd);
      return -1;
    }

    if (r == 0) {
      if (size == -1) /* if size == -1, this is normal end of loop */
        break;
      reply_with_error ("%s: input too short", src_display);
      close (src_fd);
      close (dest_fd);
      return -1;
    }

    if (xwrite (dest_fd, buf, r) == -1) {
      if (size == -1)
        pulse_mode_cancel ();
      reply_with_perror ("%s: write", dest_display);
      close (src_fd);
      close (dest_fd);
      return -1;
    }

    if (size != -1) {
      size -= r;
      notify_progress ((uint64_t) (saved_size - size), (uint64_t) saved_size);
    }
  }

  if (size == -1)
    pulse_mode_end ();

  if (close (src_fd) == -1) {
    reply_with_perror ("close: %s", src_display);
    close (dest_fd);
    return -1;
  }

  if (close (dest_fd) == -1) {
    reply_with_perror ("close: %s", dest_display);
    return -1;
  }

  return 0;
}

int
do_copy_device_to_device (const char *src, const char *dest,
                          int64_t srcoffset, int64_t destoffset, int64_t size)
{
  return copy (src, src, dest, dest, DEST_DEVICE_FLAGS,
               srcoffset, destoffset, size);
}

int
do_copy_device_to_file (const char *src, const char *dest,
                        int64_t srcoffset, int64_t destoffset, int64_t size)
{
  char *dest_buf;
  int r;

  dest_buf = sysroot_path (dest);
  if (!dest_buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = copy (src, src, dest_buf, dest, DEST_FILE_FLAGS,
            srcoffset, destoffset, size);
  free (dest_buf);

  return r;
}

int
do_copy_file_to_device (const char *src, const char *dest,
                        int64_t srcoffset, int64_t destoffset, int64_t size)
{
  char *src_buf;
  int r;

  src_buf = sysroot_path (src);
  if (!src_buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = copy (src_buf, src, dest, dest, DEST_DEVICE_FLAGS,
            srcoffset, destoffset, size);
  free (src_buf);

  return r;
}

int
do_copy_file_to_file (const char *src, const char *dest,
                      int64_t srcoffset, int64_t destoffset, int64_t size)
{
  char *src_buf, *dest_buf;
  int r;

  src_buf = sysroot_path (src);
  if (!src_buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  dest_buf = sysroot_path (dest);
  if (!dest_buf) {
    reply_with_perror ("malloc");
    free (src_buf);
    return -1;
  }

  r = copy (src_buf, src, dest_buf, dest, DEST_FILE_FLAGS,
            srcoffset, destoffset, size);
  free (src_buf);
  free (dest_buf);

  return r;
}
