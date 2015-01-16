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
#include <pcre.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "xstrtol.h"
#include "c-ctype.h"

GUESTFSD_EXT_CMD(str_btrfs, btrfs);
GUESTFSD_EXT_CMD(str_btrfstune, btrfstune);
GUESTFSD_EXT_CMD(str_btrfsck, btrfsck);
GUESTFSD_EXT_CMD(str_mkfs_btrfs, mkfs.btrfs);
GUESTFSD_EXT_CMD(str_umount, umount);

int
optgroup_btrfs_available (void)
{
  return prog_exists (str_btrfs) && filesystem_available ("btrfs") > 0;
}

char *
btrfs_get_label (const char *device)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  char *out = NULL;
  size_t len;

  r = command (&out, &err, str_btrfs, "filesystem", "label",
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  /* Trim trailing \n if present. */
  len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  return out;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_btrfs_filesystem_resize (const char *filesystem, int64_t size)
{
  const size_t MAX_ARGS = 64;
  CLEANUP_FREE char *buf = NULL, *err = NULL;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char size_str[32];

  ADD_ARG (argv, i, str_btrfs);
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

  if (r == -1) {
    reply_with_error ("%s: %s", filesystem, err);
    return -1;
  }

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
  size_t MAX_ARGS = nr_devices + 64;
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  int r;
  CLEANUP_FREE char *err = NULL;
  char allocstart_s[64];
  char bytecount_s[64];
  char leafsize_s[64];
  char nodesize_s[64];
  char sectorsize_s[64];

  if (nr_devices == 0) {
    reply_with_error ("list of devices must be non-empty");
    return -1;
  }

  ADD_ARG (argv, i, str_mkfs_btrfs);

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

  for (j = 0; j < nr_devices; ++j)
    wipe_device_before_mkfs (devices[j]);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", devices[0], err);
    return -1;
  }

  return 0;
}

int
do_btrfs_subvolume_snapshot (const char *source, const char *dest, int ro,
                             const char *qgroupid)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *source_buf = NULL, *dest_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  source_buf = sysroot_path (source);
  if (source_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }
  dest_buf = sysroot_path (dest);
  if (dest_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "snapshot");

  /* Optional arguments. */
  if ((optargs_bitmask & GUESTFS_BTRFS_SUBVOLUME_SNAPSHOT_RO_BITMASK) &&
      ro)
    ADD_ARG (argv, i, "-r");

  if (optargs_bitmask & GUESTFS_BTRFS_SUBVOLUME_SNAPSHOT_QGROUPID_BITMASK) {
    ADD_ARG (argv, i, "-i");
    ADD_ARG (argv, i, qgroupid);
  }

  ADD_ARG (argv, i, source_buf);
  ADD_ARG (argv, i, dest_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", source, dest, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_subvolume_delete (const char *subvolume)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *subvolume_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "delete");
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_subvolume_create (const char *dest, const char *qgroupid)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *dest_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  dest_buf = sysroot_path (dest);
  if (dest_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "create");

  /* Optional arguments. */
  if (optargs_bitmask & GUESTFS_BTRFS_SUBVOLUME_CREATE_QGROUPID_BITMASK) {
    ADD_ARG (argv, i, "-i");
    ADD_ARG (argv, i, qgroupid);
  }


  ADD_ARG (argv, i, dest_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", dest, err);
    return -1;
  }

  return 0;
}

static char *
mount (const mountable_t *fs)
{
  char *fs_buf;

  if (fs->type == MOUNTABLE_PATH) {
    fs_buf = sysroot_path (fs->device);
    if (fs_buf == NULL)
      reply_with_perror ("malloc");
  } else {
    fs_buf = strdup ("/tmp/btrfs.XXXXXX");
    if (fs_buf == NULL) {
      reply_with_perror ("strdup");
      return NULL;
    }

    if (mkdtemp (fs_buf) == NULL) {
      reply_with_perror ("mkdtemp");
      free (fs_buf);
      return NULL;
    }

    if (mount_vfs_nochroot ("", NULL, fs, fs_buf, "<internal>") == -1) {
      if (rmdir (fs_buf) == -1 && errno != ENOENT)
        perror ("rmdir");
      free (fs_buf);
      return NULL;
    }
  }

  return fs_buf;
}

