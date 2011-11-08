/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2011 Red Hat Inc.
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
do_part_del (const char *device, int partnum)
{
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partnum_str[16];
  snprintf (partnum_str, sizeof partnum_str, "%d", partnum);

  RUN_PARTED (return -1, device, "rm", partnum_str, NULL);

  udev_settle ();
  return 0;
}

int
do_part_disk (const char *device, const char *parttype)
{
  parttype = check_parttype (parttype);
  if (!parttype) {
    reply_with_error ("unknown partition type: common choices are \"gpt\" and \"msdos\"");
    return -1;
  }

  /* Align all partitions created this way to 64 sectors, and leave
   * the last 64 sectors at the end of the disk free.  This wastes
   * 32K+32K = 64K on 512-byte sector disks.  The rationale is:
   *
   * - aligned operations are faster
   * - GPT requires at least 34 sectors at the end of the disk.
   */
  const char *startstr = "64s";
  const char *endstr = "-64s";

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
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

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
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partstr[16];

  snprintf (partstr, sizeof partstr, "%d", partnum);

  RUN_PARTED (return -1, device, "name", partstr, name, NULL);

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

  size_t len = strcspn (p, ":;");
  char *q = strndup (p, len);
  if (q == NULL) {
    reply_with_perror ("strndup");
    return NULL;
  }

  return q;
}

/* RHEL 5 parted doesn't have the -m (machine readable) option so we
 * must do a lot more work to parse the output in
 * print_partition_table below.  Test for this option the first time
 * this function is called.
 */
static int
test_parted_m_opt (void)
{
  static int result = -1;

  if (result >= 0)
    return result;

  char *err = NULL;
  int r = commandr (NULL, &err, "parted", "-s", "-m", "/dev/null", NULL);
  if (r == -1) {
    /* Test failed, eg. missing or completely unusable parted binary. */
    reply_with_error ("could not run 'parted' command");
    free (err);
    return -1;
  }

  if (err && strstr (err, "invalid option -- m"))
    result = 0;
  else
    result = 1;
  free (err);
  return result;
}

