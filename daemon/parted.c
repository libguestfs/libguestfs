/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2025 Red Hat Inc.
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
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

/* Notes:
 *
 * Parted 1.9 sends error messages to stdout, hence use of the
 * COMMAND_FLAG_FOLD_STDOUT_ON_STDERR flag.
 *
 * There is a reason why we call udev_settle both before and after
 * each command.  When you call close on any block device, udev kicks
 * off a rule which runs blkid to reexamine the device.  We need to
 * wait for this rule to finish running (from a previous operation)
 * since it holds the device open.  Since parted also closes the block
 * device, it can cause udev to run again, hence the call to
 * udev_settle afterwards.
 */

static const char *
check_parttype (const char *parttype)
{
    static const struct {
        const char *input;      /* what the user is allowed to type */
        const char *canonical;  /* what we return / what parted expects */
    } map[] = {
        { "aix",    "aix"    },
        { "amiga",  "amiga"  }, { "rdb",  "amiga"  },
        { "bsd",    "bsd"    },
        { "dasd",   "dasd"   },
        { "dvh",    "dvh"    },
        { "gpt",    "gpt"    }, { "efi",  "gpt"    },
        { "mac",    "mac"    },
        { "msdos",  "msdos"  }, { "mbr",  "msdos"  },
        { "pc98",   "pc98"   },
        { "sun",    "sun"    },
    };

    if (parttype == NULL)
        return NULL;

    for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); ++i) {
        if (STREQ(parttype, map[i].input))
            return map[i].canonical;
    }

    return NULL;
}

int
do_part_init (const char *device, const char *parttype)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  parttype = check_parttype (parttype);
  if (!parttype) {
    reply_with_error ("unknown partition type: common choices are \"gpt\" and \"msdos\"");
    return -1;
  }

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--", device, "mklabel", parttype, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_part_add (const char *device, const char *prlogex,
             int64_t startsect, int64_t endsect)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  char startstr[32];
  char endstr[32];

  /* Check and translate prlogex. */
  if (STREQ (prlogex, "primary") ||
      STREQ (prlogex, "logical") ||
      STREQ (prlogex, "extended"))
    ;
  else if (STREQ (prlogex, "p"))
    prlogex = "primary";
  else if (STREQ (prlogex, "l"))
    prlogex = "logical";
  else if (STREQ (prlogex, "e"))
    prlogex = "extended";
  else {
    reply_with_error ("unknown partition type: %s: this should be \"primary\", \"logical\" or \"extended\"", prlogex);
    return -1;
  }

  if (startsect < 0) {
    reply_with_error ("startsect cannot be negative");
    return -1;
  }
  /* but endsect can be negative */

  snprintf (startstr, sizeof startstr, "%" PRIi64 "s", startsect);
  snprintf (endstr, sizeof endstr, "%" PRIi64 "s", endsect);

  udev_settle ();

  /* XXX Bug: If the partition table type (which we don't know in this
   * function) is GPT, then this parted command sets the _partition
   * name_ to prlogex, eg. "primary".  I would essentially describe
   * this as a bug in the parted mkpart command.
   */
  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--",
                device, "mkpart", prlogex, startstr, endstr, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_part_del (const char *device, int partnum)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partnum_str[16];
  snprintf (partnum_str, sizeof partnum_str, "%d", partnum);

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--", device, "rm", partnum_str, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_part_resize (const char *device, int partnum, int64_t endsect)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  char endstr[32];
  char partnum_str[16];

  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  snprintf (partnum_str, sizeof partnum_str, "%d", partnum);
  snprintf (endstr, sizeof endstr, "%" PRIi64 "s", endsect);

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--", device, "resizepart", partnum_str,
                endstr, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s:", device, err);
    return -1;
  }

  udev_settle();

  return 0;
}

