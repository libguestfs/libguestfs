/* libguestfs
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <libintl.h>
#include <assert.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

/**
 * Download a guest file to a local temporary file.  The file is
 * cached in the temporary directory, and is not downloaded again.
 *
 * The name of the temporary (downloaded) file is returned.  The
 * caller must free the pointer, but does I<not> need to delete the
 * temporary file.  It will be deleted when the handle is closed.
 *
 * Refuse to download the guest file if it is larger than C<max_size>.
 * On this and other errors, C<NULL> is returned.
 *
 * There is actually one cache per C<struct inspect_fs *> in order to
 * handle the case of multiple roots.
 */
char *
guestfs_int_download_to_tmp (guestfs_h *g,
			     const char *filename,
			     const char *basename, uint64_t max_size)
{
  char *r;
  int fd;
  char devfd[32];
  int64_t size;

  if (asprintf (&r, "%s/%s", g->tmpdir, basename) == -1) {
    perrorf (g, "asprintf");
    return NULL;
  }

  /* Check size of remote file. */
  size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    goto error;
  if ((uint64_t) size > max_size) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    goto error;
  }

  fd = open (r, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    perrorf (g, "open: %s", r);
    goto error;
  }

  snprintf (devfd, sizeof devfd, "/dev/fd/%d", fd);

  if (guestfs_download (g, filename, devfd) == -1) {
    unlink (r);
    close (fd);
    goto error;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", r);
    unlink (r);
    goto error;
  }

  return r;

 error:
  free (r);
  return NULL;
}

/* Parse small, unsigned ints, as used in version numbers. */
int
guestfs_int_parse_unsigned_int (guestfs_h *g, const char *str)
{
  long ret;
  const int r = xstrtol (str, NULL, 10, &ret, "");
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}
