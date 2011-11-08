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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static char **
headtail (const char *prog, const char *flag, const char *n, const char *path)
{
  char *out, *err;
  int fd, flags, r;
  char **lines;

  CHROOT_IN;
  fd = open (path, O_RDONLY);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  flags = COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN | fd;
  r = commandf (&out, &err, flags, prog, flag, n, NULL);
  if (r == -1) {
    reply_with_error ("%s %s %s: %s", prog, flag, n, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

#if 0
  /* Split it at the first whitespace. */
  len = strcspn (out, " \t\n");
  out[len] = '\0';
#endif

  lines = split_lines (out);
  free (out);
  if (lines == NULL) return NULL;

  return lines;
}

char **
do_head (const char *path)
{
  return headtail ("head", "-n", "10", path);
}

char **
do_tail (const char *path)
{
  return headtail ("tail", "-n", "10", path);
}

char **
do_head_n (int n, const char *path)
{
  char nbuf[16];

  snprintf (nbuf, sizeof nbuf, "%d", n);

  return headtail ("head", "-n", nbuf, path);
}

char **
do_tail_n (int n, const char *path)
{
  char nbuf[16];

  if (n >= 0)
    snprintf (nbuf, sizeof nbuf, "%d", n);
  else
    snprintf (nbuf, sizeof nbuf, "+%d", -n);

  return headtail ("tail", "-n", nbuf, path);
}
