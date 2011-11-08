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
#include <dirent.h>
#include <sys/stat.h>

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
  char *out, *err;
  int r;

  r = command (&out, &err, "sfdisk", flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

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
