/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs.h"
#include "guestfs_protocol.h"
#include "guestfs-internal.h"
#include "guestfs-internal-all.h"
#include "guestfs-internal-actions.h"

static struct guestfs_tsk_dirent_list *parse_dirent_file (guestfs_h *, const char *);
static int deserialise_dirent_list (guestfs_h *, FILE *, struct guestfs_tsk_dirent_list *);

struct guestfs_tsk_dirent_list *
guestfs_impl_filesystem_walk (guestfs_h *g, const char *mountable)
{
  int ret = 0;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;

  tmpfile = guestfs_int_make_temp_path (g, "filesystem_walk", NULL);
  if (tmpfile == NULL)
    return NULL;

  ret = guestfs_internal_filesystem_walk (g, mountable, tmpfile);
  if (ret < 0)
    return NULL;

  return parse_dirent_file (g, tmpfile);  /* caller frees */
}

struct guestfs_tsk_dirent_list *
guestfs_impl_find_inode (guestfs_h *g, const char *mountable, int64_t inode)
{
  int ret = 0;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;

  tmpfile = guestfs_int_make_temp_path (g, "find_inode", NULL);
  if (tmpfile == NULL)
    return NULL;

  ret = guestfs_internal_find_inode (g, mountable, inode, tmpfile);
  if (ret < 0)
    return NULL;

  return parse_dirent_file (g, tmpfile);  /* caller frees */
}

/* Parse the file content and return dirents list.
 * Return a list of tsk_dirent on success, NULL on error.
 */
static struct guestfs_tsk_dirent_list *
parse_dirent_file (guestfs_h *g, const char *tmpfile)
{
  int ret = 0;
  CLEANUP_FCLOSE FILE *fp = NULL;
  struct guestfs_tsk_dirent_list *dirents = NULL;

  fp = fopen (tmpfile, "r");
  if (fp == NULL) {
    perrorf (g, "fopen: %s", tmpfile);
    return NULL;
  }

  /* Initialise results array. */
  dirents = safe_malloc (g, sizeof (*dirents));
  dirents->len = 8;
  dirents->val = safe_malloc (g, dirents->len * sizeof (*dirents->val));

  /* Deserialise buffer into dirent list. */
  ret = deserialise_dirent_list (g, fp, dirents);
  if (ret < 0) {
    guestfs_free_tsk_dirent_list (dirents);
    return NULL;
  }

  return dirents;
}

/* Deserialise the file content and populate the dirent list.
 * Return the number of deserialised dirents, -1 on error.
 */
static int
deserialise_dirent_list (guestfs_h *g, FILE *fp,
                         struct guestfs_tsk_dirent_list *dirents)
{
  XDR xdr;
  int ret = 0;
  uint32_t index = 0;
  struct stat statbuf;

  ret = fstat (fileno(fp), &statbuf);
  if (ret == -1)
    return -1;

  xdrstdio_create (&xdr, fp, XDR_DECODE);

  for (index = 0; xdr_getpos (&xdr) < statbuf.st_size; index++) {
    if (index == dirents->len) {
      dirents->len = 2 * dirents->len;
      dirents->val = safe_realloc (g, dirents->val,
                                   dirents->len *
                                   sizeof (*dirents->val));
    }

    /* Clear the entry so xdr logic will allocate necessary memory. */
    memset (&dirents->val[index], 0, sizeof (*dirents->val));
    ret = xdr_guestfs_int_tsk_dirent (&xdr, (guestfs_int_tsk_dirent *)
                                      &dirents->val[index]);
    if (ret == 0)
      break;
  }

  xdr_destroy (&xdr);
  dirents->len = index;

  return ret ? 0 : -1;
}
