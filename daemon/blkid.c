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
#include "optgroups.h"

char *
get_blkid_tag (const char *device, const char *tag)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;
  size_t len;

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
    return NULL;
  }

  if (r == 2) {                 /* means UUID etc not found */
    free (out);
    out = strdup ("");
    if (out == NULL)
      reply_with_perror ("strdup");
    return out;
  }

  /* Trim trailing \n if present. */
  len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  return out;                   /* caller frees */
}

char *
do_vfs_label (const mountable_t *mountable)
{
  CLEANUP_FREE char *type = do_vfs_type (mountable);

  if (type) {
    if (STREQ (type, "btrfs") && optgroup_btrfs_available ())
      return btrfs_get_label (mountable->device);
    if (STREQ (type, "ntfs") && optgroup_ntfsprogs_available ())
      return ntfs_get_label (mountable->device);
  }

  return get_blkid_tag (mountable->device, "LABEL");
}

char *
do_vfs_uuid (const mountable_t *mountable)
{
  return get_blkid_tag (mountable->device, "UUID");
}

/* RHEL5 blkid doesn't have the -p (low-level probing) option and the
 * -i(I/O limits) option so we must test for these options the first
 * time the function is called.
 *
 * Debian 6 has -p but not -i.
 */
static int
test_blkid_p_i_opt (void)
{
  int r;
  CLEANUP_FREE char *err = NULL, *err2 = NULL;

  r = commandr (NULL, &err, "blkid", "-p", "/dev/null", NULL);
  if (r == -1) {
    /* This means we couldn't run the blkid command at all. */
  command_failed:
    reply_with_error ("could not run 'blkid' command: %s", err);
    return -1;
  }

  if (strstr (err, "invalid option --")) {
    return 0;
  }

  r = commandr (NULL, &err2, "blkid", "-i", NULL);
  if (r == -1)
    goto command_failed;

  if (strstr (err2, "invalid option --")) {
    return 0;
  }

  /* We have both options. */
  return 1;
}

static char **
blkid_with_p_i_opt (const char *device)
{
  size_t i;
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;
  CLEANUP_FREE_STRING_LIST char **lines = NULL;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);

  r = command (&out, &err, "blkid", "-c", "/dev/null",
               "-p", "-i", "-o", "export", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  /* Split the command output into lines */
  lines = split_lines (out);
  if (lines == NULL)
    return NULL;

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
  for (i = 0; lines[i] != NULL; ++i) {
    char *eq;
    char *line = lines[i];

    /* Skip blank lines (shouldn't happen) */
    if (line[0] == '\0') continue;

    /* Split the line in 2 at the equals sign */
    eq = strchr (line, '=');
    if (eq) {
      *eq = '\0'; eq++;

      /* Add the key/value pair to the output */
      if (add_string (&ret, line) == -1 ||
          add_string (&ret, eq) == -1) return NULL;
    } else {
      fprintf (stderr, "blkid: unexpected blkid output ignored: %s", line);
    }
  }

  if (end_stringsbuf (&ret) == -1) return NULL;

  return take_stringsbuf (&ret);
}

static char **
blkid_without_p_i_opt (const char *device)
{
  char *s;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);

  if (add_string (&ret, "TYPE") == -1) return NULL;
  s = get_blkid_tag (device, "TYPE");
  if (s == NULL) return NULL;
  if (add_string_nodup (&ret, s) == -1)
    return NULL;

  if (add_string (&ret, "LABEL") == -1) return NULL;
  s = get_blkid_tag (device, "LABEL");
  if (s == NULL) return NULL;
  if (add_string_nodup (&ret, s) == -1)
    return NULL;

  if (add_string (&ret, "UUID") == -1) return NULL;
  s = get_blkid_tag (device, "UUID");
  if (s == NULL) return NULL;
  if (add_string_nodup (&ret, s) == -1)
    return NULL;

  if (end_stringsbuf (&ret) == -1) return NULL;

  return take_stringsbuf (&ret);
}

char **
do_blkid (const char *device)
{
  static int blkid_has_p_i_opt = -1;

  if (blkid_has_p_i_opt == -1) {
    blkid_has_p_i_opt = test_blkid_p_i_opt ();
    if (blkid_has_p_i_opt == -1)
      return NULL;
  }

  if (blkid_has_p_i_opt)
    return blkid_with_p_i_opt (device);
  else
    return blkid_without_p_i_opt (device);
}