static int
umount (char *fs_buf, const mountable_t *fs)
{
  if (fs->type != MOUNTABLE_PATH) {
    CLEANUP_FREE char *err = NULL;

    if (command (NULL, &err, str_umount, fs_buf, NULL) == -1) {
      reply_with_error ("umount: %s", err);
      return -1;
    }

    if (rmdir (fs_buf) == -1 && errno != ENOENT) {
      reply_with_perror ("rmdir");
      return -1;
    }
  }
  free (fs_buf);
  return 0;
}

guestfs_int_btrfssubvolume_list *
do_btrfs_subvolume_list (const mountable_t *fs)
{
  char **lines;
  size_t i = 0;
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];

  /* Execute 'btrfs subvolume list <fs>', and split the output into lines */
  {
    char *fs_buf = mount (fs);

    if (!fs_buf)
      return NULL;

    ADD_ARG (argv, i, str_btrfs);
    ADD_ARG (argv, i, "subvolume");
    ADD_ARG (argv, i, "list");
    ADD_ARG (argv, i, fs_buf);
    ADD_ARG (argv, i, NULL);

    CLEANUP_FREE char *out = NULL, *errout = NULL;
    int r = commandv (&out, &errout, argv);

    if (umount (fs_buf, fs) != 0)
      return NULL;

    if (r == -1) {
      CLEANUP_FREE char *fs_desc = mountable_to_string (fs);
      if (fs_desc == NULL) {
        fprintf (stderr, "malloc: %m");
      }
      reply_with_error ("%s: %s", fs_desc ? fs_desc : "malloc", errout);
      return NULL;
    }

    lines = split_lines (out);
    if (!lines) return NULL;
  }

  /* Output is:
   *
   * ID 256 gen 30 top level 5 path test1
   * ID 257 gen 30 top level 5 path dir/test2
   * ID 258 gen 30 top level 5 path test3
   *
   * "ID <n>" is the subvolume ID.
   * "gen <n>" is the generation when the root was created or last
   * updated.
   * "top level <n>" is the top level subvolume ID.
   * "path <str>" is the subvolume path, relative to the top of the
   * filesystem.
   *
   * Note that the order that each of the above is fixed, but
   * different versions of btrfs may display different sets of data.
   * Specifically, older versions of btrfs do not display gen.
   */

  guestfs_int_btrfssubvolume_list *ret = NULL;
  pcre *re = NULL;

  size_t nr_subvolumes = count_strings (lines);

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    goto error;
  }

  ret->guestfs_int_btrfssubvolume_list_len = nr_subvolumes;
  ret->guestfs_int_btrfssubvolume_list_val =
    calloc (nr_subvolumes, sizeof (struct guestfs_int_btrfssubvolume));
  if (ret->guestfs_int_btrfssubvolume_list_val == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  const char *errptr;
  int erroffset;
  re = pcre_compile ("ID\\s+(\\d+).*\\s"
                     "top level\\s+(\\d+).*\\s"
                     "path\\s(.*)",
                     0, &errptr, &erroffset, NULL);
  if (re == NULL) {
    reply_with_error ("pcre_compile (%i): %s", erroffset, errptr);
    goto error;
  }

  for (size_t i = 0; i < nr_subvolumes; ++i) {
    /* To avoid allocations, reuse the 'line' buffer to store the
     * path.  Thus we don't need to free 'line', since it will be
     * freed by the calling (XDR) code.
     */
    char *line = lines[i];
    #define N_MATCHES 4
    int ovector[N_MATCHES * 3];

    if (pcre_exec (re, NULL, line, strlen (line), 0, 0,
                   ovector, N_MATCHES * 3) < 0)
    #undef N_MATCHES
    {
    unexpected_output:
      reply_with_error ("unexpected output from 'btrfs subvolume list' command: %s", line);
      goto error;
    }

    struct guestfs_int_btrfssubvolume *this  =
      &ret->guestfs_int_btrfssubvolume_list_val[i];

    #if __WORDSIZE == 64
      #define XSTRTOU64 xstrtoul
    #else
      #define XSTRTOU64 xstrtoull
    #endif

    if (XSTRTOU64 (line + ovector[2], NULL, 10,
                   &this->btrfssubvolume_id, NULL) != LONGINT_OK)
      goto unexpected_output;
    if (XSTRTOU64 (line + ovector[4], NULL, 10,
                   &this->btrfssubvolume_top_level_id, NULL) != LONGINT_OK)
      goto unexpected_output;

    #undef XSTRTOU64

    memmove (line, line + ovector[6], ovector[7] - ovector[6] + 1);
    this->btrfssubvolume_path = line;
  }

  free (lines);
  pcre_free (re);

  return ret;

error:
  free_stringslen (lines, nr_subvolumes);
  if (ret) free (ret->guestfs_int_btrfssubvolume_list_val);
  free (ret);
  if (re) pcre_free (re);

  return NULL;
}

