/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

/* Notes:
 *
 * Parted 1.9 sends error messages to stdout, hence use of the
 * COMMAND_FLAG_FOLD_STDOUT_ON_STDERR flag.
 *
 * parted occasionally fails to do ioctl(BLKRRPART) on the device,
 * apparently because of some internal race in the code.  We attempt
 * to detect and recover from this error if we can.
 */
static int
recover_blkrrpart (const char *device, const char *err)
{
  int r;

  if (!strstr (err,
               "Error informing the kernel about modifications to partition"))
    return -1;

  r = command (NULL, NULL, "blockdev", "--rereadpt", device, NULL);
  if (r == -1)
    return -1;

  udev_settle ();

  return 0;
}

#define RUN_PARTED(error,device,...)                                    \
  do {                                                                  \
    int r;                                                              \
    char *err;                                                          \
                                                                        \
    r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,       \
                  "parted", "-s", "--", (device), __VA_ARGS__);   \
    if (r == -1) {                                                      \
      if (recover_blkrrpart ((device), err) == -1) {                    \
        reply_with_error ("%s: parted: %s: %s", __func__, (device), err); \
        free (err);                                                     \
        error;                                                          \
      }                                                                 \
    }                                                                   \
                                                                        \
    free (err);                                                         \
  } while (0)

static const char *
check_parttype (const char *parttype)
{
  /* Check and translate parttype. */
  if (STREQ (parttype, "aix") ||
      STREQ (parttype, "amiga") ||
      STREQ (parttype, "bsd") ||
      STREQ (parttype, "dasd") ||
      STREQ (parttype, "dvh") ||
      STREQ (parttype, "gpt") ||
      STREQ (parttype, "mac") ||
      STREQ (parttype, "msdos") ||
      STREQ (parttype, "pc98") ||
      STREQ (parttype, "sun"))
    return parttype;
  else if (STREQ (parttype, "rdb"))
    return "amiga";
  else if (STREQ (parttype, "efi"))
    return "gpt";
  else if (STREQ (parttype, "mbr"))
    return "msdos";
  else
    return NULL;
}

int
do_part_init (const char *device, const char *parttype)
{
  parttype = check_parttype (parttype);
  if (!parttype) {
    reply_with_error ("unknown partition type: common choices are \"gpt\" and \"msdos\"");
    return -1;
  }

  RUN_PARTED (return -1, device, "mklabel", parttype, NULL);

  udev_settle ();

  return 0;
}

int
do_part_add (const char *device, const char *prlogex,
             int64_t startsect, int64_t endsect)
{
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

  /* XXX Bug: If the partition table type (which we don't know in this
   * function) is GPT, then this parted command sets the _partition
   * name_ to prlogex, eg. "primary".  I would essentially describe
   * this as a bug in the parted mkpart command.
   */
  RUN_PARTED (return -1, device, "mkpart", prlogex, startstr, endstr, NULL);

  udev_settle ();

  return 0;
}

int
do_part_disk (const char *device, const char *parttype)
{
  const char *startstr;
  const char *endstr;

  parttype = check_parttype (parttype);
  if (!parttype) {
    reply_with_error ("unknown partition type: common choices are \"gpt\" and \"msdos\"");
    return -1;
  }

  /* Voooooodooooooooo (thanks Jim Meyering for working this out). */
  if (STREQ (parttype, "msdos")) {
    startstr = "1s";
    endstr = "-1s";
  } else if (STREQ (parttype, "gpt")) {
    startstr = "34s";
    endstr = "-34s";
  } else {
    /* untested */
    startstr = "1s";
    endstr = "-1s";
  }

  RUN_PARTED (return -1,
              device,
              "mklabel", parttype,
              /* See comment about about the parted mkpart command. */
              "mkpart", STREQ (parttype, "gpt") ? "p1" : "primary",
              startstr, endstr, NULL);

  udev_settle ();

  return 0;
}

