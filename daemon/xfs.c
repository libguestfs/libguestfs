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

#include "c-ctype.h"

#define MAX_ARGS 64

int
optgroup_xfs_available (void)
{
  return prog_exists ("mkfs.xfs");
}

/* Return everything up to the first comma, equals or space in the input
 * string, strdup'ing the return value.
 */
static char *
split_strdup (char *string)
{
  size_t len;
  char *ret;

  len = strcspn (string, " ,=");
  ret = strndup (string, len);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }
  return ret;
}

static int
parse_uint32 (uint32_t *ret, const char *str)
{
  uint32_t r;

  if (sscanf (str, "%" SCNu32, &r) != 1) {
    reply_with_error ("cannot parse numeric field from xfs_info: %s", str);
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
    reply_with_error ("cannot parse numeric field from xfs_info: %s", str);
    return -1;
  }

  *ret = r;
  return 0;
}

/* Typical crazy output from the xfs_info command:
 *
 * meta-data=/dev/sda1              isize=256    agcount=4, agsize=6392 blks
 *          =                       sectsz=512   attr=2
 *[         =                       crc=0                                    ]
 * data     =                       bsize=4096   blocks=25568, imaxpct=25
 *          =                       sunit=0      swidth=0 blks
 * naming   =version 2              bsize=4096   ascii-ci=0
 * log      =internal               bsize=4096   blocks=1200, version=2
 *          =                       sectsz=512   sunit=0 blks, lazy-count=1
 * realtime =none                   extsz=4096   blocks=0, rtextents=0
 *
 * [...] line only appears in Fedora >= 21
 *
 * We may need to revisit this parsing code if the output changes
 * in future.
 */
static guestfs_int_xfsinfo *
parse_xfs_info (char **lines)
{
  guestfs_int_xfsinfo *ret;
  CLEANUP_FREE char *section = NULL; /* first column, eg "meta-data", "data" */
  char *p;
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
    if (verbose)
      fprintf (stderr, "xfs_info: lines[%zu] = \'%s\'\n", i, lines[i]);

    if (c_isalpha (lines[i][0])) {
      free (section);
      section = split_strdup (lines[i]);
      if (!section) goto error;

      if (verbose)
	fprintf (stderr, "xfs_info: new section %s\n", section);
    }

    if ((p = strstr (lines[i], "meta-data="))) {
      ret->xfs_mntpoint = split_strdup (p + 10);
      if (ret->xfs_mntpoint == NULL) goto error;
    }
    if ((p = strstr (lines[i], "isize="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 6);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_inodesize, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "agcount="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_agcount, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "agsize="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_agsize, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "sectsz="))) {
      if (section) {
	CLEANUP_FREE char *buf = split_strdup (p + 7);
	if (buf == NULL) goto error;
	if (STREQ (section, "meta-data")) {
	  if (parse_uint32 (&ret->xfs_sectsize, buf) == -1)
	    goto error;
	} else if (STREQ (section, "log")) {
	  if (parse_uint32 (&ret->xfs_logsectsize, buf) == -1)
	    goto error;
	}
      }
    }
    if ((p = strstr (lines[i], "attr="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 5);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_attr, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "bsize="))) {
      if (section) {
	CLEANUP_FREE char *buf = split_strdup (p + 6);
	if (buf == NULL) goto error;
	if (STREQ (section, "data")) {
	  if (parse_uint32 (&ret->xfs_blocksize, buf) == -1)
	    goto error;
	} else if (STREQ (section, "naming")) {
	  if (parse_uint32 (&ret->xfs_dirblocksize, buf) == -1)
	    goto error;
	} else if (STREQ (section, "log")) {
	  if (parse_uint32 (&ret->xfs_logblocksize, buf) == -1)
	    goto error;
	}
      }
    }
    if ((p = strstr (lines[i], "blocks="))) {
      if (section) {
	CLEANUP_FREE char *buf = split_strdup (p + 7);
	if (buf == NULL) goto error;
	if (STREQ (section, "data")) {
	  if (parse_uint64 (&ret->xfs_datablocks, buf) == -1)
	    goto error;
	} else if (STREQ (section, "log")) {
	  if (parse_uint32 (&ret->xfs_logblocks, buf) == -1)
	    goto error;
	} else if (STREQ (section, "realtime")) {
	  if (parse_uint64 (&ret->xfs_rtblocks, buf) == -1)
	    goto error;
	}
      }
    }
    if ((p = strstr (lines[i], "imaxpct="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_imaxpct, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "sunit="))) {
      if (section) {
	CLEANUP_FREE char *buf = split_strdup (p + 6);
	if (buf == NULL) goto error;
	if (STREQ (section, "data")) {
	  if (parse_uint32 (&ret->xfs_sunit, buf) == -1)
	    goto error;
	} else if (STREQ (section, "log")) {
	  if (parse_uint32 (&ret->xfs_logsunit, buf) == -1)
	    goto error;
	}
      }
    }
    if ((p = strstr (lines[i], "swidth="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 7);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_swidth, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "naming   =version "))) {
      CLEANUP_FREE char *buf = split_strdup (p + 18);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_dirversion, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "ascii-ci="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 9);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_cimode, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "log      ="))) {
      ret->xfs_logname = split_strdup (p + 10);
      if (ret->xfs_logname == NULL) goto error;
    }
    if ((p = strstr (lines[i], "version="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 8);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_logversion, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "lazy-count="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 11);
      if (buf == NULL) goto error;
      if (parse_uint32 (&ret->xfs_lazycount, buf) == -1)
        goto error;
    }
    if ((p = strstr (lines[i], "realtime ="))) {
      ret->xfs_rtname = split_strdup (p + 10);
      if (ret->xfs_rtname == NULL) goto error;
    }
    if ((p = strstr (lines[i], "rtextents="))) {
      CLEANUP_FREE char *buf = split_strdup (p + 10);
      if (buf == NULL) goto error;
      if (parse_uint64 (&ret->xfs_rtextents, buf) == -1)
        goto error;
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
  free (ret->xfs_mntpoint);
  free (ret->xfs_logname);
  free (ret->xfs_rtname);
  free (ret);
  return NULL;
}

