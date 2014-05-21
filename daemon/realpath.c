/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <limits.h>
#include <sys/types.h>
#include <dirent.h>

#include "cloexec.h"

#include "daemon.h"
#include "optgroups.h"
#include "actions.h"

char *
do_realpath (const char *path)
{
  char *ret;

  CHROOT_IN;
  ret = realpath (path, NULL);
  CHROOT_OUT;
  if (ret == NULL) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  return ret;			/* caller frees */
}

static int find_path_element (int fd_cwd, int is_end, const char *name, char **name_ret);

char *
do_case_sensitive_path (const char *path)
{
  size_t next;
  int fd_cwd, fd2, err, is_end;
  char *ret;

  ret = strdup ("/");
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }
  next = 1; /* next position in 'ret' buffer */

  /* 'fd_cwd' here is a surrogate for the current working directory, so
   * that we don't have to actually call chdir(2).
   */
  fd_cwd = open (sysroot, O_RDONLY|O_DIRECTORY|O_CLOEXEC);
  if (fd_cwd == -1) {
    reply_with_perror ("%s", sysroot);
    goto error;
  }

  /* First character is a '/'.  Take each subsequent path element
   * and follow it.
   */
  while (*path) {
    char *t;
    size_t i, len;
    CLEANUP_FREE char *name_in = NULL, *name_out = NULL;

    i = strcspn (path, "/");
    if (i == 0) {
      path++;
      continue;
    }

    if ((i == 1 && path[0] == '.') ||
        (i == 2 && path[0] == '.' && path[1] == '.')) {
      reply_with_error ("path contained . or .. elements");
      goto error;
    }

    name_in = strndup (path, i);
    if (name_in == NULL) {
      reply_with_perror ("strdup");
      goto error;
    }

    /* Skip to next element in path (for the next loop iteration). */
    path += i;
    is_end = *path == 0;

    /* Read the current directory looking (case insensitively) for
     * this element of the path.  This replaces 'name' with the
     * correct case version.
     */
    if (find_path_element (fd_cwd, is_end, name_in, &name_out) == -1)
      goto error;
    len = strlen (name_out);

    /* Add the real name of this path element to the return value. */
    if (next > 1)
      ret[next++] = '/';

    t = realloc (ret, next+len+1);
    if (t == NULL) {
      reply_with_perror ("realloc");
      goto error;
    }
    ret = t;

    strcpy (&ret[next], name_out);
    next += len;

    /* Is it a directory?  Try going into it. */
    fd2 = openat (fd_cwd, name_out, O_RDONLY|O_DIRECTORY|O_CLOEXEC);
    err = errno;
    close (fd_cwd);
    fd_cwd = fd2;
    errno = err;
    if (fd_cwd == -1) {
      /* Some errors are OK provided we've reached the end of the path. */
      if (is_end && (errno == ENOTDIR || errno == ENOENT))
        break;

      reply_with_perror ("openat: %s", name_out);
      goto error;
    }
  }

  if (fd_cwd >= 0)
    close (fd_cwd);

  return ret;                   /* caller frees */

 error:
  if (fd_cwd >= 0)
    close (fd_cwd);
  free (ret);

  return NULL;
}

/* 'fd_cwd' is a file descriptor pointing to an open directory.
 * 'name' is the path element to search for.  'is_end' is a flag
 * indicating if this is the last path element.
 *
 * We search the directory looking for a path element that case
 * insensitively matches 'name', returning the actual name in '*name_ret'.
 *
 * If this is successful, return 0.  If it fails, reply with an error
 * and return -1.
 */
static int
find_path_element (int fd_cwd, int is_end, const char *name, char **name_ret)
{
  int fd2;
  DIR *dir;
  struct dirent *d;

  fd2 = dup_cloexec (fd_cwd); /* because closedir will close it */
  if (fd2 == -1) {
    reply_with_perror ("dup");
    return -1;
  }
  dir = fdopendir (fd2);
  if (dir == NULL) {
    reply_with_perror ("opendir");
    close (fd2);
    return -1;
  }

  for (;;) {
    errno = 0;
    d = readdir (dir);
    if (d == NULL)
      break;
    if (STRCASEEQ (d->d_name, name))
      break;
  }

  if (d == NULL && errno != 0) {
    reply_with_perror ("readdir");
    closedir (dir);
    return -1;
  }

  if (d == NULL && is_end) {
    /* Last path element: return it as-is, assuming that the user will
     * create a new file or directory (RHBZ#840115).
     */
    closedir (dir);
    *name_ret = strdup (name);
    if (*name_ret == NULL) {
      reply_with_perror ("strdup");
      return -1;
    }
    return 0;
  }

  if (d == NULL) {
    reply_with_error ("%s: no file or directory found with this name", name);
    closedir (dir);
    return -1;
  }

  *name_ret = strdup (d->d_name);
  if (*name_ret == NULL) {
    reply_with_perror ("strdup");
    closedir (dir);
    return -1;
  }

  /* NB: closedir frees the structure associated with 'd', so we must
   * do this last.
   */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir");
    return -1;
  }

  return 0;
}
