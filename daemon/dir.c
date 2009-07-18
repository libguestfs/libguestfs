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

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_rmdir (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = rmdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("rmdir: %s", path);
    return -1;
  }

  return 0;
}

/* This implementation is quick and dirty, and allows people to try
 * to remove parts of the initramfs (eg. "rm -r /..") but if people
 * do stupid stuff, who are we to try to stop them?
 */
int
do_rm_rf (char *path)
{
  int r;
  char *buf, *err;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  if (strcmp (path, "/") == 0) {
    reply_with_error ("rm -rf: cannot remove root directory");
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
    reply_with_error ("rm -rf: %s: %s", path, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_mkdir (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = mkdir (path, 0777);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("mkdir: %s", path);
    return -1;
  }

  return 0;
}

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
      if (!S_ISDIR (buf.st_mode)) {
	errno = ENOTDIR;
	return -1;
      }
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

      if (r == -1) return -1;

      goto again;
    } else	  /* Failed for some other reason, so return error. */
      return -1;
  }
  return 0;
}

int
do_mkdir_p (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = recursive_mkdir (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("mkdir -p: %s", path);
    return -1;
  }

  return 0;
}

int
do_is_dir (char *path)
{
  int r;
  struct stat buf;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = lstat (path, &buf);
  CHROOT_OUT;

  if (r == -1) {
    if (errno != ENOENT && errno != ENOTDIR) {
      reply_with_perror ("stat: %s", path);
      return -1;
    }
    else
      return 0;			/* Not a directory. */
  }

  return S_ISDIR (buf.st_mode);
}

char *
do_mkdtemp (char *template)
{
  char *r;

  NEED_ROOT (NULL);
  ABS_PATH (template, NULL);

  CHROOT_IN;
  r = mkdtemp (template);
  CHROOT_OUT;

  if (r == NULL) {
    reply_with_perror ("mkdtemp: %s", template);
    return NULL;
  }

  /* The caller will free template AND try to free the return value,
   * so we must make a copy here.
   */
  if (r == template) {
    r = strdup (template);
    if (r == NULL) {
      reply_with_perror ("strdup");
      return NULL;
    }
  }
  return r;
}
