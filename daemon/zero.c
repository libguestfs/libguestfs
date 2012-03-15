/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/statvfs.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

static const char zero_buf[4096];

int
do_zero (const char *device)
{
  char buf[sizeof zero_buf];
  int fd;
  size_t i, offset;

  fd = open (device, O_RDWR|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return -1;
  }

  for (i = 0; i < 32; ++i) {
    offset = i * sizeof zero_buf;

    /* Check if the block is already zero before overwriting it. */
    if (pread (fd, buf, sizeof buf, offset) != sizeof buf) {
      reply_with_perror ("pread: %s", device);
      close (fd);
      return -1;
    }

    if (!is_zero (buf, sizeof buf)) {
      if (pwrite (fd, zero_buf, sizeof zero_buf, offset) != sizeof zero_buf) {
        reply_with_perror ("pwrite: %s", device);
        close (fd);
        return -1;
      }
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
optgroup_wipefs_available (void)
{
  return prog_exists ("wipefs");
}

int
do_wipefs (const char *device)
{
  int r;
  char *err = NULL;

  const char *wipefs[] = {"wipefs", "-a", device, NULL};
  r = commandv (NULL, &err, wipefs);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_zero_device (const char *device)
{
  int64_t ssize = do_blockdev_getsize64 (device);
  if (ssize == -1)
    return -1;
  uint64_t size = (uint64_t) ssize;

  int fd = open (device, O_RDWR|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return -1;
  }

  char buf[sizeof zero_buf];

  uint64_t pos = 0;

  while (pos < size) {
    uint64_t n64 = size - pos;
    size_t n;
    if (n64 > sizeof buf)
      n = sizeof buf;
    else
      n = (size_t) n64; /* safe because of if condition */

    /* Check if the block is already zero before overwriting it. */
    ssize_t r;
    r = pread (fd, buf, n, pos);
    if (r == -1) {
      reply_with_perror ("pread: %s at offset %" PRIu64, device, pos);
      close (fd);
      return -1;
    }

    if (!is_zero (buf, sizeof buf)) {
      r = pwrite (fd, zero_buf, n, pos);
      if (r == -1) {
        reply_with_perror ("pwrite: %s (with %" PRId64 " bytes left to write)",
                           device, size);
        close (fd);
        return -1;
      }
      pos += r;
    }
    else
      pos += n;

    notify_progress (pos, size);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", device);
    return -1;
  }

  return 0;
}

int
do_is_zero (const char *path)
{
  int fd;
  char buf[1024*1024];
  ssize_t r;

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  while ((r = read (fd, buf, sizeof buf)) > 0) {
    if (!is_zero (buf, r)) {
      close (fd);
      return 0;
    }
  }

  if (r == -1) {
    reply_with_perror ("read: %s", path);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 1;
}

int
do_is_zero_device (const char *device)
{
  int fd;
  char buf[1024*1024];
  ssize_t r;

  fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return -1;
  }

  while ((r = read (fd, buf, sizeof buf)) > 0) {
    if (!is_zero (buf, r)) {
      close (fd);
      return 0;
    }
  }

  if (r == -1) {
    reply_with_perror ("read: %s", device);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", device);
    return -1;
  }

  return 1;
}

static int
random_name (char *p)
{
  int fd;
  unsigned char c;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("/dev/urandom");
    return -1;
  }

  while (*p) {
    if (*p == 'X') {
      if (read (fd, &c, 1) != 1) {
        reply_with_perror ("read: /dev/urandom");
        close (fd);
        return -1;
      }
      *p = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
    }

    p++;
  }

  close (fd);
  return 0;
}

/* Current implementation is to create a file of all zeroes, then
 * delete it.  The description of this function is left open in order
 * to allow better implementations in future, including
 * sparsification.
 */
int
do_zero_free_space (const char *dir)
{
  size_t len = strlen (dir);
  char filename[sysroot_len+len+14]; /* sysroot + dir + "/" + 8.3 + "\0" */
  int fd;
  unsigned skip = 0;
  struct statvfs statbuf;
  fsblkcnt_t bfree_initial;

  /* Choose a randomly named 8.3 file.  Because of the random name,
   * this won't conflict with existing files, and it should be
   * compatible with any filesystem type inc. FAT.
   */
  snprintf (filename, sysroot_len+len+14, "%s%s/XXXXXXXX.XXX", sysroot, dir);
  if (random_name (&filename[sysroot_len+len]) == -1)
    return -1;

  if (verbose)
    printf ("random filename: %s\n", filename);

  /* Open file and fill with zeroes until we run out of space. */
  fd = open (filename, O_WRONLY|O_CREAT|O_EXCL|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    reply_with_perror ("open: %s", filename);
    return -1;
  }

  /* To estimate progress in this operation, we're going to track
   * free blocks in this filesystem down to zero.
   */
  if (fstatvfs (fd, &statbuf) == -1) {
    reply_with_perror ("fstatvfs");
    close (fd);
    return -1;
  }
  bfree_initial = statbuf.f_bfree;

  for (;;) {
    if (write (fd, zero_buf, sizeof zero_buf) == -1) {
      if (errno == ENOSPC)      /* expected error */
        break;
      reply_with_perror ("write: %s", filename);
      close (fd);
      unlink (filename);
      return -1;
    }

    skip++;
    if ((skip & 256) == 0 && fstatvfs (fd, &statbuf) == 0)
      notify_progress (bfree_initial - statbuf.f_bfree, bfree_initial);
  }

  /* Make sure the file is completely written to disk. */
  close (fd); /* expect this to give an error, don't check it */

  sync_disks ();

  notify_progress (bfree_initial, bfree_initial);

  /* Remove the file. */
  if (unlink (filename) == -1) {
    reply_with_perror ("unlink: %s", filename);
    return -1;
  }

  return 0;
}
