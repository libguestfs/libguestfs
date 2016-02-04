/* libguestfs - the guestfsd daemon
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <glob.h>

#include "daemon.h"
#include "actions.h"

char **
do_glob_expand (const char *pattern, int directoryslash)
{
  int r;
  glob_t buf = { .gl_pathc = 0, .gl_pathv = NULL, .gl_offs = 0 };
  int flags = GLOB_BRACE | GLOB_MARK;

  /* GLOB_MARK is default, unless the user explicitly disabled it. */
  if ((optargs_bitmask & GUESTFS_GLOB_EXPAND_DIRECTORYSLASH_BITMASK)
      && !directoryslash) {
    flags &= ~GLOB_MARK;
  }

  /* glob(3) in glibc never calls chdir, so this seems to be safe: */
  CHROOT_IN;
  r = glob (pattern, flags, NULL, &buf);
  CHROOT_OUT;

  if (r == GLOB_NOMATCH) {	/* Return an empty list instead of an error. */
    char **rv;

    rv = malloc (sizeof (char *) * 1);
    if (rv == NULL) {
      reply_with_perror ("malloc");
      return NULL;
    }
    rv[0] = NULL;
    return rv;			/* Caller frees. */
  }

  if (r != 0) {
    if (errno != 0)
      reply_with_perror ("%s", pattern);
    else
      reply_with_error ("glob failed: %s", pattern);
    return NULL;
  }

  /* We take a bit of a liberty here.  'globfree' just frees the
   * strings in the glob_t structure.  We will pass them out directly
   * and the caller will free them.
   */
  return buf.gl_pathv;
}
