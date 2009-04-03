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

#include "daemon.h"
#include "actions.h"

/* You must mount something on "/" first, hence: */
int root_mounted = 0;

/* The "simple mount" call offers no complex options, you can just
 * mount a device on a mountpoint.
 *
 * It's tempting to try a direct mount(2) syscall, but that doesn't
 * do any autodetection, so we are better off calling out to
 * /bin/mount.
 */

int
do_mount (const char *device, const char *mountpoint)
{
  int len, r, is_root;
  char *mp;
  char *error;

  is_root = strcmp (mountpoint, "/") == 0;

  if (!root_mounted && !is_root) {
    reply_with_error ("mount: you must mount something on / first");
    return -1;
  }

  len = strlen (mountpoint) + 9;

  mp = malloc (len);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  snprintf (mp, len, "/sysroot%s", mountpoint);

  r = command (NULL, &error,
	       "mount", "-o", "sync,noatime", device, mp, NULL);
  if (r == -1) {
    reply_with_error ("mount: %s on %s: %s", device, mountpoint, error);
    free (error);
    return -1;
  }

  if (is_root)
    root_mounted = 1;

  return 0;
}
