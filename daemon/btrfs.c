/* libguestfs - the guestfsd daemon
 * Copyright (C) 2011-2012 Red Hat Inc.
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

int
optgroup_btrfs_available (void)
{
  return prog_exists ("btrfs");
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_btrfs_filesystem_resize (const char *filesystem, int64_t size)
{
  const size_t MAX_ARGS = 64;
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
do_mkfs_btrfs (char *const *devices,
               int64_t allocstart, int64_t bytecount, const char *datatype,
               int leafsize, const char *label, const char *metadata,
               int nodesize, int sectorsize)
{
  size_t nr_devices = count_strings (devices);

  if (nr_devices == 0) {
    reply_with_error ("list of devices must be non-empty");
    return -1;
  }

  size_t MAX_ARGS = nr_devices + 64;
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
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

  for (j = 0; j < nr_devices; ++j)
    ADD_ARG (argv, i, devices[j]);

  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", devices[0], err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_btrfs_subvolume_snapshot (const char *source, const char *dest)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *source_buf, *dest_buf;
  char *err;
  int r;

  source_buf = sysroot_path (source);
  if (source_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }
  dest_buf = sysroot_path (dest);
  if (dest_buf == NULL) {
    reply_with_perror ("malloc");
    free (source_buf);
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "snapshot");
  ADD_ARG (argv, i, source_buf);
  ADD_ARG (argv, i, dest_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (source_buf);
  free (dest_buf);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", source, dest, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_subvolume_delete (const char *subvolume)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *subvolume_buf;
  char *err;
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "delete");
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (subvolume_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_subvolume_create (const char *dest)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *dest_buf;
  char *err;
  int r;

  dest_buf = sysroot_path (dest);
  if (dest_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "create");
  ADD_ARG (argv, i, dest_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (dest_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", dest, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

guestfs_int_btrfssubvolume_list *
do_btrfs_subvolume_list (const char *fs)
{
  const size_t MAX_ARGS = 64;
  guestfs_int_btrfssubvolume_list *ret;
  char *fs_buf;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *out, *err, **lines, *pos;
  size_t nr_subvolumes;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "list");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return NULL;
  }
  free (err);

  lines = split_lines (out);
  free (out);
  if (!lines)
    return NULL;

  /* Output is:
   *
   * ID 256 top level 5 path test1
   * ID 257 top level 5 path dir/test2
   * ID 258 top level 5 path test3
   *
   * "ID <n>" is the subvolume ID.  "top level <n>" is the top level
   * subvolume ID.  "path <str>" is the subvolume path, relative to
   * the top of the filesystem.
   */
  nr_subvolumes = count_strings (lines);

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    free_stringslen (lines, nr_subvolumes);
    return NULL;
  }
  ret->guestfs_int_btrfssubvolume_list_len = nr_subvolumes;
  ret->guestfs_int_btrfssubvolume_list_val =
    calloc (nr_subvolumes, sizeof (struct guestfs_int_btrfssubvolume));
  if (ret->guestfs_int_btrfssubvolume_list_val == NULL) {
    reply_with_perror ("malloc");
    free (ret);
    free_stringslen (lines, nr_subvolumes);
    return NULL;
  }

  for (i = 0; i < nr_subvolumes; ++i) {
    /* To avoid allocations, reuse the 'line' buffer to store the
     * path.  Thus we don't need to free 'line', since it will be
     * freed by the calling (XDR) code.
     */
    char *line = lines[i];

    if (sscanf (line, "ID %" SCNu64 " top level %" SCNu64 " path ",
                &ret->guestfs_int_btrfssubvolume_list_val[i].btrfssubvolume_id,
                &ret->guestfs_int_btrfssubvolume_list_val[i].btrfssubvolume_top_level_id) != 2) {
    unexpected_output:
      reply_with_error ("unexpected output from 'btrfs subvolume list' command: %s", line);
      free_stringslen (lines, nr_subvolumes);
      free (ret->guestfs_int_btrfssubvolume_list_val);
      free (ret);
      return NULL;
    }

    pos = strstr (line, " path ");
    if (pos == NULL)
      goto unexpected_output;
    pos += 6;

    memmove (line, pos, strlen (pos) + 1);
    ret->guestfs_int_btrfssubvolume_list_val[i].btrfssubvolume_path = line;
  }

  return ret;
}

int
do_btrfs_subvolume_set_default (int64_t id, const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf;
  char buf[64];
  char *err;
  int r;

  snprintf (buf, sizeof buf, "%" PRIi64, id);

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "set-default");
  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_filesystem_sync (const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf;
  char *err;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "filesystem");
  ADD_ARG (argv, i, "sync");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_filesystem_balance (const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf;
  char *err;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "filesystem");
  ADD_ARG (argv, i, "balance");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_device_add (char *const *devices, const char *fs)
{
  size_t nr_devices = count_strings (devices);

  if (nr_devices == 0)
    return 0;

  size_t MAX_ARGS = nr_devices + 8;
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  char *fs_buf;
  char *err;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "device");
  ADD_ARG (argv, i, "add");

  for (j = 0; j < nr_devices; ++j)
    ADD_ARG (argv, i, devices[j]);

  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_device_delete (char *const *devices, const char *fs)
{
  size_t nr_devices = count_strings (devices);

  if (nr_devices == 0)
    return 0;

  size_t MAX_ARGS = nr_devices + 8;
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  char *fs_buf;
  char *err;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "btrfs");
  ADD_ARG (argv, i, "device");
  ADD_ARG (argv, i, "delete");

  for (j = 0; j < nr_devices; ++j)
    ADD_ARG (argv, i, devices[j]);

  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  free (fs_buf);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int
do_btrfs_set_seeding (const char *device, int svalue)
{
  char *err;
  int r;

  const char *s_value = svalue ? "1" : "0";

  r = commandr (NULL, &err, "btrfstune", "-S", s_value, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_btrfs_fsck (const char *device, int64_t superblock, int repair)
{
  char *err;
  int r;
  size_t i = 0;
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  char super_s[64];

  ADD_ARG (argv, i, "btrfsck");

  /* Optional arguments. */
  if (optargs_bitmask & GUESTFS_BTRFS_FSCK_SUPERBLOCK_BITMASK) {
    if (superblock < 0) {
      reply_with_error ("super block offset must be >= 0");
      return -1;
    }
    snprintf (super_s, sizeof super_s, "%" PRIi64, superblock);
    ADD_ARG (argv, i, "--super");
    ADD_ARG (argv, i, super_s);
  }

  if (!(optargs_bitmask & GUESTFS_BTRFS_FSCK_REPAIR_BITMASK))
    repair = 0;

  if (repair)
    ADD_ARG (argv, i, "--repair");

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
