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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"

#define MAX_ARGS 64

/* Choose which tools like mke2fs to use.  For RHEL 5 (only) there
 * is a special set of tools which support ext2/3/4.  eg. On RHEL 5,
 * mke2fs only supports ext2/3, but mke4fs supports ext2/3/4.
 *
 * We specify e4fsprogs in the package list to ensure it is loaded
 * if it exists.
 */
int
e2prog (char *name)
{
  char *p = strstr (name, "e2");
  if (!p) return 0;
  p++;

  *p = '4';
  if (prog_exists (name))
    return 0;

  *p = '2';
  if (prog_exists (name))
    return 0;

  reply_with_error ("cannot find required program %s", name);
  return -1;
}

char **
do_tune2fs_l (const char *device)
{
  int r;
  char *out, *err;
  char *p, *pend, *colon;
  DECLARE_STRINGSBUF (ret);

  char prog[] = "tune2fs";
  if (e2prog (prog) == -1)
    return NULL;

  r = command (&out, &err, prog, "-l", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    free (out);
    return NULL;
  }
  free (err);

  p = out;

  /* Discard the first line if it contains "tune2fs ...". */
  if (STRPREFIX (p, "tune2fs ") || STRPREFIX (p, "tune4fs ")) {
    p = strchr (p, '\n');
    if (p) p++;
    else {
      reply_with_error ("truncated output");
      free (out);
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
        free (out);
        return NULL;
      }
      if (STREQ (colon, "<none>") ||
          STREQ (colon, "<not available>") ||
          STREQ (colon, "(none)")) {
        if (add_string (&ret, "") == -1) {
          free (out);
          return NULL;
        }
      } else {
        if (add_string (&ret, colon) == -1) {
          free (out);
          return NULL;
        }
      }
    }
    else {
      if (add_string (&ret, p) == -1) {
        free (out);
        return NULL;
      }
      if (add_string (&ret, "") == -1) {
        free (out);
        return NULL;
      }
    }

    p = pend;
  }

  free (out);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return ret.argv;
}

int
do_set_e2label (const char *device, const char *label)
{
  return do_set_label (device, label);
}

char *
do_get_e2label (const char *device)
{
  return do_vfs_label (device);
}

