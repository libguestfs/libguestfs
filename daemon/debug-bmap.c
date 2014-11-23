/* libguestfs - the guestfsd daemon
 * Copyright (C) 2014 Red Hat Inc.
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

/* This file provides some interim APIs for virt-bmap.  They will
 * eventually be replaced by real APIs, see:
 * https://www.redhat.com/archives/libguestfs/2014-November/msg00197.html
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/fs.h>

#include "daemon.h"
#include "actions.h"

static int fd = -1;
static DIR *dir = NULL;
static struct stat statbuf;

static void bmap_finalize (void) __attribute__((destructor));
static void
bmap_finalize (void)
{
  if (fd >= 0) {
    close (fd);
    fd = -1;
  }
  if (dir != NULL) {
    closedir (dir);
    dir = NULL;
  }
}

static char *
bmap_prepare (const char *path, const char *orig_path)
{
  char *ret;

  bmap_finalize ();

  if (stat (path, &statbuf) == -1) {
    reply_with_perror ("%s", orig_path);
    return NULL;
  }

  if (S_ISDIR (statbuf.st_mode)) {
    /* Open a directory. */
    dir = opendir (path);
    if (dir == NULL) {
      reply_with_perror ("opendir: %s", orig_path);
      return NULL;
    }
  }
  else {
    /* Open a regular file. */
    fd = open (path, O_RDONLY | O_CLOEXEC);
    if (fd == -1) {
      reply_with_perror ("%s", orig_path);
      return NULL;
    }

    posix_fadvise (fd, 0, 0,
                   POSIX_FADV_SEQUENTIAL |
                   POSIX_FADV_NOREUSE |
                   POSIX_FADV_DONTNEED);
  }

  ret = strdup ("ok");
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }
  return ret;
}

char *
debug_bmap_file (const char *subcmd, size_t argc, char *const *const argv)
{
  CLEANUP_FREE char *buf = NULL;
  const char *path;

  if (argc != 1) {
    reply_with_error ("bmap-file: missing path");
    return NULL;
  }
  path = argv[0];

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  return bmap_prepare (buf, path);
}

char *
debug_bmap_device (const char *subcmd, size_t argc, char *const *const argv)
{
  const char *device;

  if (argc != 1) {
    reply_with_error ("bmap-device: missing device");
    return NULL;
  }
  device = argv[0];

  return bmap_prepare (device, device);
}

static char buffer[BUFSIZ];

char *
debug_bmap (const char *subcmd, size_t argc, char *const *const argv)
{
  uint64_t n;
  ssize_t r;
  struct dirent *d;
  char *ret;

  if (argc != 0) {
    reply_with_error ("bmap: extra parameters on command line");
    return NULL;
  }

  /* Drop caches before starting the read. */
  if (do_drop_caches (3) == -1)
    return NULL;

  if (fd >= 0) {
    if (S_ISBLK (statbuf.st_mode)) {
      /* Get size of block device. */
      if (ioctl (fd, BLKGETSIZE64, &n) == -1) {
        reply_with_perror ("ioctl: BLKGETSIZE64");
        return NULL;
      }
    }
    else
      n = statbuf.st_size;

    while (n > 0) {
      r = read (fd, buffer, n > BUFSIZ ? BUFSIZ : n);
      if (r == -1) {
        reply_with_perror ("read");
        close (fd);
        fd = -1;
        return NULL;
      }
      n -= r;
    }

    if (close (fd) == -1) {
      reply_with_perror ("close");
      fd = -1;
      return NULL;
    }
    fd = -1;
  }

  if (dir != NULL) {
    for (;;) {
      errno = 0;
      d = readdir (dir);
      if (!d) break;
    }

    /* Check readdir didn't fail */
    if (errno != 0) {
      reply_with_perror ("readdir");
      closedir (dir);
      dir = NULL;
      return NULL;
    }

    /* Close the directory handle */
    if (closedir (dir) == -1) {
      reply_with_perror ("closedir");
      dir = NULL;
      return NULL;
    }
    dir = NULL;
  }

  ret = strdup ("ok");
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }
  return ret;
}
