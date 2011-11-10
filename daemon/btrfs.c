/* libguestfs - the guestfsd daemon
 * Copyright (C) 2011 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 64

int
optgroup_btrfs_available (void)
{
  return prog_exists ("btrfs");
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_btrfs_filesystem_resize (const char *filesystem, int64_t size)
{
  char *buf;
  char *err;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char size_str[32];

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "filesystem");
  ADD_ARG (argv, i, "resize");

  if (optargs_bitmask & GUESTFS_BTRFS_FILESYSTEM_RESIZE_SIZE_BITMASK) {
    if (size <= 0) {
      reply_with_error ("size is zero or negative");
      return -1;
    }

    snprintf (size_str, sizeof size_str, "%" PRIi64, size);
    ADD_ARG (argv, i, size_str);
  }
  else
    ADD_ARG (argv, i, "max");

  buf = sysroot_path (filesystem);
  if (!buf) {
    reply_with_error ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (buf);

  if (r == -1) {
    reply_with_error ("%s: %s", filesystem, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
