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
#include <inttypes.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int64_t
do_du (char *path)
{
  int r;
  int64_t rv;
  char *out, *err;
  char *buf;
  int len;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  /* Make the path relative to /sysroot. */
  len = strlen (path) + 9;
  buf = malloc (len);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }
  snprintf (buf, len, "/sysroot%s", path);

  r = command (&out, &err, "du", "-s", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("du: %s: %s", path, err);
    free (out);
    free (err);
    return -1;
  }

  free (err);

  if (sscanf (out, "%"SCNi64, &rv) != 1) {
    reply_with_error ("du: %s: could not read output: %s", path, out);
    free (out);
    return -1;
  }

  free (out);

  return rv;
}
