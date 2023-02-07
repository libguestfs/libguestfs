/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <sys/wait.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"
#include "xstrtol.h"

#define MAX_ARGS 128

/* https://bugzilla.redhat.com/show_bug.cgi?id=978302#c1 */
int
fstype_is_extfs (const char *fstype)
{
  return STREQ (fstype, "ext2") || STREQ (fstype, "ext3")
    || STREQ (fstype, "ext4");
}

char **
do_tune2fs_l (const char *device)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;
  char *p, *pend, *colon;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);

  r = command (&out, &err, "tune2fs", "-l", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  p = out;

  /* Discard the first line if it contains "tune2fs ...". */
  if (STRPREFIX (p, "tune2fs ") || STRPREFIX (p, "tune4fs ")) {
    p = strchr (p, '\n');
    if (p) p++;
    else {
      reply_with_error ("truncated output");
      return NULL;
    }
  }

  /* Read the lines and split into "key: value". */
  while (*p) {
    pend = strchrnul (p, '\n');
    if (*pend == '\n') {
      *pend = '\0';
      pend++;
    }

    if (!*p) continue;

    colon = strchr (p, ':');
    if (colon) {
      *colon = '\0';

      do { colon++; } while (*colon && c_isspace (*colon));

      if (add_string (&ret, p) == -1) {
        return NULL;
      }
      if (STREQ (colon, "<none>") ||
          STREQ (colon, "<not available>") ||
          STREQ (colon, "(none)")) {
        if (add_string (&ret, "") == -1) {
          return NULL;
        }
      } else {
        if (add_string (&ret, colon) == -1) {
          return NULL;
        }
      }
    }
    else {
      if (add_string (&ret, p) == -1) {
        return NULL;
      }
      if (add_string (&ret, "") == -1) {
        return NULL;
      }
    }

    p = pend;
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret);
}

