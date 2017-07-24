/* libguestfs - the guestfsd daemon
 * Copyright (C) 2013 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_syslinux_available (void)
{
  return prog_exists ("syslinux");
}

int
optgroup_extlinux_available (void)
{
  return prog_exists ("extlinux");
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_syslinux (const char *device, const char *directory)
{
  const size_t MAX_ARGS = 32;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *err = NULL;
  int r;

  ADD_ARG (argv, i, "syslinux");
  ADD_ARG (argv, i, "--install");
  ADD_ARG (argv, i, "--force");

  if (optargs_bitmask & GUESTFS_SYSLINUX_DIRECTORY_BITMASK) {
    ADD_ARG (argv, i, "--directory");
    ADD_ARG (argv, i, directory);
  }

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_extlinux (const char *directory)
{
  CLEANUP_FREE char *buf = sysroot_path (directory);
  CLEANUP_FREE char *err = NULL;
  int r;

  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "extlinux", "--install", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", directory, err);
    return -1;
  }

  return 0;
}