int
do_part_set_bootable (const char *device, int partnum, int bootable)
{
  char partstr[16];

  snprintf (partstr, sizeof partstr, "%d", partnum);

  RUN_PARTED (return -1,
              device, "set", partstr, "boot", bootable ? "on" : "off", NULL);

  udev_settle ();

  return 0;
}

int
do_part_set_name (const char *device, int partnum, const char *name)
{
  char partstr[16];

  snprintf (partstr, sizeof partstr, "%d", partnum);

  RUN_PARTED (return -1, device, "name", partstr, name, NULL);

  udev_settle ();

  return 0;
}

/* Return the nth field from a string of ':'/';'-delimited strings.
 * Useful for parsing the return value from print_partition_table
 * function below.
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

  size_t len = strcspn (p, ":;");
  char *q = strndup (p, len);
  if (q == NULL) {
    reply_with_perror ("strndup");
    return NULL;
  }

  return q;
}

static char **
print_partition_table (const char *device)
{
  char *out, *err;
  int r;
  char **lines;

  r = command (&out, &err, "parted", "-m", "--", device,
               "unit", "b",
               "print", NULL);
  if (r == -1) {
    reply_with_error ("parted print: %s: %s", device,
                      /* Hack for parted 1.x which sends errors to stdout. */
                      *err ? err : out);
    free (out);
    free (err);
    return NULL;
  }
  free (err);

  lines = split_lines (out);
  free (out);

  if (!lines)
    return NULL;

  if (lines[0] == NULL || STRNEQ (lines[0], "BYT;")) {
    reply_with_error ("unknown signature, expected \"BYT;\" as first line of the output: %s",
                      lines[0] ? lines[0] : "(signature was null)");
    free_strings (lines);
    return NULL;
  }

  if (lines[1] == NULL) {
    reply_with_error ("parted didn't return a line describing the device");
    free_strings (lines);
    return NULL;
  }

  return lines;
}

char *
do_part_get_parttype (const char *device)
{
  char **lines = print_partition_table (device);
  if (!lines)
    return NULL;

  /* lines[1] is something like:
   * "/dev/sda:1953525168s:scsi:512:512:msdos:ATA Hitachi HDT72101;"
   */
  char *r = get_table_field (lines[1], 5);
  if (r == NULL) {
    free_strings (lines);
    return NULL;
  }

  free_strings (lines);

  return r;
}

guestfs_int_partition_list *
do_part_list (const char *device)
{
  char **lines;
  size_t row, nr_rows, i;
  guestfs_int_partition_list *r;

  lines = print_partition_table (device);
  if (!lines)
    return NULL;

  /* lines[0] is "BYT;", lines[1] is the device line which we ignore,
   * lines[2..] are the partitions themselves.  Count how many.
   */
  nr_rows = 0;
  for (row = 2; lines[row] != NULL; ++row)
    ++nr_rows;

  r = malloc (sizeof *r);
  if (r == NULL) {
    reply_with_perror ("malloc");
    goto error1;
  }
  r->guestfs_int_partition_list_len = nr_rows;
  r->guestfs_int_partition_list_val =
    malloc (nr_rows * sizeof (guestfs_int_partition));
  if (r->guestfs_int_partition_list_val == NULL) {
    reply_with_perror ("malloc");
    goto error2;
  }

  /* Now parse the lines. */
  for (i = 0, row = 2; lines[row] != NULL; ++i, ++row) {
    if (sscanf (lines[row], "%d:%" SCNi64 "B:%" SCNi64 "B:%" SCNi64 "B",
                &r->guestfs_int_partition_list_val[i].part_num,
                &r->guestfs_int_partition_list_val[i].part_start,
                &r->guestfs_int_partition_list_val[i].part_end,
                &r->guestfs_int_partition_list_val[i].part_size) != 4) {
      reply_with_error ("could not parse row from output of parted print command: %s", lines[row]);
      goto error3;
    }
  }

  free_strings (lines);
  return r;

 error3:
  free (r->guestfs_int_partition_list_val);
 error2:
  free (r);
 error1:
  free_strings (lines);
  return NULL;
}
