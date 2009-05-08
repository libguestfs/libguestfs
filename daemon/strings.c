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

char **
do_strings_e (const char *encoding, const char *path)
{
  int len;
  char *buf;
  int r;
  char *out, *err;
  char **lines = NULL;
  int size = 0, alloc = 0;
  char *p, *pend;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  len = strlen (path) + 9;
  buf = malloc (len);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  snprintf (buf, len, "/sysroot%s", path);

  r = command (&out, &err, "strings", "-e", encoding, buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("strings: %s: %s", path, err);
    free (err);
    free (out);
    return NULL;
  }

  free (err);

  /* Now convert the output to a list of lines. */
  p = out;
  while (p && *p) {
    pend = strchr (p, '\n');
    if (pend) {
      *pend = '\0';
      pend++;
    }

    if (add_string (&lines, &size, &alloc, p) == -1) {
      free (out);
      return NULL;
    }

    p = pend;
  }

  free (out);

  if (add_string (&lines, &size, &alloc, NULL) == -1)
    return NULL;

  return lines;			/* Caller frees. */
}

char **
do_strings (const char *path)
{
  return do_strings_e ("s", path);
}