int
do_set_e2label (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2/3/4 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  r = command (NULL, &err, "e2label", device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

char *
do_get_e2label (const char *device)
{
  const mountable_t mountable = {
    .type = MOUNTABLE_DEVICE,
    .device = /* not really ... */ (char *) device,
    .volume = NULL,
  };
  return do_vfs_label (&mountable);
}

int
do_set_e2uuid (const char *device, const char *uuid)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, "tune2fs", "-U", uuid, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
ext_set_uuid_random (const char *device)
{
  return do_set_e2uuid (device, "random");
}

char *
do_get_e2uuid (const char *device)
{
  const mountable_t mountable = {
    .type = MOUNTABLE_DEVICE,
    .device = /* not really ... */ (char *) device,
    .volume = NULL,
  };
  return do_vfs_uuid (&mountable);
}

/* If the filesystem is not mounted, run e2fsck -f on it unconditionally. */
static int
if_not_mounted_run_e2fsck (const char *device)
{
  int r = 0, mounted;

  mounted = is_device_mounted (device);
  if (mounted == -1)
    return -1;

  if (!mounted) {
    optargs_bitmask = GUESTFS_E2FSCK_FORCEALL_BITMASK;
    r = do_e2fsck (device, 0, 1);
  }

  return r;
}

int
do_resize2fs (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (if_not_mounted_run_e2fsck (device) == -1)
    return -1;

  r = command (NULL, &err, "resize2fs", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_resize2fs_size (const char *device, int64_t size)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  /* resize2fs itself may impose additional limits.  Since we are
   * going to use the 'K' suffix however we can only work with whole
   * kilobytes.
   */
  if (size & 1023) {
    reply_with_error ("%" PRIi64 ": size must be a round number of kilobytes",
                      size);
    return -1;
  }
  size /= 1024;

  if (if_not_mounted_run_e2fsck (device) == -1)
    return -1;

  char buf[32];
  snprintf (buf, sizeof buf, "%" PRIi64 "K", size);

  r = command (NULL, &err, "resize2fs", device, buf, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_resize2fs_M (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (if_not_mounted_run_e2fsck (device) == -1)
    return -1;

  r = command (NULL, &err, "resize2fs", "-M", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static long
get_block_size (const char *device)
{
  CLEANUP_FREE_STRING_LIST char **params = NULL;
  const char *block_pattern = "Block size";
  size_t i;
  long block_size;

  params = do_tune2fs_l (device);
  if (params == NULL)
    return -1;

  for (i = 0; params[i] != NULL; i += 2) {
    if (STREQ (params[i], block_pattern)) {
      if (xstrtol (params[i + 1], NULL, 10, &block_size, NULL) != LONGINT_OK) {
        reply_with_error ("cannot parse block size");
        return -1;
      }
      return block_size;
    }
  }

  reply_with_error ("missing 'Block size' in tune2fs_l output");
  return -1;
}

int64_t
ext_minimum_size (const char *device)
{
  CLEANUP_FREE char *err = NULL, *out = NULL;
  CLEANUP_FREE_STRING_LIST char **lines = NULL;
  int r;
  size_t i;
  int64_t ret;
  long block_size;
  const char *pattern = "Estimated minimum size of the filesystem: ";

  r = command (&out, &err, "resize2fs", "-P", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  lines = split_lines (out);
  if (lines == NULL)
    return -1;

#if __WORDSIZE == 64
#define XSTRTOD64 xstrtol
#else
#define XSTRTOD64 xstrtoll
#endif

  for (i = 0; lines[i] != NULL; ++i) {
    if (STRPREFIX (lines[i], pattern)) {
      if (XSTRTOD64 (lines[i] + strlen (pattern),
                     NULL, 10, &ret, NULL) != LONGINT_OK) {
        reply_with_error ("cannot parse minimum size");
        return -1;
      }
      if ((block_size = get_block_size (device)) == -1)
        return -1;
      if (verbose) {
        fprintf (stderr, "Minimum size in blocks: %" SCNd64 \
                         "\nBlock count: %ld\n", ret, block_size);
      }
      if (INT64_MAX / block_size < ret) {
        reply_with_error ("filesystem size too big: overflow");
        return -1;
      }
      return ret * block_size;
    }
  }

#undef XSTRTOD64

  reply_with_error ("minimum size not found. Check output format:\n%s", out);
  return -1;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_e2fsck (const char *device,
           int correct,
           int forceall)
{
  const char *argv[MAX_ARGS];
  CLEANUP_FREE char *err = NULL;
  size_t i = 0;
  int r;

  /* Default if not selected. */
  if (!(optargs_bitmask & GUESTFS_E2FSCK_CORRECT_BITMASK))
    correct = 0;
  if (!(optargs_bitmask & GUESTFS_E2FSCK_FORCEALL_BITMASK))
    forceall = 0;

  if (correct && forceall) {
    reply_with_error ("only one of the options 'correct', 'forceall' may be specified");
    return -1;
  }

  ADD_ARG (argv, i, "e2fsck");
  ADD_ARG (argv, i, "-f");

  if (correct)
    ADD_ARG (argv, i, "-p");

  if (forceall)
    ADD_ARG (argv, i, "-y");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandrvf (NULL, &err,
                  COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                  argv);
  /* 0 = no errors, 1 = errors corrected.
   *
   * >= 4 means uncorrected or other errors.
   *
   * 2, 3 means errors were corrected and we require a reboot.  This is
   * a difficult corner case.
   */
  if (r == -1 || r >= 2) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_e2fsck_f (const char *device)
{
  optargs_bitmask = GUESTFS_E2FSCK_CORRECT_BITMASK;
  return do_e2fsck (device, 1, 0);
}

int
do_mke2journal (int blocksize, const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-O", "journal_dev", "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_mke2journal_L (int blocksize, const char *label, const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2/3/4 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-O", "journal_dev", "-b", blocksize_s,
               "-L", label,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_mke2journal_U (int blocksize, const char *uuid, const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-O", "journal_dev", "-b", blocksize_s,
               "-U", uuid,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_mke2fs_J (const char *fstype, int blocksize, const char *device,
             const char *journal)
{
  CLEANUP_FREE char *err = NULL;
  char blocksize_s[32];
  CLEANUP_FREE char *jdev = NULL;
  int r;

  if (!fstype_is_extfs (fstype)) {
    reply_with_error ("%s: not a valid extended filesystem type", fstype);
    return -1;
  }

  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  if (asprintf (&jdev, "device=%s", journal) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_mke2fs_JL (const char *fstype, int blocksize, const char *device,
              const char *label)
{
  CLEANUP_FREE char *err = NULL;
  char blocksize_s[32];
  CLEANUP_FREE char *jdev = NULL;
  int r;

  if (!fstype_is_extfs (fstype)) {
    reply_with_error ("%s: not a valid extended filesystem type", fstype);
    return -1;
  }

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2/3/4 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  if (asprintf (&jdev, "device=LABEL=%s", label) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_mke2fs_JU (const char *fstype, int blocksize, const char *device,
              const char *uuid)
{
  CLEANUP_FREE char *err = NULL;
  char blocksize_s[32];
  CLEANUP_FREE char *jdev = NULL;
  int r;

  if (!fstype_is_extfs (fstype)) {
    reply_with_error ("%s: not a valid extended filesystem type", fstype);
    return -1;
  }

  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  if (asprintf (&jdev, "device=UUID=%s", uuid) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  wipe_device_before_mkfs (device);

  r = command (NULL, &err,
               "mke2fs", "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_tune2fs (const char *device, /* only required parameter */
            int force,
            int maxmountcount,
            int mountcount,
            const char *errorbehavior,
            int64_t group,
            int intervalbetweenchecks,
            int reservedblockspercentage,
            const char *lastmounteddirectory,
            int64_t reservedblockscount,
            int64_t user)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;
  char maxmountcount_s[64];
  char mountcount_s[64];
  char group_s[64];
  char intervalbetweenchecks_s[64];
  char reservedblockspercentage_s[64];
  char reservedblockscount_s[64];
  char user_s[64];

  ADD_ARG (argv, i, "tune2fs");

  if (optargs_bitmask & GUESTFS_TUNE2FS_FORCE_BITMASK) {
    if (force)
      ADD_ARG (argv, i, "-f");
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_MAXMOUNTCOUNT_BITMASK) {
    if (maxmountcount < 0) {
      reply_with_error ("maxmountcount cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-c");
    snprintf (maxmountcount_s, sizeof maxmountcount_s, "%d", maxmountcount);
    ADD_ARG (argv, i, maxmountcount_s);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_MOUNTCOUNT_BITMASK) {
    if (mountcount < 0) {
      reply_with_error ("mountcount cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-C");
    snprintf (mountcount_s, sizeof mountcount_s, "%d", mountcount);
    ADD_ARG (argv, i, mountcount_s);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_ERRORBEHAVIOR_BITMASK) {
    if (STRNEQ (errorbehavior, "continue") &&
        STRNEQ (errorbehavior, "remount-ro") &&
        STRNEQ (errorbehavior, "panic")) {
      reply_with_error ("invalid errorbehavior parameter: %s", errorbehavior);
      return -1;
    }
    ADD_ARG (argv, i, "-e");
    ADD_ARG (argv, i, errorbehavior);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_GROUP_BITMASK) {
    if (group < 0) {
      reply_with_error ("group cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-g");
    snprintf (group_s, sizeof group_s, "%" PRIi64, group);
    ADD_ARG (argv, i, group_s);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_INTERVALBETWEENCHECKS_BITMASK) {
    if (intervalbetweenchecks < 0) {
      reply_with_error ("intervalbetweenchecks cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-i");
    if (intervalbetweenchecks > 0) {
      /* -i <NN>s is not documented in the man page, but has been
       * supported in tune2fs for several years.
       */
      snprintf (intervalbetweenchecks_s, sizeof intervalbetweenchecks_s,
                "%ds", intervalbetweenchecks);
      ADD_ARG (argv, i, intervalbetweenchecks_s);
    }
    else
      ADD_ARG (argv, i, "0");
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_RESERVEDBLOCKSPERCENTAGE_BITMASK) {
    if (reservedblockspercentage < 0) {
      reply_with_error ("reservedblockspercentage cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-m");
    snprintf (reservedblockspercentage_s, sizeof reservedblockspercentage_s,
              "%d", reservedblockspercentage);
    ADD_ARG (argv, i, reservedblockspercentage_s);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_LASTMOUNTEDDIRECTORY_BITMASK) {
    ADD_ARG (argv, i, "-M");
    ADD_ARG (argv, i, lastmounteddirectory);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_RESERVEDBLOCKSCOUNT_BITMASK) {
    if (reservedblockscount < 0) {
      reply_with_error ("reservedblockscount cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-r");
    snprintf (reservedblockscount_s, sizeof reservedblockscount_s,
              "%" PRIi64, reservedblockscount);
    ADD_ARG (argv, i, reservedblockscount_s);
  }

  if (optargs_bitmask & GUESTFS_TUNE2FS_USER_BITMASK) {
    if (user < 0) {
      reply_with_error ("user cannot be negative");
      return -1;
    }
    ADD_ARG (argv, i, "-u");
    snprintf (user_s, sizeof user_s, "%" PRIi64, user);
    ADD_ARG (argv, i, user_s);
  }

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

static int
compare_chars (const void *vc1, const void *vc2)
{
  char c1 = * (char *) vc1;
  char c2 = * (char *) vc2;
  return c1 - c2;
}

char *
do_get_e2attrs (const char *filename)
{
  int r;
  CLEANUP_FREE char *buf = NULL;
  char *out;
  CLEANUP_FREE char *err = NULL;
  size_t i, j;

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "lsattr", "-d", "--", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "lsattr", filename, err);
    free (out);
    return NULL;
  }

  /* Output looks like:
   * -------------e- filename
   * Remove the dashes and return everything up to the space.
   */
  for (i = j = 0; out[j] != ' '; j++) {
    if (out[j] != '-')
      out[i++] = out[j];
  }

  out[i] = '\0';

  /* Sort the output, mainly to make testing simpler. */
  qsort (out, i, sizeof (char), compare_chars);

  return out;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_set_e2attrs (const char *filename, const char *attrs, int clear)
{
  int r;
  CLEANUP_FREE char *buf = NULL;
  CLEANUP_FREE char *err = NULL;
  size_t i, j;
  int lowers[26], uppers[26];
  char attr_arg[26*2+1+1]; /* '+'/'-' + attrs + trailing '\0' */

  if (!(optargs_bitmask & GUESTFS_SET_E2ATTRS_CLEAR_BITMASK))
    attr_arg[0] = '+';
  else if (!clear)
    attr_arg[0] = '+';
  else
    attr_arg[0] = '-';
  j = 1;

  /* You can't write "chattr - file", so we have to just return if
   * the string is empty.
   */
  if (STREQ (attrs, ""))
    return 0;

  /* Valid attrs are all lower or upper case ASCII letters.  Check
   * this and that there are no duplicates.
   */
  memset (lowers, 0, sizeof lowers);
  memset (uppers, 0, sizeof uppers);
  for (; *attrs; attrs++) {
    /* These are reserved by the chattr program for command line flags. */
    if (*attrs == 'R' || *attrs == 'V' || *attrs == 'f' || *attrs == 'v') {
      reply_with_error ("bad file attribute '%c'", *attrs);
      return -1;
    }
    else if (*attrs >= 'a' && *attrs <= 'z') {
      i = *attrs - 'a';
      if (lowers[i] > 0)
        goto error_duplicate;
      lowers[i]++;
      attr_arg[j++] = *attrs;
    }
    else if (*attrs >= 'A' && *attrs <= 'Z') {
      i = *attrs - 'A';
      if (uppers[i] > 0) {
      error_duplicate:
        reply_with_error ("duplicate file attribute '%c'", *attrs);
        return -1;
      }
      uppers[i]++;
      attr_arg[j++] = *attrs;
    }
    else {
      reply_with_error ("unknown file attribute '%c'", *attrs);
      return -1;
    }
  }

  attr_arg[j] = '\0';

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "chattr", attr_arg, "--", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "chattr", filename, err);
    return -1;
  }

  return 0;
}

int64_t
do_get_e2generation (const char *filename)
{
  int r;
  CLEANUP_FREE char *buf = NULL, *out = NULL, *err = NULL;
  int64_t ret;

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (&out, &err, "lsattr", "-dv", "--", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "lsattr", filename, err);
    return -1;
  }

  if (sscanf (out, "%" SCNi64, &ret) != 1) {
    reply_with_error ("cannot parse output from '%s' command: %s",
                      "lsattr", out);
    return -1;
  }
  if (ret < 0) {
    reply_with_error ("unexpected negative number from '%s' command: %s",
                      "lsattr", out);
    return -1;
  }

  return ret;
}

int
do_set_e2generation (const char *filename, int64_t generation)
{
  int r;
  CLEANUP_FREE char *buf = NULL, *err = NULL;
  char generation_str[64];

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  snprintf (generation_str, sizeof generation_str,
            "%" PRIu64, (uint64_t) generation);

  r = command (NULL, &err, "chattr", "-v", generation_str, "--", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "chattr", filename, err);
    return -1;
  }

  return 0;
}

int
do_mke2fs (const char *device,               /* 0 */
           int64_t blockscount,
           int64_t blocksize,
           int64_t fragsize,
           int64_t blockspergroup,
           int64_t numberofgroups,           /* 5 */
           int64_t bytesperinode,
           int64_t inodesize,
           int64_t journalsize,
           int64_t numberofinodes,
           int64_t stridesize,               /* 10 */
           int64_t stripewidth,
           int64_t maxonlineresize,
           int reservedblockspercentage,
           int mmpupdateinterval,
           const char *journaldevice,        /* 15 */
           const char *label,
           const char *lastmounteddir,
           const char *creatoros,
           const char *fstype,
           const char *usagetype,            /* 20 */
           const char *uuid,
           int forcecreate,
           int writesbandgrouponly,
           int lazyitableinit,
           int lazyjournalinit,              /* 25 */
           int testfs,
           int discard,
           int quotatype,
           int extent,
           int filetype,                     /* 30 */
           int flexbg,
           int hasjournal,
           int journaldev,
           int largefile,
           int quota,                        /* 35 */
           int resizeinode,
           int sparsesuper,
           int uninitbg)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  const char *argv[MAX_ARGS];
  char blockscount_s[64];
  char blocksize_s[64];
  char fragsize_s[64];
  char blockspergroup_s[64];
  char numberofgroups_s[64];
  char bytesperinode_s[64];
  char inodesize_s[64];
  char journalsize_s[64];
  CLEANUP_FREE char *journaldevice_translated = NULL;
  CLEANUP_FREE char *journaldevice_s = NULL;
  char reservedblockspercentage_s[64];
  char numberofinodes_s[64];
  char mmpupdateinterval_s[84];
  char stridesize_s[74];
  char stripewidth_s[84];
  char maxonlineresize_s[74];
  size_t i = 0;

  ADD_ARG (argv, i, "mke2fs");

  if (optargs_bitmask & GUESTFS_MKE2FS_BLOCKSIZE_BITMASK) {
    if (blocksize < 0) {
      reply_with_error ("blocksize must be >= 0");
      return -1;
    }
    snprintf (blocksize_s, sizeof blocksize_s, "%" PRIi64, blocksize);
    ADD_ARG (argv, i, "-b");
    ADD_ARG (argv, i, blocksize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_FRAGSIZE_BITMASK) {
    if (fragsize < 0) {
      reply_with_error ("fragsize must be >= 0");
      return -1;
    }
    snprintf (fragsize_s, sizeof fragsize_s, "%" PRIi64, fragsize);
    ADD_ARG (argv, i, "-f");
    ADD_ARG (argv, i, fragsize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_FORCECREATE_BITMASK) {
    if (forcecreate)
      ADD_ARG (argv, i, "-F");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_BLOCKSPERGROUP_BITMASK) {
    if (blockspergroup < 0) {
      reply_with_error ("blockspergroup must be >= 0");
      return -1;
    }
    snprintf (blockspergroup_s, sizeof blockspergroup_s,
              "%" PRIi64, blockspergroup);
    ADD_ARG (argv, i, "-g");
    ADD_ARG (argv, i, blockspergroup_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_NUMBEROFGROUPS_BITMASK) {
    if (numberofgroups < 0) {
      reply_with_error ("numberofgroups must be >= 0");
      return -1;
    }
    snprintf (numberofgroups_s, sizeof numberofgroups_s,
              "%" PRIi64, numberofgroups);
    ADD_ARG (argv, i, "-G");
    ADD_ARG (argv, i, numberofgroups_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_BYTESPERINODE_BITMASK) {
    if (bytesperinode < 0) {
      reply_with_error ("bytesperinode must be >= 0");
      return -1;
    }
    snprintf (bytesperinode_s, sizeof bytesperinode_s, "%" PRIi64, bytesperinode);
    ADD_ARG (argv, i, "-i");
    ADD_ARG (argv, i, bytesperinode_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_INODESIZE_BITMASK) {
    if (inodesize < 0) {
      reply_with_error ("inodesize must be >= 0");
      return -1;
    }
    snprintf (inodesize_s, sizeof inodesize_s, "%" PRIi64, inodesize);
    ADD_ARG (argv, i, "-I");
    ADD_ARG (argv, i, inodesize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_JOURNALSIZE_BITMASK) {
    if (journalsize < 0) {
      reply_with_error ("journalsize must be >= 0");
      return -1;
    }
    snprintf (journalsize_s, sizeof journalsize_s,
              "size=" "%" PRIi64, journalsize);
    ADD_ARG (argv, i, "-J");
    ADD_ARG (argv, i, journalsize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_JOURNALDEVICE_BITMASK) {
    if (journaldevice) {
      /* OString doesn't do device name translation (RHBZ#876579).  We
       * have to do it manually here, but note that LABEL=.. and
       * UUID=.. are valid strings which do not require translation.
       */
      if (is_device_parameter (journaldevice)) {
        if (is_root_device (journaldevice)) {
          reply_with_error ("%s: device not found", journaldevice);
          return -1;
        }
        journaldevice_translated = device_name_translation (journaldevice);
        if (journaldevice_translated == NULL) {
          reply_with_perror ("%s", journaldevice);
          return -1;
        }

        journaldevice_s = malloc (strlen (journaldevice_translated) + 8);
        if (!journaldevice_s) {
          reply_with_perror ("malloc");
          return -1;
        }

        sprintf (journaldevice_s, "device=%s", journaldevice_translated);
      }
      else /* XXX check only UUID= or LABEL= should be used here */ {
        journaldevice_s = malloc (strlen (journaldevice) + 8);
        if (!journaldevice_s) {
          reply_with_perror ("malloc");
          return -1;
        }

        sprintf (journaldevice_s, "device=%s", journaldevice);
      }

      ADD_ARG (argv, i, "-J");
      ADD_ARG (argv, i, journaldevice_s);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_LABEL_BITMASK) {
    if (label) {
      ADD_ARG (argv, i, "-L");
      ADD_ARG (argv, i, label);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_RESERVEDBLOCKSPERCENTAGE_BITMASK) {
    if (reservedblockspercentage < 0) {
      reply_with_error ("reservedblockspercentage must be >= 0");
      return -1;
    }
    snprintf (reservedblockspercentage_s, sizeof reservedblockspercentage_s,
              "%" PRIi32, reservedblockspercentage);
    ADD_ARG (argv, i, "-m");
    ADD_ARG (argv, i, reservedblockspercentage_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_LASTMOUNTEDDIR_BITMASK) {
    if (lastmounteddir) {
      ADD_ARG (argv, i, "-M");
      ADD_ARG (argv, i, lastmounteddir);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_NUMBEROFINODES_BITMASK) {
    if (numberofinodes < 0) {
      reply_with_error ("numberofinodes must be >= 0");
      return -1;
    }
    snprintf (numberofinodes_s, sizeof numberofinodes_s,
              "%" PRIi64, numberofinodes);
    ADD_ARG (argv, i, "-N");
    ADD_ARG (argv, i, numberofinodes_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_CREATOROS_BITMASK) {
    if (creatoros) {
      ADD_ARG (argv, i, "-o");
      ADD_ARG (argv, i, creatoros);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_WRITESBANDGROUPONLY_BITMASK) {
    if (writesbandgrouponly)
      ADD_ARG (argv, i, "-S");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_FSTYPE_BITMASK) {
    if (fstype) {
      if (!fstype_is_extfs (fstype)) {
        reply_with_error ("%s: not a valid extended filesystem type", fstype);
        return -1;
      }

      ADD_ARG (argv, i, "-t");
      ADD_ARG (argv, i, fstype);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_USAGETYPE_BITMASK) {
    if (usagetype) {
      ADD_ARG (argv, i, "-T");
      ADD_ARG (argv, i, usagetype);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_UUID_BITMASK) {
    if (uuid) {
      ADD_ARG (argv, i, "-U");
      ADD_ARG (argv, i, uuid);
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_MMPUPDATEINTERVAL_BITMASK) {
    if (mmpupdateinterval < 0) {
      reply_with_error ("mmpupdateinterval must be >= 0");
      return -1;
    }
    snprintf (mmpupdateinterval_s, sizeof mmpupdateinterval_s,
              "mmp_update_interval=" "%" PRIi32, mmpupdateinterval);
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, mmpupdateinterval_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_STRIDESIZE_BITMASK) {
    if (stridesize < 0) {
      reply_with_error ("stridesize must be >= 0");
      return -1;
    }
    snprintf (stridesize_s, sizeof stridesize_s,
              "stride=" "%" PRIi64, stridesize);
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, stridesize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_STRIPEWIDTH_BITMASK) {
    if (stripewidth< 0) {
      reply_with_error ("stripewidth must be >= 0");
      return -1;
    }
    snprintf (stripewidth_s, sizeof stripewidth_s,
              "stripe_width=" "%" PRIi64, stripewidth);
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, stripewidth_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_MAXONLINERESIZE_BITMASK) {
    if (maxonlineresize < 0) {
      reply_with_error ("maxonlineresize must be >= 0");
      return -1;
    }
    snprintf (maxonlineresize_s, sizeof maxonlineresize_s,
              "resize=" "%" PRIi64, maxonlineresize);
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, maxonlineresize_s);
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_LAZYITABLEINIT_BITMASK) {
    ADD_ARG (argv, i, "-E");
    if (lazyitableinit)
      ADD_ARG (argv, i, "lazy_itable_init=1");
    else
      ADD_ARG (argv, i, "lazy_itable_init=0");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_LAZYJOURNALINIT_BITMASK) {
    ADD_ARG (argv, i, "-E");
    if (lazyjournalinit)
      ADD_ARG (argv, i, "lazy_journal_init=1");
    else
      ADD_ARG (argv, i, "lazy_journal_init=0");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_TESTFS_BITMASK) {
    if (testfs) {
      ADD_ARG (argv, i, "-E");
      ADD_ARG (argv, i, "test_fs");
    }
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_DISCARD_BITMASK) {
    ADD_ARG (argv, i, "-E");
    if (discard)
      ADD_ARG (argv, i, "discard");
    else
      ADD_ARG (argv, i, "nodiscard");
  }

  if (optargs_bitmask & GUESTFS_MKE2FS_EXTENT_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (extent)
      ADD_ARG (argv, i, "extent");
    else
      ADD_ARG (argv, i, "^extent");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_FILETYPE_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (filetype)
      ADD_ARG (argv, i, "filetype");
    else
      ADD_ARG (argv, i, "^filetype");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_FLEXBG_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (flexbg)
      ADD_ARG (argv, i, "flexbg");
    else
      ADD_ARG (argv, i, "^flexbg");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_HASJOURNAL_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (hasjournal)
      ADD_ARG (argv, i, "has_journal");
    else
      ADD_ARG (argv, i, "^has_journal");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_JOURNALDEV_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (journaldev)
      ADD_ARG (argv, i, "journal_dev");
    else
      ADD_ARG (argv, i, "^journal_dev");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_LARGEFILE_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (largefile)
      ADD_ARG (argv, i, "large_file");
    else
      ADD_ARG (argv, i, "^large_file");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_QUOTA_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (quota)
      ADD_ARG (argv, i, "quota");
    else
      ADD_ARG (argv, i, "^quota");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_RESIZEINODE_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (resizeinode)
      ADD_ARG (argv, i, "resize_inode");
    else
      ADD_ARG (argv, i, "^resize_inode");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_SPARSESUPER_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (sparsesuper)
      ADD_ARG (argv, i, "sparse_super");
    else
      ADD_ARG (argv, i, "^sparse_super");
  }
  if (optargs_bitmask & GUESTFS_MKE2FS_UNINITBG_BITMASK) {
    ADD_ARG (argv, i, "-O");
    if (uninitbg)
      ADD_ARG (argv, i, "uninit_bg");
    else
      ADD_ARG (argv, i, "^uninit_bg");
  }

  ADD_ARG (argv, i, device);

  if (optargs_bitmask & GUESTFS_MKE2FS_BLOCKSCOUNT_BITMASK) {
    if (blockscount < 0) {
      reply_with_error ("blockscount must be >= 0");
      return -1;
    }
    snprintf (blockscount_s, sizeof blockscount_s, "%" PRIi64, blockscount);
    ADD_ARG (argv, i, blockscount_s);
  }

  ADD_ARG (argv, i, NULL);

  wipe_device_before_mkfs (device);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_mklost_and_found (const char *mountpoint)
{
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  FILE *fp;
  int r;

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "cd ");
  sysroot_shell_quote (mountpoint, fp);
  fprintf (fp, " && mklost+found");
  if (fclose (fp) == EOF)
    goto cmd_error;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  r = system (cmd);
  if (r == -1) {
    reply_with_perror ("system");
    return -1;
  }
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    reply_with_error ("%s: command failed", cmd);
    return -1;
  }

  return 0;
}
