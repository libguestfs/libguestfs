/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Fujitsu Limited.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_xfs_available (void)
{
  return prog_exists ("mkfs.xfs");
}

static char *
split_strdup (char *string)
{
  char *end = string;
  while (*end != ' ' && *end != ',' && *end != '\0') end++;
  size_t len = end - string;
  char *ret = malloc (len + 1);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }
  strncpy (ret, string, len);
  ret[len] = '\0';
  return ret;
}

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

static int
parse_uint64 (uint64_t *ret, const char *str)
{
  uint64_t r;

  if (sscanf (str, "%" SCNu64, &r) != 1) {
    reply_with_error ("cannot parse numeric field from isoinfo: %s", str);
    return -1;
  }

  *ret = r;
  return 0;
}

/* Typical crazy output from the xfs_info command:
 *
 * meta-data=/dev/sda1              isize=256    agcount=4, agsize=6392 blks
 *          =                       sectsz=512   attr=2
 * data     =                       bsize=4096   blocks=25568, imaxpct=25
 *          =                       sunit=0      swidth=0 blks
 * naming   =version 2              bsize=4096   ascii-ci=0
 * log      =internal               bsize=4096   blocks=1200, version=2
 *          =                       sectsz=512   sunit=0 blks, lazy-count=1
 * realtime =none                   extsz=4096   blocks=0, rtextents=0
 *
 * We may need to revisit this parsing code if the output changes
 * in future.
 */
static guestfs_int_xfsinfo *
parse_xfs_info (char **lines)
{
  guestfs_int_xfsinfo *ret;
  char *buf = NULL, *p;
  size_t i;

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_error ("malloc");
    return NULL;
  }

  /* Initialize fields to NULL or -1 so the caller can tell which fields
   * were updated in the code below.
   */
  ret->xfs_mntpoint = NULL;
  ret->xfs_inodesize = -1;
  ret->xfs_agcount = -1;
  ret->xfs_agsize = -1;
  ret->xfs_sectsize = -1;
  ret->xfs_attr = -1;
  ret->xfs_blocksize = -1;
  ret->xfs_datablocks = -1;
  ret->xfs_imaxpct = -1;
  ret->xfs_sunit = -1;
  ret->xfs_swidth = -1;
  ret->xfs_dirversion = -1;
  ret->xfs_dirblocksize = -1;
  ret->xfs_cimode = -1;
  ret->xfs_logname = NULL;
  ret->xfs_logblocksize = -1;
  ret->xfs_logblocks = -1;
  ret->xfs_logversion = -1;
  ret->xfs_logsectsize = -1;
  ret->xfs_logsunit = -1;
  ret->xfs_lazycount = -1;
  ret->xfs_rtname = NULL;
  ret->xfs_rtextsize = -1;
  ret->xfs_rtblocks = -1;
  ret->xfs_rtextents = -1;

  for (i = 0; lines[i] != NULL; ++i) {
    if ((p = strstr (lines[i], "meta-data="))) {
      ret->xfs_mntpoint = split_strdup (p + 10);
      if (ret->xfs_mntpoint == NULL) goto error;
    }
    if ((p = strstr (lines[i], "isize="))) {
      buf = split_strdup (p + 6);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_inodesize, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "agcount="))) {
      buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_agcount, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "agsize="))) {
      buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_agsize, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "sectsz="))) {
      buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (i == 1) {
        if (parse_uint32 (&ret->xfs_sectsize, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 6) {
        if (parse_uint32 (&ret->xfs_logsectsize, buf) == -1)
          goto error;
        free (buf);
      } else goto error;
    }
    if ((p = strstr (lines[i], "attr="))) {
      buf = split_strdup (p + 5);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_attr, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "bsize="))) {
      buf = split_strdup (p + 6);
      if (buf == NULL) goto error;
      if (i == 2) {
        if (parse_uint32 (&ret->xfs_blocksize, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 4) {
        if (parse_uint32 (&ret->xfs_dirblocksize, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 5) {
        if (parse_uint32 (&ret->xfs_logblocksize, buf) == -1)
          goto error;
        free (buf);
      } else goto error;
    }
    if ((p = strstr (lines[i], "blocks="))) {
      buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (i == 2) {
        if (parse_uint64 (&ret->xfs_datablocks, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 5) {
        if (parse_uint32 (&ret->xfs_logblocks, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 7) {
        if (parse_uint64 (&ret->xfs_rtblocks, buf) == -1)
          goto error;
        free (buf);
      } else goto error;
    }
    if ((p = strstr (lines[i], "imaxpct="))) {
      buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_imaxpct, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "sunit="))) {
      buf = split_strdup (p + 6);
      if (buf == NULL) goto error;
      if (i == 3) {
        if (parse_uint32 (&ret->xfs_sunit, buf) == -1)
          goto error;
        free (buf);
      } else if (i == 6) {
        if (parse_uint32 (&ret->xfs_logsunit, buf) == -1)
          goto error;
        free (buf);
      } else goto error;
    }
    if ((p = strstr (lines[i], "swidth="))) {
      buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_swidth, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "naming   =version "))) {
      buf = split_strdup (p + 18);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_dirversion, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "ascii-ci="))) {
      buf = split_strdup (p + 9);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_cimode, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "log      ="))) {
      ret->xfs_logname = split_strdup (p + 10);
      if (ret->xfs_logname == NULL) goto error;
    }
    if ((p = strstr (lines[i], "version="))) {
      buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_logversion, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "lazy-count="))) {
      buf = split_strdup (p + 11);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_lazycount, buf) == -1)
        goto error;
      free (buf);
    }
    if ((p = strstr (lines[i], "realtime ="))) {
      ret->xfs_rtname = split_strdup (p + 10);
      if (ret->xfs_rtname == NULL) goto error;
    }
    if ((p = strstr (lines[i], "rtextents="))) {
      buf = split_strdup (p + 10);
      if (buf == NULL) goto error;
      if (parse_uint64 (&ret->xfs_rtextents, buf) == -1)
        goto error;
      free (buf);
    }
  }

  if (ret->xfs_mntpoint == NULL) {
    ret->xfs_mntpoint = strdup ("");
    if (ret->xfs_mntpoint == NULL) goto error;
  }
  if (ret->xfs_logname == NULL) {
    ret->xfs_logname = strdup ("");
    if (ret->xfs_logname == NULL) goto error;
  }
  if (ret->xfs_rtname == NULL) {
    ret->xfs_rtname = strdup ("");
    if (ret->xfs_rtname == NULL) goto error;
  }

  return ret;

error:
  free (buf);
  free (ret->xfs_mntpoint);
  free (ret->xfs_logname);
  free (ret->xfs_rtname);
  free (ret);
  return NULL;
}

guestfs_int_xfsinfo *
do_xfs_info (const char *path)
{
  int r;
  char *buf;
  char *out = NULL, *err = NULL;
  char **lines = NULL;
  guestfs_int_xfsinfo *ret = NULL;

  if (do_is_dir (path)) {
    buf = sysroot_path (path);
    if (!buf) {
      reply_with_perror ("malloc");
      return NULL;
    }
  } else {
    buf = strdup(path);
    if (!buf) {
      reply_with_perror ("strdup");
      return NULL;
    }
  }

  r = command (&out, &err, "xfs_info", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s", err);
    goto error;
  }

  lines = split_lines (out);
  if (lines == NULL)
    goto error;

  ret = parse_xfs_info (lines);

error:
  free (err);
  free (out);
  if (lines)
    free_strings (lines);
  return ret;
}
