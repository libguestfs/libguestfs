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

/* Again, use the external /bin/umount program, so that /etc/mtab
 * is kept updated.
 */
int
do_umount (const char *pathordevice)
{
  int len, freeit = 0, r;
  char *buf;
  char *err;

  if (strncmp (pathordevice, "/dev/", 5) == 0)
    buf = (char *) pathordevice;
  else {
    len = strlen (pathordevice) + 9;
    freeit = 1;
    buf = malloc (len);
    if (buf == NULL) {
      reply_with_perror ("malloc");
      return -1;
    }
    snprintf (buf, len, "/sysroot%s", pathordevice);
  }

  r = command (NULL, &err, "umount", buf, NULL);
  if (freeit) free (buf);
  if (r == -1) {
    reply_with_error ("umount: %s: %s", pathordevice, err);
    free (err);
    return -1;
  }

  free (err);

  /* update root_mounted? */

  return 0;
}

char **
do_mounts (void)
{
  char *out, *err;
  int r;
  char **ret = NULL;
  int size = 0, alloc = 0;
  char *p, *pend, *p2;

  r = command (&out, &err, "mount", NULL);
  if (r == -1) {
    reply_with_error ("mount: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  p = out;
  while (p) {
    pend = strchr (p, '\n');
    if (pend) {
      *pend = '\0';
      pend++;
    }

    /* Lines have the format:
     *   /dev/foo on /mountpoint type ...
     */
    p2 = strstr (p, " on /sysroot");
    if (p2 != NULL) {
      *p2 = '\0';
      if (add_string (&ret, &size, &alloc, p) == -1) {
	free (out);
	return NULL;
      }
    }

    p = pend;
  }

  free (out);

  if (add_string (&ret, &size, &alloc, NULL) == -1)
    return NULL;

  return ret;
}

/* Only unmount stuff under /sysroot */
int
do_umount_all (void)
{
  char **mounts;
  int i, r;
  char *err;

  mounts = do_mounts ();
  if (mounts == NULL)		/* do_mounts has already replied */
    return -1;

  for (i = 0; mounts[i] != NULL; ++i) {
    r = command (NULL, &err, "umount", mounts[i], NULL);
    if (r == -1) {
      reply_with_error ("umount: %s: %s", mounts[i], err);
      free (err);
      free_strings (mounts);
      return -1;
    }
    free (err);
  }

  free_strings (mounts);
  return 0;
}
