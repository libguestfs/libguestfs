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

#include "daemon.h"
#include "actions.h"

char *
do_hexdump (const char *path)
{
  int len;
  char *buf;
  int r;
  char *out, *err;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  len = strlen (path) + 9;
  buf = malloc (len);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  snprintf (buf, len, "/sysroot%s", path);

  r = command (&out, &err, "hexdump", "-C", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("hexdump: %s: %s", path, err);
    free (err);
    free (out);
    return NULL;
  }

  free (err);

  return out;			/* caller frees */
}