int
do_set_e2uuid (const char *device, const char *uuid)
{
  int r;
  char *err;

  char prog[] = "tune2fs";
  if (e2prog (prog) == -1)
    return -1;

  r = command (NULL, &err, prog, "-U", uuid, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

char *
do_get_e2uuid (const char *device)
{
  return do_vfs_uuid (device);
}

/* If the filesystem is not mounted, run e2fsck -f on it unconditionally. */
static int
if_not_mounted_run_e2fsck (const char *device)
{
  char *err;
  int r, mounted;
  char prog[] = "e2fsck";

  if (e2prog (prog) == -1)
    return -1;

  mounted = is_device_mounted (device);
  if (mounted == -1)
    return -1;

  if (!mounted) {
    r = command (NULL, &err, prog, "-fy", device, NULL);
    if (r == -1) {
      reply_with_error ("%s", err);
      free (err);
      return -1;
    }
    free (err);
  }

  return 0;
}

int
do_resize2fs (const char *device)
{
  char *err;
  int r;

  char prog[] = "resize2fs";
  if (e2prog (prog) == -1)
    return -1;

  if (if_not_mounted_run_e2fsck (device) == -1)
    return -1;

  r = command (NULL, &err, prog, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_resize2fs_size (const char *device, int64_t size)
{
  char *err;
  int r;

  char prog[] = "resize2fs";
  if (e2prog (prog) == -1)
    return -1;

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

  r = command (NULL, &err, prog, device, buf, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_resize2fs_M (const char *device)
{
  char *err;
  int r;

  char prog[] = "resize2fs";
  if (e2prog (prog) == -1)
    return -1;

  if (if_not_mounted_run_e2fsck (device) == -1)
    return -1;

  r = command (NULL, &err, prog, "-M", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_e2fsck (const char *device,
           int correct,
           int forceall)
{
  const char *argv[MAX_ARGS];
  char *err;
  size_t i = 0;
  int r;
  char prog[] = "e2fsck";

  if (e2prog (prog) == -1)
    return -1;

  /* Default if not selected. */
  if (!(optargs_bitmask & GUESTFS_E2FSCK_CORRECT_BITMASK))
    correct = 0;
  if (!(optargs_bitmask & GUESTFS_E2FSCK_FORCEALL_BITMASK))
    forceall = 0;

  if (correct && forceall) {
    reply_with_error ("only one of the options 'correct', 'forceall' may be specified");
    return -1;
  }

  ADD_ARG (argv, i, prog);
  ADD_ARG (argv, i, "-f");

  if (correct)
    ADD_ARG (argv, i, "-p");

  if (forceall)
    ADD_ARG (argv, i, "-y");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  /* 0 = no errors, 1 = errors corrected.
   *
   * >= 4 means uncorrected or other errors.
   *
   * 2, 3 means errors were corrected and we require a reboot.  This is
   * a difficult corner case.
   */
  if (r == -1 || r >= 2) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
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
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  r = command (NULL, &err,
               prog, "-F", "-O", "journal_dev", "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mke2journal_L (int blocksize, const char *label, const char *device)
{
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  r = command (NULL, &err,
               prog, "-F", "-O", "journal_dev", "-b", blocksize_s,
               "-L", label,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mke2journal_U (int blocksize, const char *uuid, const char *device)
{
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  r = command (NULL, &err,
               prog, "-F", "-O", "journal_dev", "-b", blocksize_s,
               "-U", uuid,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mke2fs_J (const char *fstype, int blocksize, const char *device,
             const char *journal)
{
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  size_t len = strlen (journal);
  char jdev[len+32];
  snprintf (jdev, len+32, "device=%s", journal);

  r = command (NULL, &err,
               prog, "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mke2fs_JL (const char *fstype, int blocksize, const char *device,
              const char *label)
{
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  size_t len = strlen (label);
  char jdev[len+32];
  snprintf (jdev, len+32, "device=LABEL=%s", label);

  r = command (NULL, &err,
               prog, "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mke2fs_JU (const char *fstype, int blocksize, const char *device,
              const char *uuid)
{
  char *err;
  int r;

  char prog[] = "mke2fs";
  if (e2prog (prog) == -1)
    return -1;

  char blocksize_s[32];
  snprintf (blocksize_s, sizeof blocksize_s, "%d", blocksize);

  size_t len = strlen (uuid);
  char jdev[len+32];
  snprintf (jdev, len+32, "device=UUID=%s", uuid);

  r = command (NULL, &err,
               prog, "-F", "-t", fstype, "-J", jdev, "-b", blocksize_s,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
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
  char *err;
  char prog[] = "tune2fs";
  char maxmountcount_s[64];
  char mountcount_s[64];
  char group_s[64];
  char intervalbetweenchecks_s[64];
  char reservedblockspercentage_s[64];
  char reservedblockscount_s[64];
  char user_s[64];

  if (e2prog (prog) == -1)
    return -1;

  ADD_ARG (argv, i, prog);

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
    reply_with_error ("%s: %s: %s", prog, device, err);
    free (err);
    return -1;
  }

  free (err);
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
  char *buf;
  char *out, *err;
  size_t i, j;

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "lsattr", "-d", "--", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "lsattr", filename, err);
    free (err);
    free (out);
    return NULL;
  }
  free (err);

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
  char *buf;
  char *err;
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
  free (buf);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "chattr", filename, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}

int64_t
do_get_e2generation (const char *filename)
{
  int r;
  char *buf;
  char *out, *err;
  int64_t ret;

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (&out, &err, "lsattr", "-dv", "--", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "lsattr", filename, err);
    free (err);
    free (out);
    return -1;
  }
  free (err);

  if (sscanf (out, "%" SCNu64, &ret) != 1) {
    reply_with_error ("cannot parse output from '%s' command: %s",
                      "lsattr", out);
    free (out);
    return -1;
  }
  free (out);

  return ret;
}

int
do_set_e2generation (const char *filename, int64_t generation)
{
  int r;
  char *buf;
  char *err;
  char generation_str[64];

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  snprintf (generation_str, sizeof generation_str,
            "%" PRIu64, (uint64_t) generation);

  r = command (NULL, &err, "chattr", "-v", generation_str, "--", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", "chattr", filename, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}
