/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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
optgroup_ntfs3g_available (void)
{
  return prog_exists ("ntfs-3g.probe");
}

int
optgroup_ntfsprogs_available (void)
{
  return prog_exists ("ntfsresize");
}

int
do_ntfs_3g_probe (int rw, const char *device)
{
  char *err;
  int r;
  const char *rw_flag;

  rw_flag = rw ? "-w" : "-r";

  r = commandr (NULL, &err, "ntfs-3g.probe", rw_flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return r;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsresize_opts (const char *device, int64_t size, int force)
{
  char *err;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char size_str[32];

  ADD_ARG (argv, i, "ntfsresize");
  ADD_ARG (argv, i, "-P");

  if (optargs_bitmask & GUESTFS_NTFSRESIZE_OPTS_SIZE_BITMASK) {
    if (size <= 0) {
      reply_with_error ("size is zero or negative");
      return -1;
    }

    snprintf (size_str, sizeof size_str, "%" PRIi64, size);
    ADD_ARG (argv, i, "--size");
    ADD_ARG (argv, i, size_str);
  }

  if (optargs_bitmask & GUESTFS_NTFSRESIZE_OPTS_FORCE_BITMASK && force)
    ADD_ARG (argv, i, "--force");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_ntfsresize (const char *device)
{
  return do_ntfsresize_opts (device, 0, 0);
}

int
do_ntfsresize_size (const char *device, int64_t size)
{
  optargs_bitmask = GUESTFS_NTFSRESIZE_OPTS_SIZE_BITMASK;
  return do_ntfsresize_opts (device, size, 0);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsfix (const char *device, int clearbadsectors)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  char *err;

  ADD_ARG (argv, i, "ntfsfix");

  if ((optargs_bitmask & GUESTFS_NTFSFIX_CLEARBADSECTORS_BITMASK) &&
      clearbadsectors)
    ADD_ARG (argv, i, "-b");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
