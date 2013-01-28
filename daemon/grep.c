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

#define MAX_ARGS 64

static char **
grep (const char *regex, const char *path,
      int extended, int fixed, int insensitive, int compressed)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *out = NULL, *err = NULL;
  int fd, flags, r;
  char **lines;

  if (extended && fixed) {
    reply_with_error ("can't use 'extended' and 'fixed' flags at the same time");
    return NULL;
  }

  if (!compressed)
    ADD_ARG (argv, i, "grep");
  else
    ADD_ARG (argv, i, "zgrep");

  if (extended)
    ADD_ARG (argv, i, "-E");

  if (fixed)
    ADD_ARG (argv, i, "-F");

  if (insensitive)
    ADD_ARG (argv, i, "-i");

  ADD_ARG (argv, i, regex);
  ADD_ARG (argv, i, NULL);

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  /* Note that grep returns an error if no match.  We want to
   * suppress this error and return an empty list.
   */
  flags = COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN | fd;
  r = commandrvf (&out, &err, flags, argv);
  if (r == -1 || r > 1) {
    reply_with_error ("%s: %s", regex, err);
    return NULL;
  }

  lines = split_lines (out);
  if (lines == NULL) return NULL;

  return lines;
}

/* Takes optional arguments, consult optargs_bitmask. */
char **
do_grep (const char *regex, const char *path,
         int extended, int fixed, int insensitive, int compressed)
{
  if (!(optargs_bitmask & GUESTFS_GREP_EXTENDED_BITMASK))
    extended = 0;
  if (!(optargs_bitmask & GUESTFS_GREP_FIXED_BITMASK))
    fixed = 0;
  if (!(optargs_bitmask & GUESTFS_GREP_INSENSITIVE_BITMASK))
    insensitive = 0;
  if (!(optargs_bitmask & GUESTFS_GREP_COMPRESSED_BITMASK))
    compressed = 0;

  return grep (regex, path, extended, fixed, insensitive, compressed);
}

char **
do_egrep (const char *regex, const char *path)
{
  return grep (regex, path, 1, 0, 0, 0);
}

char **
do_fgrep (const char *regex, const char *path)
{
  return grep (regex, path, 0, 1, 0, 0);
}

char **
do_grepi (const char *regex, const char *path)
{
  return grep (regex, path, 0, 0, 1, 0);
}

char **
do_egrepi (const char *regex, const char *path)
{
  return grep (regex, path, 1, 0, 1, 0);
}

char **
do_fgrepi (const char *regex, const char *path)
{
  return grep (regex, path, 0, 1, 1, 0);
}

char **
do_zgrep (const char *regex, const char *path)
{
  return grep (regex, path, 0, 0, 0, 1);
}

char **
do_zegrep (const char *regex, const char *path)
{
  return grep (regex, path, 1, 0, 0, 1);
}

char **
do_zfgrep (const char *regex, const char *path)
{
  return grep (regex, path, 0, 1, 0, 1);
}

char **
do_zgrepi (const char *regex, const char *path)
{
  return grep (regex, path, 0, 0, 1, 1);
}

char **
do_zegrepi (const char *regex, const char *path)
{
  return grep (regex, path, 1, 0, 1, 1);
}

char **
do_zfgrepi (const char *regex, const char *path)
{
  return grep (regex, path, 0, 1, 1, 1);
}
