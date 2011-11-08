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
#include <sys/stat.h>
#include <sys/types.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_rmdir (const char *path)
{
  int r;

  CHROOT_IN;
  r = rmdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

/* This implementation is quick and dirty, and allows people to try
 * to remove parts of the initramfs (eg. "rm -r /..") but if people
 * do stupid stuff, who are we to try to stop them?
 */
int
do_rm_rf (const char *path)
{
  int r;
  char *buf, *err;

  if (STREQ (path, "/")) {
    reply_with_error ("cannot remove root directory");
    return -1;
  }

  buf = sysroot_path (path);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "rm", "-rf", buf, NULL);
  free (buf);

  /* rm -rf is never supposed to fail.  I/O errors perhaps? */
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_mkdir (const char *path)
{
  int r;

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
do_mkdir_mode (const char *path, int mode)
{
  int r;

  if (mode < 0) {
    reply_with_error ("%s: mode is negative", path);
    return -1;
  }

  CHROOT_IN;
  r = mkdir (path, mode);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

/* Returns:
 * 0  if everything was OK,
 * -1 for a general error (sets errno),
 * -2 if an existing path element was not a directory.
 */
static int
recursive_mkdir (const char *path)
{
  int loop = 0;
  int r;
  char *ppath, *p;
  struct stat buf;

 again:
  r = mkdir (path, 0777);
  if (r == -1) {
    if (errno == EEXIST) {	/* Something exists here, might not be a dir. */
      r = lstat (path, &buf);
      if (r == -1) return -1;
      if (!S_ISDIR (buf.st_mode)) return -2;
      return 0;			/* OK - directory exists here already. */
    }

    if (!loop && errno == ENOENT) {
      loop = 1;			/* Stops it looping forever. */

      /* If we're at the root, and we failed, just give up. */
      if (path[0] == '/' && path[1] == '\0') return -1;

      /* Try to make the parent directory first. */
      ppath = strdup (path);
      if (ppath == NULL) return -1;

      p = strrchr (ppath, '/');
      if (p) *p = '\0';

      r = recursive_mkdir (ppath);
      free (ppath);

      if (r != 0) return r;

      goto again;
    } else	  /* Failed for some other reason, so return error. */
      return -1;
  }
  return 0;
}

int
do_mkdir_p (const char *path)
{
  int r;

  CHROOT_IN;
  r = recursive_mkdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }
  if (r == -2) {
    reply_with_error ("%s: a path element was not a directory", path);
    return -1;
  }

  return 0;
}

char *
do_mkdtemp (const char *template)
{
  char *writable = strdup (template);
  if (writable == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  CHROOT_IN;
  char *r = mkdtemp (writable);
  CHROOT_OUT;

  if (r == NULL) {
    reply_with_perror ("%s", template);
    free (writable);
  }

  return r;
}