int
do_part_disk (const char *device, const char *parttype)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  parttype = check_parttype (parttype);
  if (!parttype) {
    reply_with_error ("unknown partition type: common choices are \"gpt\" and \"msdos\"");
    return -1;
  }

  /* Align all partitions created this way to 128 sectors, and leave
   * the last 128 sectors at the end of the disk free.  This wastes
   * 64K+64K = 128K on 512-byte sector disks.  The rationale is:
   *
   * - aligned operations are faster
   * - absolute minimum recommended alignment is 64K (1M would be better)
   * - GPT requires at least 34 sectors* at the end of the disk.
   *
   *   *=except for 4k sector disks, where only 6 sectors are required
   */
  const char *startstr = "128s";
  const char *endstr = "-128s";

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--",
                device,
                "mklabel", parttype,
                /* See comment about about the parted mkpart command. */
                "mkpart", STREQ (parttype, "gpt") ? "p1" : "primary",
                startstr, endstr, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_part_set_bootable (const char *device, int partnum, int bootable)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partstr[16];

  snprintf (partstr, sizeof partstr, "%d", partnum);

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--",
                device, "set", partstr, "boot", bootable ? "on" : "off", NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_part_set_name (const char *device, int partnum, const char *name)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partstr[16];

  snprintf (partstr, sizeof partstr, "%d", partnum);

  udev_settle ();

  r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                "parted", "-s", "--", device, "name", partstr, name, NULL);
  if (r == -1) {
    reply_with_error ("parted: %s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

/* Return the nth field from a string of ':'/';'-delimited strings.
 * Useful for parsing the return value from 'parted -m'.
 */
static char *
get_table_field (const char *line, int n)
{
  const char *p = line;

  while (*p && n > 0) {
    p += strcspn (p, ":;") + 1;
    n--;
  }

  if (n > 0) {
    reply_with_error ("not enough fields in output of parted print command: %s",
                      line);
    return NULL;
  }

  const size_t len = strcspn (p, ":;");
  char *q = strndup (p, len);
  if (q == NULL) {
    reply_with_perror ("strndup");
    return NULL;
  }

  return q;
}

static char *
print_partition_table (const char *device)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;

  udev_settle ();

  r = command (&out, &err, "parted", "-m", "-s", "--", device,
               "unit", "b",
               "print", NULL);

  udev_settle ();

  if (r == -1) {
    int errcode = 0;

    /* Translate "unrecognised disk label" into an errno code. */
    if (err && strstr (err, "unrecognised disk label") != NULL)
      errcode = EINVAL;

    reply_with_error_errno (errcode, "parted print: %s: %s", device, err);
    free (out);
    return NULL;
  }

  return out;
}

int
do_part_get_bootable (const char *device, int partnum)
{
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  CLEANUP_FREE char *out = print_partition_table (device);
  if (!out)
    return -1;

  CLEANUP_FREE_STRING_LIST char **lines = split_lines (out);

  if (!lines)
    return -1;

  /* Partitions may not be in any order, so we have to look for
   * the matching partition number (RHBZ#602997).
   */
  if (lines[0] == NULL || STRNEQ (lines[0], "BYT;")) {
    reply_with_error ("unknown signature, expected \"BYT;\" as first line of the output: %s",
                      lines[0] ? lines[0] : "(signature was null)");
    return -1;
  }

  if (lines[1] == NULL) {
    reply_with_error ("parted didn't return a line describing the device");
    return -1;
  }

  size_t row;
  int pnum;
  for (row = 2; lines[row] != NULL; ++row) {
    if (sscanf (lines[row], "%d:", &pnum) != 1) {
      reply_with_error ("could not parse row from output of parted print command: %s", lines[row]);
      return -1;
    }
    if (pnum == partnum)
      break;
  }

  if (lines[row] == NULL) {
    reply_with_error ("partition number %d not found", partnum);
    return -1;
  }

  CLEANUP_FREE char *boot = get_table_field (lines[row], 6);
  if (boot == NULL)
    return -1;

  return strstr (boot, "boot") != NULL;
}

int
do_part_set_mbr_id (const char *device, int partnum, int idbyte)
{
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partnum_str[16];
  snprintf (partnum_str, sizeof partnum_str, "%d", partnum);

  char idbyte_str[16];
  /* NB: hex */
  snprintf (idbyte_str, sizeof partnum_str, "%x", (unsigned) idbyte);

  CLEANUP_FREE char *err = NULL;
  int r;

  udev_settle ();

  r = command (NULL, &err, "sfdisk", "--part-type",
               device, partnum_str, idbyte_str, NULL);
  if (r == -1) {
    reply_with_error ("sfdisk --part-type: %s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

char *
do_part_get_name (const char *device, int partnum)
{
  CLEANUP_FREE char *parttype;

  parttype = do_part_get_parttype (device);
  if (parttype == NULL)
    return NULL;

  if (STREQ (parttype, "gpt")) {
    CLEANUP_FREE char *out = print_partition_table (device);
    if (!out)
      return NULL;

    CLEANUP_FREE_STRING_LIST char **lines = split_lines (out);

    if (!lines)
      return NULL;

    if (lines[0] == NULL || STRNEQ (lines[0], "BYT;")) {
      reply_with_error ("unknown signature, expected \"BYT;\" as first line of the output: %s",
                        lines[0] ? lines[0] : "(signature was null)");
      return NULL;
    }

    if (lines[1] == NULL) {
      reply_with_error ("parted didn't return a line describing the device");
      return NULL;
    }

    size_t row;
    int pnum;
    for (row = 2; lines[row] != NULL; ++row) {
      if (sscanf (lines[row], "%d:", &pnum) != 1) {
        reply_with_error ("could not parse row from output of parted print command: %s", lines[row]);
        return NULL;
      }
      if (pnum == partnum)
        break;
    }

    if (lines[row] == NULL) {
      reply_with_error ("partition number %d not found", partnum);
      return NULL;
    }

    char *name = get_table_field (lines[row], 5);
    if (name == NULL)
      reply_with_error ("cannot get the name field from '%s'", lines[row]);

    return name;
  } else {
    reply_with_error ("part-get-name can only be used on GUID Partition Tables");
    return NULL;
  }
}
