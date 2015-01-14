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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "xstrtol.h"

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
do_btrfs_subvolume_snapshot (const char *source, const char *dest)
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
do_btrfs_subvolume_create (const char *dest)
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
  ADD_ARG (argv, i, dest_buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", dest, err);
    return -1;
  }

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
    CLEANUP_FREE char *fs_buf = NULL;

    if (fs->type == MOUNTABLE_PATH) {
      fs_buf = sysroot_path (fs->device);
      if (fs_buf == NULL) {
        reply_with_perror ("malloc");

      cmderror:
        if (fs->type != MOUNTABLE_PATH && fs_buf) {
          CLEANUP_FREE char *err = NULL;
          if (command (NULL, &err, str_umount, fs_buf, NULL) == -1)
            fprintf (stderr, "%s\n", err);

          if (rmdir (fs_buf) == -1 && errno != ENOENT)
            fprintf (stderr, "rmdir: %m\n");
        }
        return NULL;
      }
    }

    else {
      fs_buf = strdup ("/tmp/btrfs.XXXXXX");
      if (fs_buf == NULL) {
        reply_with_perror ("strdup");
        goto cmderror;
      }

      if (mkdtemp (fs_buf) == NULL) {
        reply_with_perror ("mkdtemp");
        goto cmderror;
      }

      if (mount_vfs_nochroot ("", NULL, fs, fs_buf, "<internal>") == -1) {
        goto cmderror;
      }
    }

    ADD_ARG (argv, i, str_btrfs);
    ADD_ARG (argv, i, "subvolume");
    ADD_ARG (argv, i, "list");
    ADD_ARG (argv, i, fs_buf);
    ADD_ARG (argv, i, NULL);

    CLEANUP_FREE char *out = NULL, *errout = NULL;
    int r = commandv (&out, &errout, argv);

    if (fs->type != MOUNTABLE_PATH) {
      CLEANUP_FREE char *err = NULL;
      if (command (NULL, &err, str_umount, fs_buf, NULL) == -1) {
        reply_with_error ("%s", err ? err : "malloc");
        goto cmderror;
      }

      if (rmdir (fs_buf) == -1 && errno != ENOENT) {
        reply_with_error ("rmdir: %m\n");
        goto cmderror;
      }
    }

    if (r == -1) {
      CLEANUP_FREE char *fs_desc = mountable_to_string (fs);
      if (fs_desc == NULL) {
        fprintf (stderr, "malloc: %m");
      }
      reply_with_error ("%s: %s", fs_desc ? fs_desc : "malloc", errout);
      goto cmderror;
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
