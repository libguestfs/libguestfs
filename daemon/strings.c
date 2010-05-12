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
  char *buf;
  int r;
  char *out, *err;
  char **lines;

  if (strlen (encoding) != 1 ||
      strchr ("sSblBL", encoding[0]) == NULL) {
    reply_with_error ("%s: invalid encoding", encoding);
    return NULL;
  }

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "strings", "-e", encoding, buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    free (err);
    free (out);
    return NULL;
  }

  free (err);

  /* Now convert the output to a list of lines. */
  lines = split_lines (out);
  free (out);

  if (lines == NULL)
    return NULL;

  return lines;			/* Caller frees. */
}

char **
do_strings (const char *path)
{
  return do_strings_e ("s", path);
}
