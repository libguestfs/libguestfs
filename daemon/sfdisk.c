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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <ctype.h>
#include <inttypes.h>

#include <json.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "daemon.h"
#include "actions.h"

static int
sfdisk (const char *device, int n, int cyls, int heads, int sectors,
        const char *extra_flag,
        char *const *lines)
{
  FILE *fp;
  char buf[256];
  int i;

  strcpy (buf, "sfdisk");

  if (n > 0)
    sprintf (buf + strlen (buf), " -N %d", n);
  if (cyls)
    sprintf (buf + strlen (buf), " -C %d", cyls);
  if (heads)
    sprintf (buf + strlen (buf), " -H %d", heads);
  if (sectors)
    sprintf (buf + strlen (buf), " -S %d", sectors);

  /* The above are all guaranteed to fit in the fixed-size buffer.
     However, extra_flag and device have no restrictions,
     so we must check.  */

  if (extra_flag) {
    if (strlen (buf) + 1 + strlen (extra_flag) >= sizeof buf) {
      reply_with_error ("internal buffer overflow: sfdisk extra_flag too long");
      return -1;
    }
    sprintf (buf + strlen (buf), " %s", extra_flag);
  }

  if (strlen (buf) + 1 + strlen (device) >= sizeof buf) {
    reply_with_error ("internal buffer overflow: sfdisk device name too long");
    return -1;
  }
  sprintf (buf + strlen (buf), " %s", device);

  if (verbose)
    printf ("%s\n", buf);

  fp = popen (buf, "w");
  if (fp == NULL) {
    reply_with_perror ("failed to open pipe: %s", buf);
    return -1;
  }

  for (i = 0; lines[i] != NULL; ++i) {
    if (fprintf (fp, "%s\n", lines[i]) < 0) {
      reply_with_perror ("failed to write to pipe: %s", buf);
      pclose (fp);
      return -1;
    }
  }

  if (pclose (fp) != 0) {
    reply_with_error ("%s: external command failed", buf);
    return -1;
  }

  /* sfdisk sometimes fails on fast machines with:
   *
   * Re-reading the partition table ...
   * BLKRRPART: Device or resource busy
   * The command to re-read the partition table failed.
   * Run partprobe(8), kpartx(8) or reboot your system now,
   * before using mkfs
   *
   * Unclear if this is a bug in sfdisk or the kernel or some
   * other component.  In any case, reread the partition table
   * unconditionally here.
   */
  (void) command (NULL, NULL, "blockdev", "--rereadpt", device, NULL);

  udev_settle ();

  return 0;
}

int
do_sfdisk (const char *device, int cyls, int heads, int sectors,
           char *const *lines)
{
  return sfdisk (device, 0, cyls, heads, sectors, NULL, lines);
}

int
do_sfdisk_N (const char *device, int n, int cyls, int heads, int sectors,
             const char *line)
{
  char const *const lines[2] = { line, NULL };

  return sfdisk (device, n, cyls, heads, sectors, NULL, (void *) lines);
}

int
do_sfdiskM (const char *device, char *const *lines)
{
  return sfdisk (device, 0, 0, 0, 0, "-uM", lines);
}

static char *
sfdisk_flag (const char *device, const char *flag)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (&out, &err, "sfdisk", flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (out);
    return NULL;
  }

  udev_settle ();

  return out;			/* caller frees */
}

char *
do_sfdisk_l (const char *device)
{
  return sfdisk_flag (device, "-l");
}

char *
do_sfdisk_kernel_geometry (const char *device)
{
  return sfdisk_flag (device, "-g");
}

char *
do_sfdisk_disk_geometry (const char *device)
{
  return sfdisk_flag (device, "-G");
}

/* Get partition table for sun disks using sfdisk --json.
 * Returns a formatted string compatible with parted's machine-readable output.
 * Format: "device_line\npartition_line1\npartition_line2\n..."
 * where device_line is: "/dev/sda:SIZEB:TYPE:SECTORSIZE:SECTORSIZE:LABEL:;"
 * and partition_line is: "NUM:STARTB:ENDB:SIZEB:::"
 */
