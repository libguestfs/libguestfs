/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2010 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_ntfs3g_available (void)
{
  return prog_exists ("ntfs-3g.probe");
}

int
optgroup_ntfsprogs_available (void)
{
  return prog_exists ("ntfsresize");
}

int
do_ntfs_3g_probe (int rw, const char *device)
{
  char *err;
  int r;
  const char *rw_flag;

  rw_flag = rw ? "-w" : "-r";

  r = commandr (NULL, &err, "ntfs-3g.probe", rw_flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  return r;
}

int
do_ntfsresize (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err, "ntfsresize", "-P", device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  return 0;
}

int
do_ntfsresize_size (const char *device, int64_t size)
{
  char *err;
  int r;

  char buf[32];
  snprintf (buf, sizeof buf, "%" PRIi64, size);

  r = command (NULL, &err, "ntfsresize", "-P", "--size", buf,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  return 0;
}