int
do_btrfs_subvolume_set_default (int64_t id, const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *fs_buf = NULL;
  char buf[64];
  CLEANUP_FREE char *err = NULL;
  int r;

  snprintf (buf, sizeof buf, "%" PRIi64, id);

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "set-default");
  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    return -1;
  }

  return 0;
}

int64_t
do_btrfs_subvolume_get_default (const mountable_t *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;
  int64_t ret = -1;

  fs_buf = mount (fs);
  if (fs_buf == NULL)
    goto error;

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "get-default");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs_buf, err);
    goto error;
  }
  if (sscanf (out, "ID %" SCNi64, &ret) != 1) {
    reply_with_error ("%s: could not parse subvolume id: %s.", argv[0], out);
    ret = -1;
    goto error;
  }

error:
  if (fs_buf && umount (fs_buf, fs) != 0)
    return -1;
  return ret;
}

int
do_btrfs_filesystem_sync (const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "filesystem");
  ADD_ARG (argv, i, "sync");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_filesystem_balance (const char *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "filesystem");
  ADD_ARG (argv, i, "balance");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    return -1;
  }

  return 0;
}

/* Test if 'btrfs device add' needs the --force option (added
 * c.2013-09) in order to work.
 */
static int
test_btrfs_device_add_needs_force (void)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err, str_btrfs, "device", "add", "--help", NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", "btrfs device add --help", err);
    return -1;
  }

  return strstr (out, "--force") != NULL;
}

int
do_btrfs_device_add (char *const *devices, const char *fs)
{
  static int btrfs_device_add_needs_force = -1;
  size_t nr_devices = count_strings (devices);
  size_t MAX_ARGS = nr_devices + 8;
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  CLEANUP_FREE char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  if (nr_devices == 0)
    return 0;

  if (btrfs_device_add_needs_force == -1) {
    btrfs_device_add_needs_force = test_btrfs_device_add_needs_force ();
    if (btrfs_device_add_needs_force == -1)
      return -1;
  }

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "device");
  ADD_ARG (argv, i, "add");

  if (btrfs_device_add_needs_force)
    ADD_ARG (argv, i, "--force");

  for (j = 0; j < nr_devices; ++j)
    ADD_ARG (argv, i, devices[j]);

  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    return -1;
  }

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
  CLEANUP_FREE char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  fs_buf = sysroot_path (fs);
  if (fs_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "device");
  ADD_ARG (argv, i, "delete");

  for (j = 0; j < nr_devices; ++j)
    ADD_ARG (argv, i, devices[j]);

  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_set_seeding (const char *device, int svalue)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  const char *s_value = svalue ? "1" : "0";

  r = commandr (NULL, &err, str_btrfstune, "-S", s_value, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_btrfs_fsck (const char *device, int64_t superblock, int repair)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  size_t i = 0;
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  char super_s[64];

  ADD_ARG (argv, i, str_btrfsck);

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
    return -1;
  }

  return 0;
}

/* analyze_line: analyze one line contains key:value pair.
 * returns the next position following \n.
 */
