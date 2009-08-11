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

int
do_set_e2label (const char *device, const char *label)
{
  int r;
  char *err;

  r = command (NULL, &err, "/sbin/e2label", device, label, NULL);
  if (r == -1) {
    reply_with_error ("e2label: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

char *
do_get_e2label (const char *device)
{
  int r, len;
  char *out, *err;

  r = command (&out, &err, "/sbin/e2label", device, NULL);
  if (r == -1) {
    reply_with_error ("e2label: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  /* Remove any trailing \n from the label. */
  len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  return out;			/* caller frees */
}

int
do_set_e2uuid (const char *device, const char *uuid)
{
  int r;
  char *err;

  r = command (NULL, &err, "/sbin/tune2fs", "-U", uuid, device, NULL);
  if (r == -1) {
    reply_with_error ("tune2fs -U: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

char *
do_get_e2uuid (const char *device)
{
  int r;
  char *out, *err, *p, *q;

  /* It's not so straightforward to get the volume UUID.  We have
   * to use tune2fs -l and then look for a particular string in
   * the output.
   */

  r = command (&out, &err, "/sbin/tune2fs", "-l", device, NULL);
  if (r == -1) {
    reply_with_error ("tune2fs -l: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  /* Look for /\nFilesystem UUID:\s+/ in the output. */
  p = strstr (out, "\nFilesystem UUID:");
  if (p == NULL) {
    reply_with_error ("no Filesystem UUID in the output of tune2fs -l");
    free (out);
    return NULL;
  }

  p += 17;
  while (*p && isspace (*p))
    p++;
  if (!*p) {
    reply_with_error ("malformed Filesystem UUID in the output of tune2fs -l");
    free (out);
    return NULL;
  }

  /* Now 'p' hopefully points to the start of the UUID. */
  q = p;
  while (*q && (isxdigit (*q) || *q == '-'))
    q++;
  if (!*q) {
    reply_with_error ("malformed Filesystem UUID in the output of tune2fs -l");
    free (out);
    return NULL;
  }

  *q = '\0';

  p = strdup (p);
  if (!p) {
    reply_with_perror ("strdup");
    free (out);
    return NULL;
  }

  free (out);
  return p;			/* caller frees */
}

int
do_resize2fs (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err, "/sbin/resize2fs", device, NULL);
  if (r == -1) {
    reply_with_error ("resize2fs: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_e2fsck_f (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err, "/sbin/e2fsck", "-p", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("e2fsck: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
