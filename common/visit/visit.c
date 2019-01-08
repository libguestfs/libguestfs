/* virt-ls visitor function
 * Copyright (C) 2010-2019 Red Hat Inc.
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

/**
 * This file contains a recursive function for visiting all files and
 * directories in a guestfs filesystem.
 *
 * Adapted from
 * L<https://rwmj.wordpress.com/2010/12/15/tip-audit-virtual-machine-for-setuid-files/>
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <libintl.h>

#include "getprogname.h"

#include "guestfs.h"
#include "guestfs-utils.h"
#include "structs-cleanups.h"

#include "visit.h"

static int _visit (guestfs_h *g, int depth, const char *dir, visitor_function f, void *opaque);

/**
 * Visit every file and directory in a guestfs filesystem, starting
 * at C<dir>.
 *
 * C<dir> may be C<"/"> to visit the entire filesystem, or may be some
 * subdirectory.  Symbolic links are not followed.
 *
 * The visitor function C<f> is called once for every directory and
 * every file.  The parameters passed to C<f> include the current
 * directory name, the current file name (or C<NULL> when we're
 * visiting a directory), the C<guestfs_statns> (file permissions
 * etc), and the list of extended attributes of the file.  The visitor
 * function may return C<-1> which causes the whole recursion to stop
 * with an error.
 *
 * Also passed to this function is an C<opaque> pointer which is
 * passed through to the visitor function.
 *
 * Returns C<0> if everything went OK, or C<-1> if there was an error.
 * Error handling is not particularly well defined.  It will either
 * set an error in the libguestfs handle or print an error on stderr,
 * but there is no way for the caller to tell the difference.
 */
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
    CLEANUP_FREE char *attrval = NULL;
    struct guestfs_xattr_list file_xattrs;
    size_t nr_xattrs;

    assert (stats->len >= i);
    assert (xattrs->len >= xattrp);

    /* Find the list of extended attributes for this file. */
    assert (strlen (xattrs->val[xattrp].attrname) == 0);

    if (xattrs->val[xattrp].attrval_len == 0) {
      fprintf (stderr, _("%s: error getting extended attrs for %s %s\n"),
               getprogname (), dir, names[i]);
      return -1;
    }
    /* attrval is not \0-terminated. */
    attrval = malloc (xattrs->val[xattrp].attrval_len + 1);
    if (attrval == NULL) {
      perror ("malloc");
      return -1;
    }
    memcpy (attrval, xattrs->val[xattrp].attrval,
            xattrs->val[xattrp].attrval_len);
    attrval[xattrs->val[xattrp].attrval_len] = '\0';
    if (sscanf (attrval, "%zu", &nr_xattrs) != 1) {
      fprintf (stderr, _("%s: error: cannot parse xattr count for %s %s\n"),
               getprogname (), dir, names[i]);
      return -1;
    }

    file_xattrs.len = nr_xattrs;
    file_xattrs.val = &xattrs->val[xattrp+1];
    xattrp += nr_xattrs;

    /* Call the function. */
    if (f (dir, names[i], &stats->val[i], &file_xattrs, opaque) == -1)
      return -1;

    /* Recursively call visit, but only on directories. */
    if (guestfs_int_is_dir (stats->val[i].st_mode)) {
      path = guestfs_int_full_path (dir, names[i]);
      if (!path) {
        perror ("guestfs_int_full_path");
        return -1;
      }
      if (_visit (g, depth + 1, path, f, opaque) == -1)
        return -1;
    }
  }

  return 0;
}
