/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
#include <stdint.h>
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "full-read.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

static void
sort_strings (char **argv, size_t len)
{
  qsort (argv, len, sizeof (char *), compare);
}

char *
guestfs__cat (guestfs_h *g, const char *path)
{
  int fd = -1;
  size_t size;
  char *tmpfile = NULL, *ret = NULL;
  struct stat statbuf;

  tmpfile = safe_asprintf (g, "%s/cat%d", g->tmpdir, ++g->unique);

  if (guestfs_download (g, path, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  unlink (tmpfile);
  free (tmpfile);
  tmpfile = NULL;

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc, because we want to return an errno to the caller. */
  size = statbuf.st_size;
  ret = malloc (size + 1);
  if (!ret) {
    perrorf (g, "malloc: %zu bytes", size + 1);
    goto err;
  }

  if (full_read (fd, ret, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size + 1);
    goto err;
  }

  ret[size] = '\0';

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }

  return ret;

 err:
  free (ret);
  if (fd >= 0)
    close (fd);
  if (tmpfile) {
    unlink (tmpfile);
    free (tmpfile);
  }
  return NULL;
}

char **
guestfs__find (guestfs_h *g, const char *directory)
{
  int fd = -1;
  struct stat statbuf;
  char *tmpfile = NULL, *buf = NULL;
  char **ret = NULL;
  size_t i, count, size;

  tmpfile = safe_asprintf (g, "%s/find%d", g->tmpdir, ++g->unique);

  if (guestfs_find0 (g, directory, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  unlink (tmpfile);
  free (tmpfile);
  tmpfile = NULL;

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc, because we want to return an errno to the caller. */
  size = statbuf.st_size;
  buf = malloc (size);
  if (!buf) {
    perrorf (g, "malloc: %zu bytes", size);
    goto err;
  }

  if (full_read (fd, buf, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size);
    goto err;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }
  fd = -1;

  /* 'buf' contains the list of strings, separated (and terminated) by
   * '\0' characters.  Convert this to a list of lines.  Note we
   * handle the case where buf is completely empty (size == 0), even
   * though it is probably impossible.
   */
  count = 0;
  for (i = 0; i < size; ++i)
    if (buf[i] == '\0')
      count++;

  ret = malloc ((count + 1) * sizeof (char *));
  if (!ret) {
    perrorf (g, "malloc");
    goto err;
  }

  count = 0;
  ret[count++] = buf;
  for (i = 0; i < size; ++i) {
    if (buf[i] == '\0')
      ret[count++] = &buf[i+1];
  }
  ret[--count] = NULL;

  /* Finally we have to duplicate and sort the strings, since that's
   * what the caller is expecting.
   */
  for (i = 0; ret[i] != NULL; ++i) {
    ret[i] = strdup (ret[i]);
    if (ret[i] == NULL) {
      perrorf (g, "strdup");
      while (i > 0)
        free (ret[--i]);
      goto err;
    }
  }
  free (buf);

  sort_strings (ret, count);

  return ret;                   /* caller frees */

 err:
  free (buf);
  free (ret);
  if (fd >= 0)
    close (fd);
  if (tmpfile) {
    unlink (tmpfile);
    free (tmpfile);
  }
  return NULL;
}
