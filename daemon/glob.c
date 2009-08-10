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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <glob.h>

#include "daemon.h"
#include "actions.h"

char **
do_glob_expand (char *pattern)
{
  int r;
  glob_t buf;

  NEED_ROOT (NULL);
  ABS_PATH (pattern, return NULL);	/* Required so chroot can be used. */

  /* glob(3) in glibc never calls chdir, so this seems to be safe: */
  CHROOT_IN;
  r = glob (pattern, GLOB_MARK|GLOB_BRACE, NULL, &buf);
  CHROOT_OUT;

  if (r == GLOB_NOMATCH) {	/* Return an empty list instead of an error. */
    char **rv;

    rv = malloc (sizeof (char *) * 1);
    rv[0] = NULL;
    return rv;			/* Caller frees. */
  }

  if (r != 0) {
    if (errno != 0)
      reply_with_perror ("glob: %s", pattern);
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
