/* libguestfs
 * Copyright (C) 2011-2019 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <libintl.h>

#include "p2v.h"

/**
 * Read the whole file into a memory buffer and return it.  The file
 * should be a regular, local, trusted file.
 */
int
read_whole_file (const char *filename, char **data_r, size_t *size_r)
{
  int fd;
  char *data;
  off_t size;
  off_t n;
  ssize_t r;
  struct stat statbuf;

  fd = open (filename, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    fprintf (stderr, "open: %s: %m\n", filename);
    return -1;
  }

  if (fstat (fd, &statbuf) == -1) {
    fprintf (stderr, "stat: %s: %m\n", filename);
    close (fd);
    return -1;
  }

  size = statbuf.st_size;
  data = malloc (size + 1);
  if (data == NULL) {
    perror ("malloc");
    return -1;
  }

  n = 0;
  while (n < size) {
    r = read (fd, &data[n], size - n);
    if (r == -1) {
      fprintf (stderr, "read: %s: %m\n", filename);
      free (data);
      close (fd);
      return -1;
    }
    if (r == 0) {
      fprintf (stderr, "read: %s: unexpected end of file\n", filename);
      free (data);
      close (fd);
      return -1;
    }
    n += r;
  }

  if (close (fd) == -1) {
    fprintf (stderr, "close: %s: %m\n", filename);
    free (data);
    return -1;
  }

  /* For convenience of callers, \0-terminate the data. */
  data[size] = '\0';

  *data_r = data;
  if (size_r != NULL)
    *size_r = size;

  return 0;
}
