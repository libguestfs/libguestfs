/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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
optgroup_rsync_available (void)
{
  return prog_exists ("rsync");
}

static int
rsync (const char *src, const char *src_orig,
       const char *dest, const char *dest_orig,
       int archive, int deletedest)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;

  ADD_ARG (argv, i, "rsync");

  if (archive)
    ADD_ARG (argv, i, "--archive");

  if (deletedest)
    ADD_ARG (argv, i, "--delete");

  ADD_ARG (argv, i, src);
  ADD_ARG (argv, i, dest);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("'%s' to '%s': %s", src_orig, dest_orig, err);
    return -1;
  }

  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_rsync (const char *src_orig, const char *dest_orig,
          int archive, int deletedest)
{
  CLEANUP_FREE char *src = NULL, *dest = NULL;

  src = sysroot_path (src_orig);
  dest = sysroot_path (dest_orig);
  if (!src || !dest) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (!(optargs_bitmask & GUESTFS_RSYNC_ARCHIVE_BITMASK))
    archive = 0;
  if (!(optargs_bitmask & GUESTFS_RSYNC_DELETEDEST_BITMASK))
    deletedest = 0;

  return rsync (src, src_orig, dest, dest_orig, archive, deletedest);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_rsync_in (const char *remote, const char *dest_orig,
             int archive, int deletedest)
{
  CLEANUP_FREE char *dest = NULL;

  dest = sysroot_path (dest_orig);
  if (!dest) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (!(optargs_bitmask & GUESTFS_RSYNC_IN_ARCHIVE_BITMASK))
    archive = 0;
  if (!(optargs_bitmask & GUESTFS_RSYNC_IN_DELETEDEST_BITMASK))
    deletedest = 0;

  return rsync (remote, remote, dest, dest_orig, archive, deletedest);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_rsync_out (const char *src_orig, const char *remote,
              int archive, int deletedest)
{
  CLEANUP_FREE char *src = NULL;

  src = sysroot_path (src_orig);
  if (!src) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (!(optargs_bitmask & GUESTFS_RSYNC_OUT_ARCHIVE_BITMASK))
    archive = 0;
  if (!(optargs_bitmask & GUESTFS_RSYNC_OUT_DELETEDEST_BITMASK))
    deletedest = 0;

  return rsync (src, src_orig, remote, remote, archive, deletedest);
}