guestfs_int_xfsinfo *
do_xfs_info (const char *pathordevice)
{
  int r;
  CLEANUP_FREE char *buf = NULL;
  CLEANUP_FREE char *out = NULL, *err = NULL;
  CLEANUP_FREE_STRING_LIST char **lines = NULL;
  int is_dev;

  is_dev = is_device_parameter (pathordevice);
  buf = is_dev ? strdup (pathordevice)
               : sysroot_path (pathordevice);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "xfs_info", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  lines = split_lines (out);
  if (lines == NULL)
    return NULL;

  return parse_xfs_info (lines);
}

int
do_xfs_growfs (const char *path,
               int datasec, int logsec, int rtsec,
               int64_t datasize, int64_t logsize, int64_t rtsize,
               int64_t rtextsize, int32_t maxpct)
{
  int r;
  CLEANUP_FREE char *buf = NULL, *err = NULL;
  const char *argv[MAX_ARGS];
  char datasize_s[64];
  char logsize_s[64];
  char rtsize_s[64];
  char rtextsize_s[64];
  char maxpct_s[32];
  size_t i = 0;

  buf = sysroot_path (path);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  ADD_ARG (argv, i, "xfs_growfs");

  /* Optional arguments */
  if (!(optargs_bitmask & GUESTFS_XFS_GROWFS_DATASEC_BITMASK))
    datasec = 0;
  if (!(optargs_bitmask & GUESTFS_XFS_GROWFS_LOGSEC_BITMASK))
    logsec = 0;
  if (!(optargs_bitmask & GUESTFS_XFS_GROWFS_RTSEC_BITMASK))
    rtsec = 0;

  if (datasec)
    ADD_ARG (argv, i, "-d");
  if (logsec)
    ADD_ARG (argv, i, "-l");
  if (rtsec)
    ADD_ARG (argv, i, "-r");

  if (optargs_bitmask & GUESTFS_XFS_GROWFS_DATASIZE_BITMASK) {
    if (datasize < 0) {
      reply_with_error ("datasize must be >= 0");
      return -1;
    }
    snprintf (datasize_s, sizeof datasize_s, "%" PRIi64, datasize);
    ADD_ARG (argv, i, "-D");
    ADD_ARG (argv, i, datasize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_GROWFS_LOGSIZE_BITMASK) {
    if (logsize < 0) {
      reply_with_error ("logsize must be >= 0");
      return -1;
    }
    snprintf (logsize_s, sizeof logsize_s, "%" PRIi64, logsize);
    ADD_ARG (argv, i, "-L");
    ADD_ARG (argv, i, logsize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_GROWFS_RTSIZE_BITMASK) {
    if (rtsize < 0) {
      reply_with_error ("rtsize must be >= 0");
      return -1;
    }
    snprintf (rtsize_s, sizeof rtsize_s, "%" PRIi64, rtsize);
    ADD_ARG (argv, i, "-R");
    ADD_ARG (argv, i, rtsize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_GROWFS_RTEXTSIZE_BITMASK) {
    if (rtextsize < 0) {
      reply_with_error ("rtextsize must be >= 0");
      return -1;
    }
    snprintf (rtextsize_s, sizeof rtextsize_s, "%" PRIi64, rtextsize);
    ADD_ARG (argv, i, "-e");
    ADD_ARG (argv, i, rtextsize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_GROWFS_MAXPCT_BITMASK) {
    if (maxpct < 0) {
      reply_with_error ("maxpct must be >= 0");
      return -1;
    }
    snprintf (maxpct_s, sizeof maxpct_s, "%" PRIi32, maxpct);
    ADD_ARG (argv, i, "-m");
    ADD_ARG (argv, i, maxpct_s);
  }

  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  return 0;
}

int
xfs_set_uuid (const char *device, const char *uuid)
{
  optargs_bitmask = GUESTFS_XFS_ADMIN_UUID_BITMASK;
  return do_xfs_admin (device, 0, 0, 0, 0, 0, NULL, uuid);
}

int
xfs_set_uuid_random (const char *device)
{
  optargs_bitmask = GUESTFS_XFS_ADMIN_UUID_BITMASK;
  return do_xfs_admin (device, 0, 0, 0, 0, 0, NULL, "generate");
}

int
xfs_set_label (const char *device, const char *label)
{
  optargs_bitmask = GUESTFS_XFS_ADMIN_LABEL_BITMASK;
  return do_xfs_admin (device, 0, 0, 0, 0, 0, label, NULL);
}

int
do_xfs_admin (const char *device,
              int extunwritten, int imgfile, int v2log,
              int projid32bit,
              int lazycounter, const char *label, const char *uuid)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  const char *argv[MAX_ARGS];
  size_t i = 0;

  ADD_ARG (argv, i, "xfs_admin");

  /* Optional arguments */
  if (!(optargs_bitmask & GUESTFS_XFS_ADMIN_EXTUNWRITTEN_BITMASK))
    extunwritten = 0;
  if (!(optargs_bitmask & GUESTFS_XFS_ADMIN_IMGFILE_BITMASK))
    imgfile = 0;
  if (!(optargs_bitmask & GUESTFS_XFS_ADMIN_V2LOG_BITMASK))
    v2log = 0;
  if (!(optargs_bitmask & GUESTFS_XFS_ADMIN_PROJID32BIT_BITMASK))
    projid32bit = 0;

  if (extunwritten)
    ADD_ARG (argv, i, "-e");
  if (imgfile)
    ADD_ARG (argv, i, "-f");
  if (v2log)
    ADD_ARG (argv, i, "-j");
  if (projid32bit)
    ADD_ARG (argv, i, "-p");

  if (optargs_bitmask & GUESTFS_XFS_ADMIN_LAZYCOUNTER_BITMASK) {
    if (lazycounter) {
      ADD_ARG (argv, i, "-c");
      ADD_ARG (argv, i, "1");
    } else {
      ADD_ARG (argv, i, "-c");
      ADD_ARG (argv, i, "0");
    }
  }

  if (optargs_bitmask & GUESTFS_XFS_ADMIN_LABEL_BITMASK) {
    if (strlen (label) > XFS_LABEL_MAX) {
      reply_with_error ("%s: xfs labels are limited to %d bytes",
                        label, XFS_LABEL_MAX);
      return -1;
    }

    ADD_ARG (argv, i, "-L");
    ADD_ARG (argv, i, label);
  }

  if (optargs_bitmask & GUESTFS_XFS_ADMIN_UUID_BITMASK) {
    ADD_ARG (argv, i, "-U");
    ADD_ARG (argv, i, uuid);
  }

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandvf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_xfs_repair (const char *device,
               int forcelogzero, int nomodify,
               int noprefetch, int forcegeometry,
               int64_t maxmem, int64_t ihashsize,
               int64_t bhashsize, int64_t agstride,
               const char *logdev, const char *rtdev)
{
  int r;
  CLEANUP_FREE char *err = NULL, *buf = NULL;
  const char *argv[MAX_ARGS];
  char maxmem_s[64];
  char ihashsize_s[70];
  char bhashsize_s[70];
  char agstride_s[74];
  size_t i = 0;
  int is_device;

  ADD_ARG (argv, i, "xfs_repair");

  /* Optional arguments */
  if (optargs_bitmask & GUESTFS_XFS_REPAIR_FORCELOGZERO_BITMASK) {
    if (forcelogzero)
      ADD_ARG (argv, i, "-L");
  }
  if (optargs_bitmask & GUESTFS_XFS_REPAIR_NOMODIFY_BITMASK) {
    if (nomodify)
      ADD_ARG (argv, i, "-n");
  }
  if (optargs_bitmask & GUESTFS_XFS_REPAIR_NOPREFETCH_BITMASK) {
    if (noprefetch)
      ADD_ARG (argv, i, "-P");
  }
  if (optargs_bitmask & GUESTFS_XFS_REPAIR_FORCEGEOMETRY_BITMASK) {
    if (forcegeometry) {
      ADD_ARG (argv, i, "-o");
      ADD_ARG (argv, i, "force_geometry");
    }
  }

  if (optargs_bitmask & GUESTFS_XFS_REPAIR_MAXMEM_BITMASK) {
    if (maxmem < 0) {
      reply_with_error ("maxmem must be >= 0");
      return -1;
    }
    snprintf (maxmem_s, sizeof maxmem_s, "%" PRIi64, maxmem);
    ADD_ARG (argv, i, "-m");
    ADD_ARG (argv, i, maxmem_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_REPAIR_IHASHSIZE_BITMASK) {
    if (ihashsize < 0) {
      reply_with_error ("ihashsize must be >= 0");
      return -1;
    }
    snprintf (ihashsize_s, sizeof ihashsize_s, "ihash=" "%" PRIi64, ihashsize);
    ADD_ARG (argv, i, "-o");
    ADD_ARG (argv, i, ihashsize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_REPAIR_BHASHSIZE_BITMASK) {
    if (bhashsize < 0) {
      reply_with_error ("bhashsize must be >= 0");
      return -1;
    }
    snprintf (bhashsize_s, sizeof bhashsize_s, "bhash=" "%" PRIi64, bhashsize);
    ADD_ARG (argv, i, "-o");
    ADD_ARG (argv, i, bhashsize_s);
  }

  if (optargs_bitmask & GUESTFS_XFS_REPAIR_AGSTRIDE_BITMASK) {
    if (agstride < 0) {
      reply_with_error ("agstride must be >= 0");
      return -1;
    }
    snprintf (agstride_s, sizeof agstride_s, "ag_stride=" "%" PRIi64, agstride);
    ADD_ARG (argv, i, "-o");
    ADD_ARG (argv, i, agstride_s);
  }


  if (optargs_bitmask & GUESTFS_XFS_REPAIR_LOGDEV_BITMASK) {
    ADD_ARG (argv, i, "-l");
    ADD_ARG (argv, i, logdev);
  }

  if (optargs_bitmask & GUESTFS_XFS_REPAIR_RTDEV_BITMASK) {
    ADD_ARG (argv, i, "-r");
    ADD_ARG (argv, i, rtdev);
  }

  is_device = is_device_parameter (device);
  if (!is_device) {
    buf = sysroot_path (device);
    if (buf == NULL) {
      reply_with_perror ("malloc");
      return -1;
    }
    ADD_ARG (argv, i, "-f");
    ADD_ARG (argv, i, buf);
  } else {
    ADD_ARG (argv, i, device);
  }

  ADD_ARG (argv, i, NULL);

  r = commandrv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return r;
}

int64_t
xfs_minimum_size (const char *path)
{
  CLEANUP_FREE_XFSINFO struct guestfs_int_xfsinfo *info = do_xfs_info (path);

  if (info == NULL)
    return -1;

  // XFS does not support shrinking.
  if (INT64_MAX / info->xfs_blocksize < info->xfs_datablocks) {
    reply_with_error ("filesystem size too big: overflow");
    return -1;
  }
  return info->xfs_blocksize * info->xfs_datablocks;
}