char *
do_sfdisk_sun_partition_table (const char *device)
{
  CLEANUP_FREE char *out = NULL, *err = NULL;
  char *result = NULL;  /* caller frees */
  int r;
  json_object *root = NULL, *pt = NULL, *partitions = NULL;
  json_object *tmp = NULL;
  const char *label = NULL;
  int64_t sectorsize = 512;
  int64_t device_size = 0;
  struct stat statbuf;
  size_t result_size = 0, result_alloc = 4096;

  /* Get device size using stat */
  if (stat (device, &statbuf) == 0 && S_ISREG (statbuf.st_mode))
    device_size = statbuf.st_size;

  /* Run sfdisk --json */
  r = command (&out, &err, "sfdisk", "--json", device, NULL);
  if (r == -1) {
    reply_with_error ("sfdisk --json %s: %s", device, err);
    return NULL;
  }

  /* Parse JSON output */
  root = json_tokener_parse (out);
  if (root == NULL) {
    reply_with_error ("sfdisk --json: failed to parse JSON output");
    return NULL;
  }

  /* Get partitiontable object */
  if (!json_object_object_get_ex (root, "partitiontable", &pt)) {
    reply_with_error ("sfdisk --json: missing 'partitiontable' in output");
    json_object_put (root);
    return NULL;
  }

  /* Get label type */
  if (json_object_object_get_ex (pt, "label", &tmp))
    label = json_object_get_string (tmp);
  if (label == NULL)
    label = "unknown";

  /* Get sector size */
  if (json_object_object_get_ex (pt, "sectorsize", &tmp))
    sectorsize = json_object_get_int64 (tmp);

  /* Allocate result buffer */
  result = malloc (result_alloc);
  if (result == NULL) {
    reply_with_perror ("malloc");
    json_object_put (root);
    return NULL;
  }

  /* Format device line: /dev/sda:104857600B:file:512:512:sun:; */
  r = snprintf (result, result_alloc, "%s:%"PRId64"B:file:%"PRId64":%"PRId64":%s:;",
                device, device_size, sectorsize, sectorsize, label);
  if (r < 0 || (size_t) r >= result_alloc) {
    reply_with_error ("snprintf: device line too long");
    free (result);
    json_object_put (root);
    return NULL;
  }
  result_size = r;

  /* Get partitions array */
  if (!json_object_object_get_ex (pt, "partitions", &partitions)) {
    /* No partitions is OK, just return device line */
    json_object_put (root);
    return result;
  }

  /* Process each partition */
  size_t n_partitions = json_object_array_length (partitions);
  for (size_t i = 0; i < n_partitions; i++) {
    json_object *part = json_object_array_get_idx (partitions, i);
    const char *node = NULL;
    int64_t start = 0, size = 0;
    int partnum = 0;

    /* Get partition node name to extract number */
    if (json_object_object_get_ex (part, "node", &tmp))
      node = json_object_get_string (tmp);

    /* Extract partition number from node name (e.g., "sun.img1" -> 1) */
    if (node) {
      const char *p = node + strlen (node);
      while (p > node && isdigit (*(p-1)))
        p--;
      if (*p)
        partnum = atoi (p);
    }

    /* Get start sector */
    if (json_object_object_get_ex (part, "start", &tmp))
      start = json_object_get_int64 (tmp);

    /* Get size in sectors */
    if (json_object_object_get_ex (part, "size", &tmp))
      size = json_object_get_int64 (tmp);

    /* Convert sectors to bytes */
    int64_t start_bytes = start * sectorsize;
    int64_t size_bytes = size * sectorsize;
    int64_t end_bytes = start_bytes + size_bytes - 1;

    /* Ensure we have enough space in buffer */
    if (result_size + 200 > result_alloc) {
      result_alloc *= 2;
      char *new_result = realloc (result, result_alloc);
      if (new_result == NULL) {
        reply_with_perror ("realloc");
        free (result);
        json_object_put (root);
        return NULL;
      }
      result = new_result;
    }

    /* Format partition line: 1:0B:65802239B:65802240B::: */
    r = snprintf (result + result_size, result_alloc - result_size,
                  "\n%d:%"PRId64"B:%"PRId64"B:%"PRId64"B:::",
                  partnum, start_bytes, end_bytes, size_bytes);
    if (r < 0 || result_size + (size_t) r >= result_alloc) {
      reply_with_error ("snprintf: partition line too long");
      free (result);
      json_object_put (root);
      return NULL;
    }
    result_size += r;
  }

  json_object_put (root);
  return result;
}

/* OCaml binding for sun_partition_table.
 * Called from Sfdisk.sun_partition_table in OCaml code.
 */
value
guestfs_int_daemon_sfdisk_sun_partition_table (value devicev)
{
  CAMLparam1 (devicev);
  CAMLlocal1 (rv);
  const char *device = String_val (devicev);
  char *result;

  result = do_sfdisk_sun_partition_table (device);
  if (result == NULL)
    caml_failwith ("sfdisk_sun_partition_table failed");

  rv = caml_copy_string (result);
  free (result);
  CAMLreturn (rv);
}
