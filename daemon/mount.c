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
#include <errno.h>
#include <error.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <mntent.h>

#include "daemon.h"
#include "actions.h"

#define MAX_ARGS 64

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
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "setmntent: %s", "/proc/mounts");

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

/* Return true iff 'device' is mounted under /sysroot.
 *   1  : true, device is mounted
 *   0  : false, device is not mounted
 *   -1 : error, reply_with_* has been called
 */
int
is_device_mounted (const char *device)
{
  FILE *fp;
  struct mntent *m;
  struct stat stat1, stat2;

  if (stat (device, &stat1) == -1) {
    reply_with_perror ("stat: %s", device);
    return -1;
  }

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "setmntent: %s", "/proc/mounts");

  while ((m = getmntent (fp)) != NULL) {
    if ((sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) ||
        (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/')) {
      if (stat (m->mnt_fsname, &stat2) == 0) {
        if (stat1.st_rdev == stat2.st_rdev) {
          /* found it */
          endmntent (fp);
          return 1;
        }
      }
    }
  }

  endmntent (fp);
  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_umount (const char *pathordevice,
           int force, int lazyunmount)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *buf = NULL;
  int is_dev;
  const char *argv[MAX_ARGS];
  size_t i = 0;

  is_dev = is_device_parameter (pathordevice);
  buf = is_dev ? strdup (pathordevice)
    : sysroot_path (pathordevice);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (!(optargs_bitmask & GUESTFS_UMOUNT_FORCE_BITMASK))
    force = 0;
  if (!(optargs_bitmask & GUESTFS_UMOUNT_LAZYUNMOUNT_BITMASK))
    lazyunmount = 0;

  /* Use the external /bin/umount program, so that /etc/mtab is kept
   * updated.
   */
  ADD_ARG (argv, i, "umount");

  if (force)
    ADD_ARG (argv, i, "-f");
  if (lazyunmount)
    ADD_ARG (argv, i, "-l");

  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);

  if (r == -1) {
    reply_with_error ("%s: %s", pathordevice, err);
    return -1;
  }

  return 0;
}

/* Implement 'mounts' (mp==0) and 'mountpoints' (mp==1) calls. */
static char **
mounts_or_mountpoints (int mp)
{
  FILE *fp;
  struct mntent *m;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  size_t i;
  int r;

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "setmntent: %s", "/proc/mounts");

  while ((m = getmntent (fp)) != NULL) {
    /* Allow a mount directory like "/sysroot". */
    if (sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) {
      if (add_string (&ret, m->mnt_fsname) == -1) {
      error:
        endmntent (fp);
        return NULL;
      }
      if (mp &&
          add_string (&ret, "/") == -1)
        goto error;
    }
    /* Or allow a mount directory like "/sysroot/...". */
    if (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/') {
      if (add_string (&ret, m->mnt_fsname) == -1)
        goto error;
      if (mp &&
          add_string (&ret, &m->mnt_dir[sysroot_len]) == -1)
        goto error;
    }
  }

  endmntent (fp);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  /* Convert /dev/mapper LV paths into canonical paths (RHBZ#646432). */
  for (i = 0; ret.argv[i] != NULL; i += mp ? 2 : 1) {
    if (STRPREFIX (ret.argv[i], "/dev/mapper/") ||
        STRPREFIX (ret.argv[i], "/dev/dm-")) {
      char *canonical;
      r = lv_canonical (ret.argv[i], &canonical);
      if (r == -1)
        return NULL;
      if (r == 1) {
        free (ret.argv[i]);
        ret.argv[i] = canonical;
      }
      /* Ignore the case where r == 0.  This might happen where
       * eg. a LUKS /dev/mapper device is mounted, but that won't
       * correspond to any LV.
       */
    }
  }

  return take_stringsbuf (&ret);
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
  const int n1 = strlen (*p1);
  const int n2 = strlen (*p2);
  return n2 - n1;
}

int
do_umount_all (void)
{
  FILE *fp;
  struct mntent *m;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (mounts);
  size_t i;
  int r;

  /* This is called from internal_autosync and generally as a cleanup
   * function, and since the umount will definitely fail if any
   * handles are open, we may as well close them.
   */
  aug_finalize ();
  hivex_finalize ();
  journal_finalize ();

  /* NB: Eventually we should aim to parse /proc/self/mountinfo, but
   * that requires custom parsing code.
   */
  fp = setmntent ("/proc/mounts", "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "setmntent: %s", "/proc/mounts");

  while ((m = getmntent (fp)) != NULL) {
    if (verbose) {
      fprintf (stderr, "umount-all: /proc/mounts: fsname=%s dir=%s type=%s opts=%s freq=%d passno=%d\n",
               m->mnt_fsname, m->mnt_dir, m->mnt_type, m->mnt_opts,
               m->mnt_freq, m->mnt_passno);
    }

    /* Allow a mount directory like "/sysroot". */
    if (sysroot_len > 0 && STREQ (m->mnt_dir, sysroot)) {
      if (add_string (&mounts, m->mnt_dir) == -1) {
        endmntent (fp);
        return -1;
      }
    }
    /* Or allow a mount directory like "/sysroot/...". */
    if (STRPREFIX (m->mnt_dir, sysroot) && m->mnt_dir[sysroot_len] == '/') {
      if (add_string (&mounts, m->mnt_dir) == -1) {
        endmntent (fp);
        return -1;
      }
    }
  }

  endmntent (fp);

  if (mounts.size > 0)
    qsort (mounts.argv, mounts.size, sizeof (char *), compare_longest_first);

  /* Unmount them. */
  for (i = 0; i < mounts.size; ++i) {
    CLEANUP_FREE char *err = NULL;

    r = command (NULL, &err, "umount", mounts.argv[i], NULL);
    if (r == -1) {
      reply_with_error ("umount: %s: %s", mounts.argv[i], err);
      return -1;
    }
  }

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
  CLEANUP_FREE char *buf = NULL, *mp = NULL, *error = NULL;

  /* We have to prefix /sysroot on both the filename and the mountpoint. */
  mp = sysroot_path (mountpoint);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  buf = sysroot_path (file);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &error, "mount", "-o", "loop", buf, mp, NULL);
  if (r == -1) {
    reply_with_error ("%s on %s: %s", file, mountpoint, error);
    return -1;
  }

  return 0;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_remount (const char *mountpoint, int rw)
{
  CLEANUP_FREE char *mp = NULL, *err = NULL;
  const char *options;
  int r;

  /* In future we'll allow other flags / parameters to be adjusted.
   * For now we just have to check rw was passed, but in future it
   * will genuinely be an optional argument.
   */
  if (!(optargs_bitmask & GUESTFS_REMOUNT_RW_BITMASK)) {
    reply_with_error ("parameter 'rw' must be specified");
    return -1;
  }
  options = rw ? "remount,rw" : "remount,ro";

  mp = sysroot_path (mountpoint);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* XXX Do we need to check the mountpoint exists? */

  r = command (NULL, &err, "mount", "-o", options, mp, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", mountpoint, options, err);
    return -1;
  }

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

  /* NEED_ROOT (0, return -1); - we don't want this test for this call. */
  ABS_PATH (path, 0, return -1);

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

  /* NEED_ROOT (0, return -1); - we don't want this test for this call. */
  ABS_PATH (path, 0, return -1);

  CHROOT_IN;
  r = rmdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}
