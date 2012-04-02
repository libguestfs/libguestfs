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

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mkfs_btrfs (const char *device,
               int64_t allocstart, int64_t bytecount, const char *datatype,
               int leafsize, const char *label, const char *metadata,
               int nodesize, int sectorsize)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  char *err;
  char allocstart_s[64];
  char bytecount_s[64];
  char leafsize_s[64];
  char nodesize_s[64];
  char sectorsize_s[64];

  ADD_ARG (argv, i, "mkfs.btrfs");

  /* Optional arguments. */
  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_ALLOCSTART_BITMASK) {
    if (allocstart < 0) {
      reply_with_error ("allocstart must be >= 0");
      return -1;
    }
    snprintf (allocstart_s, sizeof allocstart_s, "%" PRIi64, allocstart);
    ADD_ARG (argv, i, "--alloc-start");
    ADD_ARG (argv, i, allocstart_s);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_BYTECOUNT_BITMASK) {
    if (bytecount <= 0) { /* actually the minimum is 256MB */
      reply_with_error ("bytecount must be > 0");
      return -1;
    }
    snprintf (bytecount_s, sizeof bytecount_s, "%" PRIi64, bytecount);
    ADD_ARG (argv, i, "--byte-count");
    ADD_ARG (argv, i, bytecount_s);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_DATATYPE_BITMASK) {
    if (STRNEQ (datatype, "raid0") && STRNEQ (datatype, "raid1") &&
        STRNEQ (datatype, "raid10") && STRNEQ (datatype, "single")) {
      reply_with_error ("datatype not one of the allowed values");
      return -1;
    }
    ADD_ARG (argv, i, "--data");
    ADD_ARG (argv, i, datatype);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_LEAFSIZE_BITMASK) {
    if (!is_power_of_2 (leafsize) || leafsize <= 0) {
      reply_with_error ("leafsize must be > 0 and a power of two");
      return -1;
    }
    snprintf (leafsize_s, sizeof leafsize_s, "%d", leafsize);
    ADD_ARG (argv, i, "--leafsize");
    ADD_ARG (argv, i, leafsize_s);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_LABEL_BITMASK) {
    ADD_ARG (argv, i, "--label");
    ADD_ARG (argv, i, label);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_METADATA_BITMASK) {
    if (STRNEQ (metadata, "raid0") && STRNEQ (metadata, "raid1") &&
        STRNEQ (metadata, "raid10") && STRNEQ (metadata, "single")) {
      reply_with_error ("metadata not one of the allowed values");
      return -1;
    }
    ADD_ARG (argv, i, "--metadata");
    ADD_ARG (argv, i, metadata);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_NODESIZE_BITMASK) {
    if (!is_power_of_2 (nodesize) || nodesize <= 0) {
      reply_with_error ("nodesize must be > 0 and a power of two");
      return -1;
    }
    snprintf (nodesize_s, sizeof nodesize_s, "%d", nodesize);
    ADD_ARG (argv, i, "--nodesize");
    ADD_ARG (argv, i, nodesize_s);
  }

  if (optargs_bitmask & GUESTFS_MKFS_BTRFS_SECTORSIZE_BITMASK) {
    if (!is_power_of_2 (sectorsize) || sectorsize <= 0) {
      reply_with_error ("sectorsize must be > 0 and a power of two");
      return -1;
    }
    snprintf (sectorsize_s, sizeof sectorsize_s, "%d", sectorsize);
    ADD_ARG (argv, i, "--sectorsize");
    ADD_ARG (argv, i, sectorsize_s);
  }

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
