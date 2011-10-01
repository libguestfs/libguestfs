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
#include <mntent.h>

#include "daemon.h"
#include "actions.h"

/* You must mount something on "/" first before many operations.
 * Hence we have an internal function which can test if something is
 * mounted on *or under* the sysroot directory.  (It has to be *or
 * under* because of mkmountpoint and friends).
 */
int
is_root_mounted (void)
{
  FILE *fp;
  struct mntent *m;

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL) {
    perror ("/proc/mounts");
    exit (EXIT_FAILURE);
  }

  while ((m = getmntent (fp)) != NULL) {
    /* Allow a mount directory like "/sysroot". */
    if (sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) {
    gotit:
      endmntent (fp);
      return 1;
    }
    /* Or allow a mount directory like "/sysroot/...". */
    if (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/')
      goto gotit;
  }

  endmntent (fp);
  return 0;
}

/* The "simple mount" call offers no complex options, you can just
 * mount a device on a mountpoint.  The variations like mount_ro,
 * mount_options and mount_vfs let you set progressively more things.
 *
 * It's tempting to try a direct mount(2) syscall, but that doesn't
 * do any autodetection, so we are better off calling out to
 * /bin/mount.
 */

int
do_mount_vfs (const char *options, const char *vfstype,
              const char *device, const char *mountpoint)
{
  int r;
  char *mp;
  char *error;
  struct stat statbuf;

  ABS_PATH (mountpoint, , return -1);

  mp = sysroot_path (mountpoint);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Check the mountpoint exists and is a directory. */
  if (stat (mp, &statbuf) == -1) {
    reply_with_perror ("mount: %s", mountpoint);
    free (mp);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_perror ("mount: %s: mount point is not a directory", mountpoint);
    free (mp);
    return -1;
  }

  if (vfstype)
    r = command (NULL, &error,
                 "mount", "-o", options, "-t", vfstype, device, mp, NULL);
  else
    r = command (NULL, &error,
                 "mount", "-o", options, device, mp, NULL);
  free (mp);
  if (r == -1) {
    reply_with_error ("%s on %s: %s", device, mountpoint, error);
    free (error);
    return -1;
  }

  free (error);
  return 0;
}

int
do_mount (const char *device, const char *mountpoint)
{
  return do_mount_vfs ("", NULL, device, mountpoint);
}

int
do_mount_ro (const char *device, const char *mountpoint)
{
  return do_mount_vfs ("ro", NULL, device, mountpoint);
}

int
do_mount_options (const char *options, const char *device,
                  const char *mountpoint)
{
  return do_mount_vfs (options, NULL, device, mountpoint);
}

/* Again, use the external /bin/umount program, so that /etc/mtab
 * is kept updated.
 */
int
do_umount (const char *pathordevice)
{
  int r;
  char *err;
  char *buf;
  int is_dev;

  is_dev = STREQLEN (pathordevice, "/dev/", 5);
  buf = is_dev ? strdup (pathordevice)
               : sysroot_path (pathordevice);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (is_dev)
    RESOLVE_DEVICE (buf, , { free (buf); return -1; });

  r = command (NULL, &err, "umount", buf, NULL);
  free (buf);

  if (r == -1) {
    reply_with_error ("%s: %s", pathordevice, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

/* Implement 'mounts' (mp==0) and 'mountpoints' (mp==1) calls. */
static char **
mounts_or_mountpoints (int mp)
{
  FILE *fp;
  struct mntent *m;
  char **ret = NULL;
  int size = 0, alloc = 0;
  size_t i;
  int r;

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL) {
    perror ("/proc/mounts");
    exit (EXIT_FAILURE);
  }

  while ((m = getmntent (fp)) != NULL) {
    /* Allow a mount directory like "/sysroot". */
    if (sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) {
      if (add_string (&ret, &size, &alloc, m->mnt_fsname) == -1) {
      error:
        endmntent (fp);
        return NULL;
      }
      if (mp &&
          add_string (&ret, &size, &alloc, "/") == -1)
        goto error;
    }
    /* Or allow a mount directory like "/sysroot/...". */
    if (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/') {
      if (add_string (&ret, &size, &alloc, m->mnt_fsname) == -1)
        goto error;
      if (mp &&
          add_string (&ret, &size, &alloc, &m->mnt_dir[sysroot_len]) == -1)
        goto error;
    }
  }

  endmntent (fp);

  if (add_string (&ret, &size, &alloc, NULL) == -1)
    return NULL;

  /* Convert /dev/mapper LV paths into canonical paths (RHBZ#646432). */
  for (i = 0; ret[i] != NULL; i += mp ? 2 : 1) {
    if (STRPREFIX (ret[i], "/dev/mapper/") || STRPREFIX (ret[i], "/dev/dm-")) {
      char *canonical;
      r = lv_canonical (ret[i], &canonical);
      if (r == -1) {
        free_strings (ret);
        return NULL;
      }
      if (r == 1) {
        free (ret[i]);
        ret[i] = canonical;
      }
      /* Ignore the case where r == 0.  This might happen where
       * eg. a LUKS /dev/mapper device is mounted, but that won't
       * correspond to any LV.
       */
    }
  }

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
  FILE *fp;
  struct mntent *m;
  char **mounts = NULL;
  int size = 0, alloc = 0;
  char *err;
  int i, r;

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL) {
    perror ("/proc/mounts");
    exit (EXIT_FAILURE);
  }

  while ((m = getmntent (fp)) != NULL) {
    /* Allow a mount directory like "/sysroot". */
    if (sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) {
      if (add_string (&mounts, &size, &alloc, m->mnt_dir) == -1) {
        endmntent (fp);
        return -1;
      }
    }
    /* Or allow a mount directory like "/sysroot/...". */
    if (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/') {
      if (add_string (&mounts, &size, &alloc, m->mnt_dir) == -1) {
        endmntent (fp);
        return -1;
      }
    }
  }

  endmntent (fp);

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

  return 0;
}

/* Mount using the loopback device.  You can't use the generic
 * do_mount call for this because the first parameter isn't a
 * device.
 */
int
do_mount_loop (const char *file, const char *mountpoint)
{
  int r;
  char *buf, *mp;
  char *error;

  /* We have to prefix /sysroot on both the filename and the mountpoint. */
  mp = sysroot_path (mountpoint);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  buf = sysroot_path (file);
  if (!buf) {
    reply_with_perror ("malloc");
    free (mp);
    return -1;
  }

  r = command (NULL, &error, "mount", "-o", "loop", buf, mp, NULL);
  free (mp);
  free (buf);
  if (r == -1) {
    reply_with_error ("%s on %s: %s", file, mountpoint, error);
    free (error);
    return -1;
  }

  free (error);
  return 0;
}

/* Specialized calls mkmountpoint and rmmountpoint are really
 * variations on mkdir and rmdir which do no checking of the
 * is_root_mounted() flag.
 */
int
do_mkmountpoint (const char *path)
{
  int r;

  /* NEED_ROOT (return -1); - we don't want this test for this call. */
  ABS_PATH (path, , return -1);

  CHROOT_IN;
  r = mkdir (path, 0777);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

int
do_rmmountpoint (const char *path)
{
  int r;

  /* NEED_ROOT (return -1); - we don't want this test for this call. */
  ABS_PATH (path, , return -1);

  CHROOT_IN;
  r = rmdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}
