/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2013 Red Hat Inc.
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

GUESTFSD_EXT_CMD(str_ntfs3g_probe, ntfs-3g.probe);
GUESTFSD_EXT_CMD(str_ntfsresize, ntfsresize);
GUESTFSD_EXT_CMD(str_ntfsfix, ntfsfix);

int
optgroup_ntfs3g_available (void)
{
  return prog_exists (str_ntfs3g_probe);
}

int
optgroup_ntfsprogs_available (void)
{
  return prog_exists (str_ntfsresize);
}

int
do_ntfs_3g_probe (int rw, const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  const char *rw_flag;

  rw_flag = rw ? "-w" : "-r";

  r = commandr (NULL, &err, str_ntfs3g_probe, rw_flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return r;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsresize (const char *device, int64_t size, int force)
{
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *cmd = NULL;
  int r;
  char size_str[64];

  if (optargs_bitmask & GUESTFS_NTFSRESIZE_SIZE_BITMASK) {
    if (size <= 0) {
      reply_with_error ("size is zero or negative");
      return -1;
    }

    snprintf (size_str, sizeof size_str, " --size %" PRIi64, size);
  }
  else
    size_str[0] = '\0';

  if (!(optargs_bitmask & GUESTFS_NTFSRESIZE_FORCE_BITMASK))
    force = 0;

  if (asprintf_nowarn (&cmd, "yes | %s -P%s%s %Q",
		       str_ntfsresize,
		       size_str,
		       force ? " --force" : "",
		       device) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  printf ("%s\n", cmd);

  r = system (cmd);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    reply_with_error ("command failed: %s (enable debug to see the full error message)", cmd);
    return -1;
  }

  return 0;
}

int
do_ntfsresize_size (const char *device, int64_t size)
{
  optargs_bitmask = GUESTFS_NTFSRESIZE_SIZE_BITMASK;
  return do_ntfsresize (device, size, 0);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsfix (const char *device, int clearbadsectors)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;

  ADD_ARG (argv, i, str_ntfsfix);

  if ((optargs_bitmask & GUESTFS_NTFSFIX_CLEARBADSECTORS_BITMASK) &&
      clearbadsectors)
    ADD_ARG (argv, i, "-b");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}
