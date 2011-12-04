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
#include <limits.h>

#include "daemon.h"
#include "actions.h"

static char *
get_blkid_tag (const char *device, const char *tag)
{
  char *out, *err;
  int r;

  r = commandr (&out, &err,
                "blkid",
                /* Adding -c option kills all caching, even on RHEL 5. */
                "-c", "/dev/null",
                "-o", "value", "-s", tag, device, NULL);
  if (r != 0 && r != 2) {
    if (r >= 0)
      reply_with_error ("%s: %s (blkid returned %d)", device, err, r);
    else
      reply_with_error ("%s: %s", device, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  if (r == 2) {                 /* means UUID etc not found */
    free (out);
    out = strdup ("");
    if (out == NULL)
      reply_with_perror ("strdup");
    return out;
  }

  /* Trim trailing \n if present. */
  size_t len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  return out;                   /* caller frees */
}

char *
do_vfs_type (const char *device)
{
  return get_blkid_tag (device, "TYPE");
}

char *
do_vfs_label (const char *device)
{
  return get_blkid_tag (device, "LABEL");
}

char *
do_vfs_uuid (const char *device)
{
  return get_blkid_tag (device, "UUID");
}

char **
do_blkid(const char *device)
{
  int r;
  char *out = NULL, *err = NULL;
  char **lines = NULL;

  char **ret = NULL;
  int size = 0, alloc = 0;

  const char *blkid[] = {"blkid", "-p", "-i", "-o", "export", device, NULL};
  r = commandv(&out, &err, blkid);
  if (r == -1) {
    reply_with_error("%s", err);
    goto error;
  }

  /* Split the command output into lines */
  lines = split_lines(out);
  if (lines == NULL) {
    reply_with_perror("malloc");
    goto error;
  }

  /* Parse the output of blkid -p -i -o export:
   * UUID=b6d83437-c6b4-4bf0-8381-ef3fc3578590
   * VERSION=1.0
   * TYPE=ext2
   * USAGE=filesystem
   * MINIMUM_IO_SIZE=512
   * PHYSICAL_SECTOR_SIZE=512
   * LOGICAL_SECTOR_SIZE=512
   * PART_ENTRY_SCHEME=dos
   * PART_ENTRY_TYPE=0x83
   * PART_ENTRY_NUMBER=6
   * PART_ENTRY_OFFSET=642875153
   * PART_ENTRY_SIZE=104857600
   * PART_ENTRY_DISK=8:0
   */
  for (char **i = lines; *i != NULL; i++) {
    char *line = *i;

    /* Skip blank lines (shouldn't happen) */
    if (line[0] == '\0') continue;

    /* Split the line in 2 at the equals sign */
    char *eq = strchr(line, '=');
    if (eq) {
      *eq = '\0'; eq++;

      /* Add the key/value pair to the output */
      if (add_string(&ret, &size, &alloc, line) == -1 ||
          add_string(&ret, &size, &alloc, eq) == -1) goto error;
    } else {
      fprintf(stderr, "blkid: unexpected blkid output ignored: %s", line);
    }
  }

  free(out);
  free(err);
  free(lines);

  if (add_string(&ret, &size, &alloc, NULL) == -1) return NULL;

  return ret;

error:
  free(out);
  free(err);
  if (lines) free(lines);
  if (ret) free_strings(ret);

  return NULL;
}
