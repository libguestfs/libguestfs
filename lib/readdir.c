/* libguestfs
 * Copyright (C) 2016-2023 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs.h"                  /* guestfs_internal_readdir() */
#include "guestfs_protocol.h"         /* guestfs_int_dirent */
#include "guestfs-internal.h"         /* guestfs_int_make_temp_path() */
#include "guestfs-internal-actions.h" /* guestfs_impl_readdir */

struct guestfs_dirent_list *
guestfs_impl_readdir (guestfs_h *g, const char *dir)
{
  struct guestfs_dirent_list *ret;
  char *tmpfn;
  FILE *f;
  off_t fsize;
  XDR xdr;
  struct guestfs_dirent_list *dirents;
  uint32_t alloc_entries;
  size_t alloc_bytes;

  /* Prepare to fail. */
  ret = NULL;

  tmpfn = guestfs_int_make_temp_path (g, "readdir", NULL);
  if (tmpfn == NULL)
    return ret;

  if (guestfs_internal_readdir (g, dir, tmpfn) == -1)
    goto drop_tmpfile;

  f = fopen (tmpfn, "r");
  if (f == NULL) {
    perrorf (g, "fopen: %s", tmpfn);
    goto drop_tmpfile;
  }

  if (fseeko (f, 0, SEEK_END) == -1) {
    perrorf (g, "fseeko");
    goto close_tmpfile;
  }
  fsize = ftello (f);
  if (fsize == -1) {
    perrorf (g, "ftello");
    goto close_tmpfile;
  }
  if (fseeko (f, 0, SEEK_SET) == -1) {
    perrorf (g, "fseeko");
    goto close_tmpfile;
  }

  xdrstdio_create (&xdr, f, XDR_DECODE);

  dirents = safe_malloc (g, sizeof *dirents);
  dirents->len = 0;
  alloc_entries = 8;
  alloc_bytes = alloc_entries * sizeof *dirents->val;
  dirents->val = safe_malloc (g, alloc_bytes);

  while (xdr_getpos (&xdr) < fsize) {
    guestfs_int_dirent v;
    struct guestfs_dirent *d;

    if (dirents->len == alloc_entries) {
      if (alloc_entries > UINT32_MAX / 2 || alloc_bytes > (size_t)-1 / 2) {
        error (g, "integer overflow");
        goto free_dirents;
      }
      alloc_entries *= 2u;
      alloc_bytes *= 2u;
      dirents->val = safe_realloc (g, dirents->val, alloc_bytes);
    }

    /* Decoding does not work unless the target buffer is zero-initialized. */
    memset (&v, 0, sizeof v);
    if (!xdr_guestfs_int_dirent (&xdr, &v)) {
      error (g, "xdr_guestfs_int_dirent failed");
      goto free_dirents;
    }

    d = &dirents->val[dirents->len];
    d->ino = v.ino;
    d->ftyp = v.ftyp;
    d->name = v.name; /* transfer malloc'd string to "d" */

    dirents->len++;
  }

  /* Success; transfer "dirents" to "ret". */
  ret = dirents;
  dirents = NULL;

  /* Clean up. */
  xdr_destroy (&xdr);

free_dirents:
  guestfs_free_dirent_list (dirents);

close_tmpfile:
  fclose (f);

drop_tmpfile:
  /* In case guestfs_internal_readdir() failed, it may or may not have created
   * the temporary file.
   */
  unlink (tmpfn);
  free (tmpfn);

  return ret;
}
