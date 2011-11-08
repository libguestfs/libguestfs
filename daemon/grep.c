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
grep (const char *prog, const char *flag, const char *regex, const char *path)
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

  /* Note that grep returns an error if no match.  We want to
   * suppress this error and return an empty list.
   */
  flags = COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN | fd;
  r = commandrf (&out, &err, flags, prog, flag, regex, NULL);
  if (r == -1 || r > 1) {
    reply_with_error ("%s %s %s: %s", prog, flag, regex, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  lines = split_lines (out);
  free (out);
  if (lines == NULL) return NULL;

  return lines;
}

char **
do_grep (const char *regex, const char *path)
{
  /* The "--" is not really needed, but it helps when we don't need a flag. */
  return grep ("grep", "--", regex, path);
}

char **
do_egrep (const char *regex, const char *path)
{
  return grep ("egrep", "--", regex, path);
}

char **
do_fgrep (const char *regex, const char *path)
{
  return grep ("fgrep", "--", regex, path);
}

char **
do_grepi (const char *regex, const char *path)
{
  return grep ("grep", "-i", regex, path);
}

char **
do_egrepi (const char *regex, const char *path)
{
  return grep ("egrep", "-i", regex, path);
}

char **
do_fgrepi (const char *regex, const char *path)
{
  return grep ("fgrep", "-i", regex, path);
}

char **
do_zgrep (const char *regex, const char *path)
{
  return grep ("zgrep", "--", regex, path);
}

char **
do_zegrep (const char *regex, const char *path)
{
  return grep ("zegrep", "--", regex, path);
}

char **
do_zfgrep (const char *regex, const char *path)
{
  return grep ("zfgrep", "--", regex, path);
}

char **
do_zgrepi (const char *regex, const char *path)
{
  return grep ("zgrep", "-i", regex, path);
}

char **
do_zegrepi (const char *regex, const char *path)
{
  return grep ("zegrep", "-i", regex, path);
}

char **
do_zfgrepi (const char *regex, const char *path)
{
  return grep ("zfgrep", "-i", regex, path);
}
