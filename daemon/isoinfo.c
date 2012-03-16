/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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
#include <time.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
parse_uint32 (uint32_t *ret, const char *str)
{
  uint32_t r;

  if (sscanf (str, "%" SCNu32, &r) != 1) {
    reply_with_error ("cannot parse numeric field from isoinfo: %s", str);
    return -1;
  }

  *ret = r;
  return 0;
}

/* This is always in a fixed format:
 * "2012 03 16 11:05:46.00"
 * or if the field is not present, then:
 * "0000 00 00 00:00:00.00"
 */
static int
parse_time_t (int64_t *ret, const char *str)
{
  struct tm tm;
  time_t r;

  if (STREQ (str, "0000 00 00 00:00:00.00")) {
    *ret = -1;
    return 0;
  }

  if (sscanf (str, "%04d %02d %02d %02d:%02d:%02d",
              &tm.tm_year, &tm.tm_mon, &tm.tm_mday,
              &tm.tm_hour, &tm.tm_min, &tm.tm_sec) != 6) {
    reply_with_error ("cannot parse date from isoinfo: %s", str);
    return -1;
  }

  /* Adjust fields. */
  tm.tm_year -= 1900;
  tm.tm_mon--;
  tm.tm_isdst = -1;

  /* Convert to time_t. */
  r = timegm (&tm);
  if (r == -1) {
    reply_with_error ("invalid date or time: %s", str);
    return -1;
  }

  *ret = r;
  return 0;
}