static char *
print_partition_table (const char *device, int parted_has_m_opt)
{
  char *out, *err;
  int r;

  if (parted_has_m_opt)
    r = command (&out, &err, "parted", "-m", "--", device,
                 "unit", "b",
                 "print", NULL);
  else
    r = command (&out, &err, "parted", "-s", "--", device,
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

  return out;
}

char *
do_part_get_parttype (const char *device)
{
  int parted_has_m_opt = test_parted_m_opt ();
  if (parted_has_m_opt == -1)
    return NULL;

  char *out = print_partition_table (device, parted_has_m_opt);
  if (!out)
    return NULL;

  if (parted_has_m_opt) {
    /* New-style parsing using the "machine-readable" format from
     * 'parted -m'.
     */
    char **lines = split_lines (out);
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

    /* lines[1] is something like:
     * "/dev/sda:1953525168s:scsi:512:512:msdos:ATA Hitachi HDT72101;"
     */
    char *r = get_table_field (lines[1], 5);
    if (r == NULL) {
      free_strings (lines);
      return NULL;
    }

    free_strings (lines);

    /* If "loop" return an error (RHBZ#634246). */
    if (STREQ (r, "loop")) {
      free (r);
      reply_with_error ("not a partitioned device");
      return NULL;
    }

    return r;
  }
  else {
    /* Old-style.  Look for "\nPartition Table: <str>\n". */
    char *p = strstr (out, "\nPartition Table: ");
    if (!p) {
      reply_with_error ("parted didn't return Partition Table line");
      free (out);
      return NULL;
    }

    p += 18;
    char *q = strchr (p, '\n');
    if (!q) {
      reply_with_error ("parted Partition Table has no end of line char");
      free (out);
      return NULL;
    }

    *q = '\0';

    p = strdup (p);
    free (out);
    if (!p) {
      reply_with_perror ("strdup");
      return NULL;
    }

    /* If "loop" return an error (RHBZ#634246). */
    if (STREQ (p, "loop")) {
      free (p);
      reply_with_error ("not a partitioned device");
      return NULL;
    }

    return p;                   /* caller frees */
  }
}

guestfs_int_partition_list *
do_part_list (const char *device)
{
  int parted_has_m_opt = test_parted_m_opt ();
  if (parted_has_m_opt == -1)
    return NULL;

  char *out = print_partition_table (device, parted_has_m_opt);
  if (!out)
    return NULL;

  char **lines = split_lines (out);
  free (out);

  if (!lines)
    return NULL;

  guestfs_int_partition_list *r;

  if (parted_has_m_opt) {
    /* New-style parsing using the "machine-readable" format from
     * 'parted -m'.
     *
     * lines[0] is "BYT;", lines[1] is the device line which we ignore,
     * lines[2..] are the partitions themselves.  Count how many.
     */
    size_t nr_rows = 0, row;
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
    size_t i;
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
  }
  else {
    /* Old-style.  Start at the line following "^Number", up to the
     * next blank line.
     */
    size_t start = 0, end = 0, row;

    for (row = 0; lines[row] != NULL; ++row)
      if (STRPREFIX (lines[row], "Number")) {
        start = row+1;
        break;
      }

    if (start == 0) {
      reply_with_error ("parted output has no \"Number\" line");
      goto error1;
    }

    for (row = start; lines[row] != NULL; ++row)
      if (STREQ (lines[row], "")) {
        end = row;
        break;
      }

    if (end == 0) {
      reply_with_error ("parted output has no blank after end of table");
      goto error1;
    }

    size_t nr_rows = end - start;

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
    size_t i;
    for (i = 0, row = start; row < end; ++i, ++row) {
      if (sscanf (lines[row], " %d %" SCNi64 "B %" SCNi64 "B %" SCNi64 "B",
                  &r->guestfs_int_partition_list_val[i].part_num,
                  &r->guestfs_int_partition_list_val[i].part_start,
                  &r->guestfs_int_partition_list_val[i].part_end,
                  &r->guestfs_int_partition_list_val[i].part_size) != 4) {
        reply_with_error ("could not parse row from output of parted print command: %s", lines[row]);
        goto error3;
      }
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

int
do_part_get_bootable (const char *device, int partnum)
{
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  int parted_has_m_opt = test_parted_m_opt ();
  if (parted_has_m_opt == -1)
    return -1;

  char *out = print_partition_table (device, parted_has_m_opt);
  if (!out)
    return -1;

  char **lines = split_lines (out);
  free (out);

  if (!lines)
    return -1;

  if (parted_has_m_opt) {
    /* New-style parsing using the "machine-readable" format from
     * 'parted -m'.
     *
     * Partitions may not be in any order, so we have to look for
     * the matching partition number (RHBZ#602997).
     */
    if (lines[0] == NULL || STRNEQ (lines[0], "BYT;")) {
      reply_with_error ("unknown signature, expected \"BYT;\" as first line of the output: %s",
                        lines[0] ? lines[0] : "(signature was null)");
      free_strings (lines);
      return -1;
    }

    if (lines[1] == NULL) {
      reply_with_error ("parted didn't return a line describing the device");
      free_strings (lines);
      return -1;
    }

    size_t row;
    int pnum;
    for (row = 2; lines[row] != NULL; ++row) {
      if (sscanf (lines[row], "%d:", &pnum) != 1) {
        reply_with_error ("could not parse row from output of parted print command: %s", lines[row]);
        free_strings (lines);
        return -1;
      }
      if (pnum == partnum)
        break;
    }

    if (lines[row] == NULL) {
      reply_with_error ("partition number %d not found", partnum);
      free_strings (lines);
      return -1;
    }

    char *boot = get_table_field (lines[row], 6);
    if (boot == NULL) {
      free_strings (lines);
      return -1;
    }

    int r = STREQ (boot, "boot");

    free (boot);
    free_strings (lines);

    return r;
  }
  else {
    /* Old-style: First look for the line matching "^Number". */
    size_t start = 0, header, row;

    for (row = 0; lines[row] != NULL; ++row)
      if (STRPREFIX (lines[row], "Number")) {
        start = row+1;
        header = row;
        break;
      }

    if (start == 0) {
      reply_with_error ("parted output has no \"Number\" line");
      free_strings (lines);
      return -1;
    }

    /* Now we have to look at the column number of the "Flags" field.
     * This is because parted's output has no way to represent a
     * missing field except as whitespace, so we cannot just count
     * fields from the left.  eg. The "File system" field is often
     * missing in the output.
     */
    char *p = strstr (lines[header], "Flags");
    if (!p) {
      reply_with_error ("parted output has no \"Flags\" field");
      free_strings (lines);
      return -1;
    }
    size_t col = p - lines[header];

    /* Look for the line corresponding to this partition number. */
    row = start + partnum - 1;
    if (row >= count_strings (lines) || !STRPREFIX (lines[row], " ")) {
      reply_with_error ("partition number out of range: %d", partnum);
      free_strings (lines);
      return -1;
    }

    int r = STRPREFIX (&lines[row][col], "boot");
    free_strings (lines);
    return r;
  }
}

/* Currently we use sfdisk for getting and setting the ID byte.  In
 * future, extend parted to provide this functionality.  As a result
 * of using sfdisk, this won't work for non-MBR-style partitions, but
 * that limitation is noted in the documentation and we can extend it
 * later without breaking the ABI.
 */
int
do_part_get_mbr_id (const char *device, int partnum)
{
  if (partnum <= 0) {
    reply_with_error ("partition number must be >= 1");
    return -1;
  }

  char partnum_str[16];
  snprintf (partnum_str, sizeof partnum_str, "%d", partnum);

  char *out, *err;
  int r;

  r = command (&out, &err, "sfdisk", "--print-id", device, partnum_str, NULL);
  if (r == -1) {
    reply_with_error ("sfdisk --print-id: %s", err);
    free (out);
    free (err);
    return -1;
  }

  free (err);

  /* It's printed in hex ... */
  int id;
  if (sscanf (out, "%x", &id) != 1) {
    reply_with_error ("sfdisk --print-id: cannot parse output: %s", out);
    free (out);
    return -1;
  }

  free (out);
  return id;
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
  snprintf (idbyte_str, sizeof partnum_str, "%x", idbyte); /* NB: hex */

  char *err;
  int r;

  r = command (NULL, &err, "sfdisk",
               "--change-id", device, partnum_str, idbyte_str, NULL);
  if (r == -1) {
    reply_with_error ("sfdisk --change-id: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
