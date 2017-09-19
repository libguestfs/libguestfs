/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif
#ifdef HAVE_SYS_ENDIAN_H
#include <sys/endian.h>
#endif

#if defined __APPLE__ && defined __MACH__
#include <libkern/OSByteOrder.h>
#define be64toh(x) OSSwapBigToHostInt64(x)
#endif

#include "full-read.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

/* This is implemented library-side in order to get around potential
 * protocol limits.
 *
 * A journal record can contain an arbitrarily large amount of data
 * (stuff like core dumps in particular).  To save the user from
 * having to deal with it, the implementation uses an internal
 * function that downloads to a FileOut, and we reconstruct the
 * hashtable entries from that.
 */
struct guestfs_xattr_list *
guestfs_impl_journal_get (guestfs_h *g)
{
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  CLEANUP_FREE char *buf = NULL;
  struct stat statbuf;
  struct guestfs_xattr_list *ret = NULL;
  char *p, *eofield, *eobuf;
  int fd = -1;
  size_t i, j, size;
  uint64_t len;

  tmpfile = guestfs_int_make_temp_path (g, "journal", NULL);
  if (tmpfile == NULL)
    goto err;

  if (guestfs_internal_journal_get (g, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc.  Want to return an errno to the caller. */
  size = statbuf.st_size;
  buf = malloc (size+1);
  if (!buf) {
    perrorf (g, "malloc: %zu bytes", size);
    goto err;
  }
  eobuf = &buf[size];
  *eobuf = '\0';                /* Makes strchr etc safe. */

  if (full_read (fd, buf, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size);
    goto err;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }
  fd = -1;

  j = 0;
  ret = safe_malloc (g, sizeof *ret);
  ret->len = 0;
  ret->val = NULL;

  /* There is a simple, private protocol employed here (note: it may
   * be changed at any time), where fields are sent using a big-endian
   * 64 bit length field followed by N bytes of 'field=data' binary
   * data.
   */
  for (i = 0; i < size; ) {
    if (i+8 > size) {
      error (g, "invalid data from guestfs_internal_journal_get: "
             "truncated: "
             "size=%zu, i=%zu", size, i);
      goto err;
    }
    memcpy(&len, &buf[i], sizeof(len));
    len = be64toh (len);
    i += 8;
    eofield = &buf[i+len];
    if (eofield > eobuf) {
      error (g, "invalid data from guestfs_internal_journal_get: "
             "length field is too large: "
             "size=%zu, i=%zu, len=%" PRIu64, size, i, len);
      goto err;
    }
    p = strchr (&buf[i], '=');
    if (!p || p >= eofield) {
      error (g, "invalid data from guestfs_internal_journal_get: "
             "no '=' found separating field name and data: "
             "size=%zu, i=%zu, p=%p", size, i, p);
      goto err;
    }
    *p = '\0';

    j++;
    ret->val = safe_realloc (g, ret->val, j * sizeof (struct guestfs_xattr));
    ret->val[j-1].attrname = safe_strdup (g, &buf[i]);
    ret->val[j-1].attrval_len = eofield - (p+1);
    ret->val[j-1].attrval = safe_memdup (g, p+1, eofield - (p+1));
    ret->len = j;
    i += len;
  }

  return ret;                   /* caller frees */

 err:
  guestfs_free_xattr_list (ret);
  if (fd >= 0)
    close (fd);
  return NULL;
}