static guestfs_int_isoinfo *
parse_isoinfo (char **lines)
{
  guestfs_int_isoinfo *ret;
  size_t i;

  ret = calloc (1, sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("calloc");
    return NULL;
  }

  /* Default each int field in the struct to -1. */
  ret->iso_volume_space_size = (uint32_t) -1;
  ret->iso_volume_set_size = (uint32_t) -1;
  ret->iso_volume_sequence_number = (uint32_t) -1;
  ret->iso_logical_block_size = (uint32_t) -1;
  ret->iso_volume_creation_t = -1;
  ret->iso_volume_modification_t = -1;
  ret->iso_volume_expiration_t = -1;
  ret->iso_volume_effective_t = -1;

  for (i = 0; lines[i] != NULL; ++i) {
    if (STRPREFIX (lines[i], "System id: ")) {
      ret->iso_system_id = strdup (&lines[i][11]);
      if (ret->iso_system_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Volume id: ")) {
      ret->iso_volume_id = strdup (&lines[i][11]);
      if (ret->iso_volume_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Volume set id: ")) {
      ret->iso_volume_set_id = strdup (&lines[i][15]);
      if (ret->iso_volume_set_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Publisher id: ")) {
      ret->iso_publisher_id = strdup (&lines[i][14]);
      if (ret->iso_publisher_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Data preparer id: ")) {
      ret->iso_data_preparer_id = strdup (&lines[i][18]);
      if (ret->iso_data_preparer_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Application id: ")) {
      ret->iso_application_id = strdup (&lines[i][16]);
      if (ret->iso_application_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Copyright File id: ")) {
      ret->iso_copyright_file_id = strdup (&lines[i][19]);
      if (ret->iso_copyright_file_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Abstract File id: ")) {
      ret->iso_abstract_file_id = strdup (&lines[i][18]);
      if (ret->iso_abstract_file_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Bibliographic File id: ")) {
      ret->iso_bibliographic_file_id = strdup (&lines[i][23]);
      if (ret->iso_bibliographic_file_id == NULL) goto error;
    }
    else if (STRPREFIX (lines[i], "Volume size is: ")) {
      if (parse_uint32 (&ret->iso_volume_space_size, &lines[i][16]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Volume set size is: ")) {
      if (parse_uint32 (&ret->iso_volume_set_size, &lines[i][20]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Volume set sequence number is: ")) {
      if (parse_uint32 (&ret->iso_volume_sequence_number, &lines[i][31]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Logical block size is: ")) {
      if (parse_uint32 (&ret->iso_logical_block_size, &lines[i][23]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Creation Date:     ")) {
      if (parse_time_t (&ret->iso_volume_creation_t, &lines[i][19]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Modification Date: ")) {
      if (parse_time_t (&ret->iso_volume_modification_t, &lines[i][19]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Expiration Date:   ")) {
      if (parse_time_t (&ret->iso_volume_expiration_t, &lines[i][19]) == -1)
        goto error;
    }
    else if (STRPREFIX (lines[i], "Effective Date:    ")) {
      if (parse_time_t (&ret->iso_volume_effective_t, &lines[i][19]) == -1)
        goto error;
    }
  }

  /* Any string fields which were not set above will be NULL.  However
   * we cannot return NULL fields in structs, so we convert these to
   * empty strings here.
   */
  if (ret->iso_system_id == NULL) {
    ret->iso_system_id = strdup ("");
    if (ret->iso_system_id == NULL) goto error;
  }
  if (ret->iso_volume_id == NULL) {
    ret->iso_volume_id = strdup ("");
    if (ret->iso_volume_id == NULL) goto error;
  }
  if (ret->iso_volume_set_id == NULL) {
    ret->iso_volume_set_id = strdup ("");
    if (ret->iso_volume_set_id == NULL) goto error;
  }
  if (ret->iso_publisher_id == NULL) {
    ret->iso_publisher_id = strdup ("");
    if (ret->iso_publisher_id == NULL) goto error;
  }
  if (ret->iso_data_preparer_id == NULL) {
    ret->iso_data_preparer_id = strdup ("");
    if (ret->iso_data_preparer_id == NULL) goto error;
  }
  if (ret->iso_application_id == NULL) {
    ret->iso_application_id = strdup ("");
    if (ret->iso_application_id == NULL) goto error;
  }
  if (ret->iso_copyright_file_id == NULL) {
    ret->iso_copyright_file_id = strdup ("");
    if (ret->iso_copyright_file_id == NULL) goto error;
  }
  if (ret->iso_abstract_file_id == NULL) {
    ret->iso_abstract_file_id = strdup ("");
    if (ret->iso_abstract_file_id == NULL) goto error;
  }
  if (ret->iso_bibliographic_file_id == NULL) {
    ret->iso_bibliographic_file_id = strdup ("");
    if (ret->iso_bibliographic_file_id == NULL) goto error;
  }

  return ret;

 error:
  free (ret->iso_system_id);
  free (ret->iso_volume_id);
  free (ret->iso_volume_set_id);
  free (ret->iso_publisher_id);
  free (ret->iso_data_preparer_id);
  free (ret->iso_application_id);
  free (ret->iso_copyright_file_id);
  free (ret->iso_abstract_file_id);
  free (ret->iso_bibliographic_file_id);
  free (ret);
  return NULL;
}

static guestfs_int_isoinfo *
isoinfo (const char *path)
{
  char *out = NULL, *err = NULL;
  int r;
  char **lines = NULL;
  guestfs_int_isoinfo *ret = NULL;

  /* --debug is necessary to get additional fields, in particular
   * the date & time fields.
   */
  r = command (&out, &err, "isoinfo", "--debug", "-d", "-i", path, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    goto done;
  }

  lines = split_lines (out);
  if (lines == NULL)
    goto done;

  ret = parse_isoinfo (lines);
  if (ret == NULL)
    goto done;

 done:
  free (out);
  free (err);
  if (lines)
    free_strings (lines);

  return ret;
}

guestfs_int_isoinfo *
do_isoinfo_device (const char *device)
{
  return isoinfo (device);
}

guestfs_int_isoinfo *
do_isoinfo (const char *path)
{
  char *buf;
  guestfs_int_isoinfo *ret;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret = isoinfo (buf);
  free (buf);

  return ret;
}
