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