static char *
analyze_line (char *line, char **key, char **value)
{
  char *p = line;
  char *next = NULL;
  char delimiter = ':';
  char *del_pos = NULL;

  if (!line || *line == '\0') {
    *key = NULL;
    *value = NULL;
    return NULL;
  }

  next = strchr (p, '\n');
  if (next) {
    *next = '\0';
    ++next;
  }

  /* leading spaces and tabs */
  while (*p && c_isspace (*p))
    ++p;

  assert (key);
  if (*p == delimiter)
    *key = NULL;
  else
    *key = p;

  del_pos = strchr (p, delimiter);
  if (del_pos) {
    *del_pos = '\0';

    /* leading spaces and tabs */
    do {
      ++del_pos;
    } while (*del_pos && c_isspace (*del_pos));
    assert (value);
    *value = del_pos;
  } else
    *value = NULL;

  return next;
}

char **
do_btrfs_subvolume_show (const char *subvolume)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *subvolume_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  char *p, *key = NULL, *value = NULL;
  DECLARE_STRINGSBUF (ret);
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "subvolume");
  ADD_ARG (argv, i, "show");
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    return NULL;
  }

  /* If the path is the btrfs root, `btrfs subvolume show' reports:
   *   <path> is btrfs root
   */
  if (out && strstr (out, "is btrfs root") != NULL) {
    reply_with_error ("%s is btrfs root", subvolume);
    return NULL;
  }

  /* If the path is a normal directory, `btrfs subvolume show' reports:
   *   ERROR: <path> is not a subvolume
   */
  if (err && strstr (err, "is not a subvolume")) {
    reply_with_error ("%s is not a subvolume", subvolume);
    return NULL;
  }

  /* Output is:
   *
   * /
   *         Name:                   root
   *         uuid:                   c875169e-cf4e-a04d-9959-b667dec36234
   *         Parent uuid:            -
   *         Creation time:          2014-11-13 10:13:08
   *         Object ID:              256
   *         Generation (Gen):       6579
   *         Gen at creation:        5
   *         Parent:                 5
   *         Top Level:              5
   *         Flags:                  -
   *         Snapshot(s):
   *                                 snapshots/test1
   *                                 snapshots/test2
   *                                 snapshots/test3
   *
   */
  p = analyze_line(out, &key, &value);
  if (!p) {
    reply_with_error ("truncated output: %s", out);
    return NULL;
  }

  /* The first line is the path of the subvolume. */
  if (key && !value) {
    if (add_string (&ret, "path") == -1)
      return NULL;
    if (add_string (&ret, key) == -1)
      return NULL;
  } else {
    if (add_string (&ret, key) == -1)
      return NULL;
    if (add_string (&ret, value) == -1)
      return NULL;
  }

  /* Read the lines and split into "key: value". */
  p = analyze_line(p, &key, &value);
  while (key) {
    /* snapshot is special, see the output above */
    if (STREQLEN (key, "Snapshot(s)", sizeof ("Snapshot(s)") - 1)) {
      char *ss = NULL;
      int ss_len = 0;

      if (add_string (&ret, key) == -1)
        return NULL;

      p = analyze_line(p, &key, &value);

      while (key && !value) {
          ss = realloc (ss, ss_len + strlen (key) + 1);
          if (!ss)
            return NULL;

          if (ss_len != 0)
            ss[ss_len++] = ',';

          memcpy (ss + ss_len, key, strlen (key));
          ss_len += strlen (key);
          ss[ss_len] = '\0';

          p = analyze_line(p, &key, &value);
      }

      if (ss) {
        if (add_string_nodup (&ret, ss) == -1) {
          free (ss);
          return NULL;
        }
      } else {
        if (add_string (&ret, "") == -1)
          return NULL;
      }
    } else {
      if (add_string (&ret, key ? key : "") == -1)
        return NULL;
      if (value && !STREQ(value, "-")) {
        if (add_string (&ret, value) == -1)
          return NULL;
      } else {
        if (add_string (&ret, "") == -1)
          return NULL;
      }

      p = analyze_line(p, &key, &value);
    }
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return ret.argv;
}

int
do_btrfs_quota_enable (const mountable_t *fs, int enable)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r = -1;

  fs_buf = mount (fs);
  if (fs_buf == NULL)
    goto error;

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "quota");
  if (enable)
    ADD_ARG (argv, i, "enable");
  else
    ADD_ARG (argv, i, "disable");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs_buf, err);
    goto error;
  }

error:
  if (fs_buf && umount (fs_buf, fs) != 0)
    return -1;
  return r;
}

