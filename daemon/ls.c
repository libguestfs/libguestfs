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
#include <errno.h>

#include "daemon.h"
#include "actions.h"

/* Has one FileOut parameter. */
int
do_ls0 (const char *path)
{
  DIR *dir;
  struct dirent *d;
  size_t len;

  CHROOT_IN;
  dir = opendir (path);
  CHROOT_OUT;

  if (dir == NULL) {
    reply_with_perror ("opendir: %s", path);
    return -1;
  }

  /* Now we must send the reply message, before the filenames.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while (1) {
    errno = 0;
    d = readdir (dir);
    if (d == NULL) break;

    /* Ignore . and .. */
    if (STREQ (d->d_name, ".") || STREQ (d->d_name, ".."))
      continue;

    /* Send the name in a single chunk.  XXX Needs to be fixed if
     * names can be longer than the chunk size.  Note we use 'len+1'
     * because we want to include the \0 terminating character in the
     * output.
     */
    len = strlen (d->d_name);
    if (send_file_write (d->d_name, len+1) < 0) {
      closedir (dir);
      return -1;
    }
  }

  if (errno != 0) {
    fprintf (stderr, "readdir: %s: %m\n", path);
    send_file_end (1);          /* Cancel. */
    closedir (dir);
    return -1;
  }

  if (closedir (dir) == -1) {
    fprintf (stderr, "closedir: %s: %m\n", path);
    send_file_end (1);          /* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}

char *
do_ll (const char *path)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *rpath = NULL;
  CLEANUP_FREE char *spath = NULL;

  CHROOT_IN;
  rpath = realpath (path, NULL);
  CHROOT_OUT;
  if (rpath == NULL) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  spath = sysroot_path (rpath);
  if (!spath) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "ls", "-la", spath, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  return out;			/* caller frees */
}

char *
do_llz (const char *path)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *rpath = NULL;
  CLEANUP_FREE char *spath = NULL;

  CHROOT_IN;
  rpath = realpath (path, NULL);
  CHROOT_OUT;
  if (rpath == NULL) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  spath = sysroot_path (rpath);
  if (!spath) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "ls", "-laZ", spath, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  return out;			/* caller frees */
}
