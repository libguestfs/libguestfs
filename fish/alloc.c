/* guestfish - the filesystem interactive shell
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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>
#include <errno.h>

#include "fish.h"

int
do_alloc (const char *cmd, int argc, char *argv[])
{
  if (argc != 2) {
    fprintf (stderr, _("use 'alloc file size' to create an image\n"));
    return -1;
  }

  if (alloc_disk (argv[0], argv[1], 1, 0) == -1)
    return -1;

  return 0;
}

int
do_sparse (const char *cmd, int argc, char *argv[])
{
  if (argc != 2) {
    fprintf (stderr, _("use 'sparse file size' to create a sparse image\n"));
    return -1;
  }

  if (alloc_disk (argv[0], argv[1], 1, 1) == -1)
    return -1;

  return 0;
}

static int parse_size (const char *str, off_t *size_rtn);

/* This is the underlying allocation function.  It's called from
 * a few other places in guestfish.
 */
int
alloc_disk (const char *filename, const char *size_str, int add, int sparse)
{
  off_t size;
  int fd;
  char c = 0;

  if (parse_size (size_str, &size) == -1)
    return -1;

  if (!guestfs_is_config (g)) {
    fprintf (stderr, _("can't allocate or add disks after launching\n"));
    return -1;
  }

  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    return -1;
  }

  if (!sparse) {                /* Not sparse */
#ifdef HAVE_POSIX_FALLOCATE
    int err = posix_fallocate (fd, 0, size);
    if (err != 0) {
      errno = err;
      perror ("fallocate");
      close (fd);
      unlink (filename);
      return -1;
    }
#else
    /* Slow emulation of posix_fallocate on platforms which don't have it. */
    char buffer[BUFSIZ];
    memset (buffer, 0, sizeof buffer);

    size_t remaining = size;
    while (remaining > 0) {
      size_t n = remaining > sizeof buffer ? sizeof buffer : remaining;
      ssize_t r = write (fd, buffer, n);
      if (r == -1) {
        perror ("write");
        close (fd);
        unlink (filename);
        return -1;
      }
      remaining -= r;
    }
#endif
  } else {                      /* Sparse */
    if (lseek (fd, size-1, SEEK_SET) == (off_t) -1) {
      perror ("lseek");
      close (fd);
      unlink (filename);
      return -1;
    }

    if (write (fd, &c, 1) != 1) {
      perror ("write");
      close (fd);
      unlink (filename);
      return -1;
    }
  }

  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    return -1;
  }

  if (add) {
    if (guestfs_add_drive (g, filename) == -1) {
      unlink (filename);
      return -1;
    }
  }

  return 0;
}

static int
parse_size (const char *str, off_t *size_rtn)
{
  uint64_t size;
  char type;

  /* Note that the parsing here is looser than what is specified in the
   * help, but we may tighten it up in future so beware.
   */
  if (sscanf (str, "%"SCNu64"%c", &size, &type) == 2) {
    switch (type) {
    case 'k': case 'K': size *= 1024ULL; break;
    case 'm': case 'M': size *= 1024ULL * 1024ULL; break;
    case 'g': case 'G': size *= 1024ULL * 1024ULL * 1024ULL; break;
    case 't': case 'T': size *= 1024ULL * 1024ULL * 1024ULL * 1024ULL; break;
    case 'p': case 'P': size *= 1024ULL * 1024ULL * 1024ULL * 1024ULL * 1024ULL; break;
    case 'e': case 'E': size *= 1024ULL * 1024ULL * 1024ULL * 1024ULL * 1024ULL * 1024ULL; break;
    case 's': size *= 512; break;
    default:
      fprintf (stderr, _("could not parse size specification '%s'\n"), str);
      return -1;
    }
  }
  else if (sscanf (str, "%"SCNu64, &size) == 1)
    size *= 1024ULL;
  else {
    fprintf (stderr, _("could not parse size specification '%s'\n"), str);
    return -1;
  }

  /* XXX 32 bit file offsets, if anyone uses them?  GCC should give
   * a warning here anyhow.
   */
  *size_rtn = size;

  return 0;
}