int
do_btrfs_quota_rescan (const mountable_t *fs)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char *fs_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r = -1;

  fs_buf = mount (fs);
  if (fs_buf == NULL)
    goto error;

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "quota");
  ADD_ARG (argv, i, "rescan");
  ADD_ARG (argv, i, fs_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", fs_buf, err);
    goto error;
  }

error:
  if (fs_buf && umount (fs_buf, fs) != 0)
    return -1;
  return r;
}

int
do_btrfs_qgroup_limit (const char *subvolume, int64_t size)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *subvolume_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  char size_str[32];
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "limit");
  snprintf (size_str, sizeof size_str, "%" PRIi64, size);
  ADD_ARG (argv, i, size_str);
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_qgroup_create (const char *qgroupid, const char *subvolume)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *subvolume_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "create");
  ADD_ARG (argv, i, qgroupid);
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_qgroup_destroy (const char *qgroupid, const char *subvolume)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *subvolume_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;

  subvolume_buf = sysroot_path (subvolume);
  if (subvolume_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "destroy");
  ADD_ARG (argv, i, qgroupid);
  ADD_ARG (argv, i, subvolume_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", subvolume, err);
    return -1;
  }

  return 0;
}

guestfs_int_btrfsqgroup_list *
do_btrfs_qgroup_show (const char *path)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *path_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;
  char **lines;

  path_buf = sysroot_path (path);
  if (path_buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "show");
  ADD_ARG (argv, i, path_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return NULL;
  }

  lines = split_lines (out);
  if (!lines)
    return NULL;

  /* line 0 and 1 are:
   *
   * qgroupid rfer          excl
   * -------- ----          ----
   */
  size_t nr_qgroups = count_strings (lines) - 2;
  guestfs_int_btrfsqgroup_list *ret = NULL;
  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    goto error;
  }

  ret->guestfs_int_btrfsqgroup_list_len = nr_qgroups;
  ret->guestfs_int_btrfsqgroup_list_val =
    calloc (nr_qgroups, sizeof (struct guestfs_int_btrfsqgroup));
  if (ret->guestfs_int_btrfsqgroup_list_val == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  for (i = 0; i < nr_qgroups; ++i) {
    char *line = lines[i + 2];
    struct guestfs_int_btrfsqgroup *this  =
      &ret->guestfs_int_btrfsqgroup_list_val[i];
    uint64_t dummy1, dummy2;
    char *p;

    if (sscanf (line, "%" SCNu64 "/%" SCNu64 " %" SCNu64 " %" SCNu64,
                &dummy1, &dummy2, &this->btrfsqgroup_rfer,
                &this->btrfsqgroup_excl) != 4) {
      reply_with_perror ("sscanf");
      goto error;
    }
    p = strchr(line, ' ');
    if (!p) {
      reply_with_error ("truncated line: %s", line);
      goto error;
    }
    *p = '\0';
    this->btrfsqgroup_id = line;
  }

  free (lines);
  return ret;

error:
  free_stringslen (lines, nr_qgroups + 2);
  if (ret)
    free (ret->guestfs_int_btrfsqgroup_list_val);
  free (ret);

  return NULL;
}

int
do_btrfs_qgroup_assign (const char *src, const char *dst, const char *path)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *path_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;

  path_buf = sysroot_path (path);
  if (path_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "assign");
  ADD_ARG (argv, i, src);
  ADD_ARG (argv, i, dst);
  ADD_ARG (argv, i, path_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_qgroup_remove (const char *src, const char *dst, const char *path)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *path_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;

  path_buf = sysroot_path (path);
  if (path_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "qgroup");
  ADD_ARG (argv, i, "remove");
  ADD_ARG (argv, i, src);
  ADD_ARG (argv, i, dst);
  ADD_ARG (argv, i, path_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  return 0;
}

int
do_btrfs_scrub_start (const char *path)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  CLEANUP_FREE char *path_buf = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *out = NULL;
  int r;

  path_buf = sysroot_path (path);
  if (path_buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, str_btrfs);
  ADD_ARG (argv, i, "scrub");
  ADD_ARG (argv, i, "start");
  ADD_ARG (argv, i, path_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  return 0;
}
