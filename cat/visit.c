/* virt-ls visitor function
 * Copyright (C) 2010-2014 Red Hat Inc.
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

/* Adapted from
https://rwmj.wordpress.com/2010/12/15/tip-audit-virtual-machine-for-setuid-files/
*/

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "visit.h"

static int _visit (guestfs_h *g, int depth, const char *dir, visitor_function f, void *opaque);

int
visit (guestfs_h *g, const char *dir, visitor_function f, void *opaque)
{
  return _visit (g, 0, dir, f, opaque);
}

static int
_visit (guestfs_h *g, int depth, const char *dir,
        visitor_function f, void *opaque)
{
  /* Call 'f' with the top directory.  Note that ordinary recursive
   * visits will not otherwise do this, so we have to have a special
   * case.
   */
  if (depth == 0) {
    CLEANUP_FREE_STATNS struct guestfs_statns *stat = NULL;
    CLEANUP_FREE_XATTR_LIST struct guestfs_xattr_list *xattrs = NULL;
    int r;

    stat = guestfs_lstatns (g, dir);
    if (stat == NULL)
      return -1;

    xattrs = guestfs_lgetxattrs (g, dir);
    if (xattrs == NULL)
      return -1;

    r = f (dir, NULL, stat, xattrs, opaque);

    if (r == -1)
      return -1;
  }

  size_t i, xattrp;
  CLEANUP_FREE_STRING_LIST char **names = NULL;
  CLEANUP_FREE_STAT_LIST struct guestfs_statns_list *stats = NULL;
  CLEANUP_FREE_XATTR_LIST struct guestfs_xattr_list *xattrs = NULL;

  names = guestfs_ls (g, dir);
  if (names == NULL)
    return -1;

  stats = guestfs_lstatnslist (g, dir, names);
  if (stats == NULL)
    return -1;

  xattrs = guestfs_lxattrlist (g, dir, names);
  if (xattrs == NULL)
    return -1;

  /* Call function on everything in this directory. */
  for (i = 0, xattrp = 0; names[i] != NULL; ++i, ++xattrp) {
    CLEANUP_FREE char *path = NULL;
    struct guestfs_xattr_list file_xattrs;
    size_t nr_xattrs;

    assert (stats->len >= i);
    assert (xattrs->len >= xattrp);

    /* Find the list of extended attributes for this file. */
    assert (strlen (xattrs->val[xattrp].attrname) == 0);

    if (xattrs->val[xattrp].attrval_len == 0) {
      fprintf (stderr, _("%s: error getting extended attrs for %s %s\n"),
               guestfs_int_program_name, dir, names[i]);
      return -1;
    }
    /* attrval is not \0-terminated. */
    char attrval[xattrs->val[xattrp].attrval_len+1];
    memcpy (attrval, xattrs->val[xattrp].attrval,
            xattrs->val[xattrp].attrval_len);
    attrval[xattrs->val[xattrp].attrval_len] = '\0';
    if (sscanf (attrval, "%zu", &nr_xattrs) != 1) {
      fprintf (stderr, _("%s: error: cannot parse xattr count for %s %s\n"),
               guestfs_int_program_name, dir, names[i]);
      return -1;
    }

    file_xattrs.len = nr_xattrs;
    file_xattrs.val = &xattrs->val[xattrp+1];
    xattrp += nr_xattrs;

    /* Call the function. */
    if (f (dir, names[i], &stats->val[i], &file_xattrs, opaque) == -1)
      return -1;

    /* Recursively call visit, but only on directories. */
    if (is_dir (stats->val[i].st_mode)) {
      path = full_path (dir, names[i]);
      if (_visit (g, depth + 1, path, f, opaque) == -1)
        return -1;
    }
  }

  return 0;
}

char *
full_path (const char *dir, const char *name)
{
  int r;
  char *path;
  int len;

  len = strlen (dir);
  if (len > 0 && dir[len - 1] == '/')
    --len;

  if (STREQ (dir, "/"))
    r = asprintf (&path, "/%s", name ? name : "");
  else if (name)
    r = asprintf (&path, "%.*s/%s", len, dir, name);
  else
    r = asprintf (&path, "%.*s", len, dir);

  if (r == -1) {
    perror ("asprintf");
    abort ();
  }

  return path;
}

/* In the libguestfs API, modes returned by lstat and friends are
 * defined to contain Linux ABI values.  However since the "current
 * operating system" might not be Linux, we have to hard-code those
 * numbers here.
 */
int
is_reg (int64_t mode)
{
  return (mode & 0170000) == 0100000;
}

int
is_dir (int64_t mode)
{
  return (mode & 0170000) == 0040000;
}

int
is_chr (int64_t mode)
{
  return (mode & 0170000) == 0020000;
}

int
is_blk (int64_t mode)
{
  return (mode & 0170000) == 0060000;
}

int
is_fifo (int64_t mode)
{
  return (mode & 0170000) == 0010000;
}

/* symbolic link */
int
is_lnk (int64_t mode)
{
  return (mode & 0170000) == 0120000;
}

int
is_sock (int64_t mode)
{
  return (mode & 0170000) == 0140000;
}
