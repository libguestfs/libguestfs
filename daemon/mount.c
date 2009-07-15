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
#include <sys/stat.h>
#include <sys/types.h>

#include "daemon.h"
#include "actions.h"

/* You must mount something on "/" first, hence: */
int root_mounted = 0;

/* The "simple mount" call offers no complex options, you can just
 * mount a device on a mountpoint.  The variations like mount_ro,
 * mount_options and mount_vfs let you set progressively more things.
 *
 * It's tempting to try a direct mount(2) syscall, but that doesn't
 * do any autodetection, so we are better off calling out to
 * /bin/mount.
 */

int
do_mount_vfs (char *options, char *vfstype,
	      char *device, char *mountpoint)
{
  int len, r, is_root;
  char *mp;
  char *error;

  IS_DEVICE (device, -1);

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

  if (vfstype)
    r = command (NULL, &error,
		 "mount", "-o", options, "-t", vfstype, device, mp, NULL);
  else
    r = command (NULL, &error,
		 "mount", "-o", options, device, mp, NULL);
  free (mp);
  if (r == -1) {
    reply_with_error ("mount: %s on %s: %s", device, mountpoint, error);
    free (error);
    return -1;
  }

  if (is_root)
    root_mounted = 1;

  return 0;
}

int
do_mount (char *device, char *mountpoint)
{
  return do_mount_vfs ("sync,noatime", NULL, device, mountpoint);
}

int
do_mount_ro (char *device, char *mountpoint)
{
  return do_mount_vfs ("ro", NULL, device, mountpoint);
}

int
do_mount_options (char *options, char *device,
		  char *mountpoint)
{
  return do_mount_vfs (options, NULL, device, mountpoint);
}

/* Again, use the external /bin/umount program, so that /etc/mtab
 * is kept updated.
 */
int
do_umount (char *pathordevice)
{
  int len, freeit = 0, r;
  char *buf;
  char *err;

  if (strncmp (pathordevice, "/dev/", 5) == 0) {
    buf = pathordevice;
    IS_DEVICE (buf, -1);
  } else {
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

static char **
mounts_or_mountpoints (int mp)
{
  char *out, *err;
  int r;
  char **ret = NULL;
  int size = 0, alloc = 0;
  char *p, *pend, *p2;
  int len;

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
      if (mp) {
	p2 += 12;		/* skip " on /sysroot" */
	len = strcspn (p2, " ");

	if (len == 0)		/* .. just /sysroot, so we turn it into "/" */
	  p2 = (char *) "/";
	else
	  p2[len] = '\0';

	if (add_string (&ret, &size, &alloc, p2) == -1) {
	  free (out);
	  return NULL;
	}
      }
    }

    p = pend;
  }

  free (out);

  if (add_string (&ret, &size, &alloc, NULL) == -1)
    return NULL;

  return ret;
}

char **
do_mounts (void)
{
  return mounts_or_mountpoints (0);
}

char **
do_mountpoints (void)
{
  return mounts_or_mountpoints (1);
}

/* Unmount everything mounted under /sysroot.
 *
 * We have to unmount in the correct order, so we sort the paths by
 * longest first to ensure that child paths are unmounted by parent
 * paths.
 *
 * This call is more important than it appears at first, because it
 * is widely used by both test and production code in order to
 * get back to a known state (nothing mounted, everything synchronized).
 */
static int
compare_longest_first (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  int n1 = strlen (*p1);
  int n2 = strlen (*p2);
  return n2 - n1;
}

int
do_umount_all (void)
{
  char *out, *err;
  int i, r;
  char **mounts = NULL;
  int size = 0, alloc = 0;
  char *p, *p2, *p3, *pend;

  r = command (&out, &err, "mount", NULL);
  if (r == -1) {
    reply_with_error ("mount: %s", err);
    free (out);
    free (err);
    return -1;
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
      p2 += 4;
      p3 = p2 + strcspn (p2, " ");
      *p3 = '\0';
      if (add_string (&mounts, &size, &alloc, p2) == -1) {
	free (out);
	return -1;
      }
    }

    p = pend;
  }
  free (out);

  qsort (mounts, size, sizeof (char *), compare_longest_first);

  /* Unmount them. */
  for (i = 0; i < size; ++i) {
    r = command (NULL, &err, "umount", mounts[i], NULL);
    if (r == -1) {
      reply_with_error ("umount: %s: %s", mounts[i], err);
      free (err);
      free_stringslen (mounts, size);
      return -1;
    }
    free (err);
  }

  free_stringslen (mounts, size);

  /* We've unmounted root now, so ... */
  root_mounted = 0;

  return 0;
}

/* Mount using the loopback device.  You can't use the generic
 * do_mount call for this because the first parameter isn't a
 * device.
 */
int
do_mount_loop (char *file, char *mountpoint)
{
  int len, r;
  char *buf, *mp;
  char *error;

  NEED_ROOT (-1);
  ABS_PATH (file, -1);

  /* We have to prefix /sysroot on both the filename and the mountpoint. */
  len = strlen (mountpoint) + 9;
  mp = malloc (len);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }
  snprintf (mp, len, "/sysroot%s", mountpoint);

  len = strlen (file) + 9;
  buf = malloc (len);
  if (!file) {
    reply_with_perror ("malloc");
    free (mp);
    return -1;
  }
  snprintf (buf, len, "/sysroot%s", file);

  r = command (NULL, &error, "mount", "-o", "loop", buf, mp, NULL);
  free (mp);
  free (buf);
  if (r == -1) {
    reply_with_error ("mount: %s on %s: %s", file, mountpoint, error);
    free (error);
    return -1;
  }

  return 0;
}

/* Specialized calls mkmountpoint and rmmountpoint are really
 * variations on mkdir and rmdir which do no checking and (in the
 * mkmountpoint case) set the root_mounted flag.
 */
int
do_mkmountpoint (char *path)
{
  int r;

  /* NEED_ROOT (-1); - we don't want this test for this call. */
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = mkdir (path, 0777);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("mkmountpoint: %s", path);
    return -1;
  }

  /* Set the flag so that filesystems can be mounted here,
   * not just on /sysroot.
   */
  root_mounted = 1;

  return 0;
}

int
do_rmmountpoint (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = rmdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("rmmountpoint: %s", path);
    return -1;
  }

  return 0;
}
