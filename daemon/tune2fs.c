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

#define _GNU_SOURCE // for strchrnul

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <ctype.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

char **
do_tune2fs_l (const char *device)
{
  int r;
  char *out, *err;
  char *p, *pend, *colon;
  char **ret = NULL;
  int size = 0, alloc = 0;

  IS_DEVICE (device, NULL);

  r = command (&out, &err, "/sbin/tune2fs", "-l", device, NULL);
  if (r == -1) {
    reply_with_error ("tune2fs: %s", err);
    free (err);
    free (out);
    return NULL;
  }
  free (err);

  p = out;

  /* Discard the first line if it contains "tune2fs ...". */
  if (strncmp (p, "tune2fs ", 8) == 0) {
    p = strchr (p, '\n');
    if (p) p++;
    else {
      reply_with_error ("tune2fs: truncated output");
      free (out);
      return NULL;
    }
  }

  /* Read the lines and split into "key: value". */
  while (*p) {
    pend = strchrnul (p, '\n');
    if (*pend == '\n') {
      *pend = '\0';
      pend++;
    }

    if (!*p) continue;

    colon = strchr (p, ':');
    if (colon) {
      *colon = '\0';

      do { colon++; } while (*colon && isspace (*colon));

      if (add_string (&ret, &size, &alloc, p) == -1) {
	free (out);
	return NULL;
      }
      if (strcmp (colon, "<none>") == 0 ||
	  strcmp (colon, "<not available>") == 0 ||
	  strcmp (colon, "(none)") == 0) {
	if (add_string (&ret, &size, &alloc, "") == -1) {
	  free (out);
	  return NULL;
	}
      } else {
	if (add_string (&ret, &size, &alloc, colon) == -1) {
	  free (out);
	  return NULL;
	}
      }
    }
    else {
      if (add_string (&ret, &size, &alloc, p) == -1) {
	free (out);
	return NULL;
      }
      if (add_string (&ret, &size, &alloc, "") == -1) {
	free (out);
	return NULL;
      }
    }

    p = pend;
  }

  free (out);

  if (add_string (&ret, &size, &alloc, NULL) == -1)
    return NULL;

  return ret;
}
