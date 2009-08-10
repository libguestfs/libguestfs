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
#include <string.h>
#include <unistd.h>
#include <limits.h>

#include "daemon.h"
#include "actions.h"

char *
do_readlink (char *path)
{
  ssize_t r;
  char *ret;
  char link[PATH_MAX];

  NEED_ROOT (return NULL);
  ABS_PATH (path, return NULL);

  CHROOT_IN;
  r = readlink (path, link, sizeof link);
  CHROOT_OUT;
  if (r == -1) {
    reply_with_perror ("readlink");
    return NULL;
  }

  ret = strndup (link, r);
  if (ret == NULL) {
    reply_with_perror ("strndup");
    return NULL;
  }

  return ret;			/* caller frees */
}

static int
_link (const char *flag, int symbolic, const char *target, const char *linkname)
{
  int r;
  char *err;
  char *buf_linkname;
  char *buf_target;

  NEED_ROOT (return -1);
  ABS_PATH (linkname, return -1);
  /* but target does not need to be absolute */

  /* Prefix linkname with sysroot. */
  buf_linkname = sysroot_path (linkname);
  if (!buf_linkname) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Only prefix target if it's _not_ a symbolic link, and if
   * the target is absolute.  Note that the resulting link will
   * always be "broken" from the p.o.v. of the appliance, ie:
   * /a -> /b but the path as seen here is /sysroot/b
   */
  buf_target = NULL;
  if (!symbolic && target[0] == '/') {
    buf_target = sysroot_path (target);
    if (!buf_target) {
      reply_with_perror ("malloc");
      free (buf_linkname);
      return -1;
    }
  }

  if (flag)
    r = command (NULL, &err,
                 "ln", flag, "--", /* target could begin with '-' */
                 buf_target ? : target, buf_linkname, NULL);
  else
    r = command (NULL, &err,
                 "ln", "--",
                 buf_target ? : target, buf_linkname, NULL);
  free (buf_linkname);
  free (buf_target);
  if (r == -1) {
    reply_with_error ("ln%s%s: %s: %s: %s",
                      flag ? " " : "",
                      flag ? : "",
                      target, linkname, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_ln (char *target, char *linkname)
{
  return _link (NULL, 0, target, linkname);
}

int
do_ln_f (char *target, char *linkname)
{
  return _link ("-f", 0, target, linkname);
}

int
do_ln_s (char *target, char *linkname)
{
  return _link ("-s", 1, target, linkname);
}

int
do_ln_sf (char *target, char *linkname)
{
  return _link ("-sf", 1, target, linkname);
}
