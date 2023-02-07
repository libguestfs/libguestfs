/* libguestfs
 * Copyright (C) 2011-2023 Red Hat Inc.
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

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * Read the whole file C<filename> into a memory buffer.
 *
 * The memory buffer is initialized and returned in C<data_r>.  The
 * size of the file in bytes is returned in C<size_r>.  The return
 * buffer must be freed by the caller.
 *
 * On error this sets the error in the handle and returns C<-1>.
 *
 * For the convenience of callers, the returned buffer is
 * NUL-terminated (the NUL is not included in the size).
 *
 * The file must be a B<regular>, B<local>, B<trusted> file.  In
 * particular, do not use this function to read files that might be
 * under control of an untrusted user since that will lead to a
 * denial-of-service attack.
 */
int
guestfs_int_read_whole_file (guestfs_h *g, const char *filename,
                             char **data_r, size_t *size_r)
{
  int fd;
  char *data;
  off_t size;
  off_t n;
  ssize_t r;
  struct stat statbuf;

  fd = open (filename, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    return -1;
  }

  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", filename);
    close (fd);
    return -1;
  }

  size = statbuf.st_size;
  data = safe_malloc (g, size + 1);

  n = 0;
  while (n < size) {
    r = read (fd, &data[n], size - n);
    if (r == -1) {
      perrorf (g, "read: %s", filename);
      free (data);
      close (fd);
      return -1;
    }
    if (r == 0) {
      error (g, _("read: %s: unexpected end of file"), filename);
      free (data);
      close (fd);
      return -1;
    }
    n += r;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", filename);
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
