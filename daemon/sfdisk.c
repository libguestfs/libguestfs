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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

static int
sfdisk (char *device, int n, int cyls, int heads, int sectors,
        const char *extra_flag,
        char * const* const lines)
{
  FILE *fp;
  char buf[256];
  int i;

  RESOLVE_DEVICE (device, return -1);

  strcpy (buf, "/sbin/sfdisk");

  if (n > 0)
    sprintf (buf + strlen (buf), " -N %d", n);
  if (cyls)
    sprintf (buf + strlen (buf), " -C %d", cyls);
  if (heads)
    sprintf (buf + strlen (buf), " -H %d", heads);
  if (sectors)
    sprintf (buf + strlen (buf), " -S %d", sectors);
  if (extra_flag)
    sprintf (buf + strlen (buf), " %s", extra_flag);

  /* Safe because of IS_DEVICE above: */
  sprintf (buf + strlen (buf), " %s", device);

  if (verbose)
    printf ("%s\n", buf);

  fp = popen (buf, "w");
  if (fp == NULL) {
    reply_with_perror (buf);
    return -1;
  }

  for (i = 0; lines[i] != NULL; ++i) {
    if (fprintf (fp, "%s\n", lines[i]) < 0) {
      reply_with_perror (buf);
      pclose (fp);
      return -1;
    }
  }

  if (pclose (fp) != 0) {
    reply_with_error ("%s: external command failed", buf);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_sfdisk (char *device, int cyls, int heads, int sectors,
           char **lines)
{
  return sfdisk (device, 0, cyls, heads, sectors, NULL, lines);
}

int
do_sfdisk_N (char *device, int n, int cyls, int heads, int sectors,
             char *line)
{
  const char *lines[2] = { line, NULL };

  return sfdisk (device, n, cyls, heads, sectors, NULL, lines);
}

int
do_sfdiskM (char *device, char **lines)
{
  return sfdisk (device, 0, 0, 0, 0, "-uM", lines);
}

static char *
sfdisk_flag (char *device, const char *flag)
{
  char *out, *err;
  int r;

  RESOLVE_DEVICE (device, return NULL);

  r = command (&out, &err, "/sbin/sfdisk", flag, device, NULL);
  if (r == -1) {
    reply_with_error ("sfdisk: %s: %s", device, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  udev_settle ();

  return out;			/* caller frees */
}

char *
do_sfdisk_l (char *device)
{
  return sfdisk_flag (device, "-l");
}

char *
do_sfdisk_kernel_geometry (char *device)
{
  return sfdisk_flag (device, "-g");
}

char *
do_sfdisk_disk_geometry (char *device)
{
  return sfdisk_flag (device, "-G");
}
