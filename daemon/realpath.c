/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#include "daemon.h"
#include "optgroups.h"
#include "actions.h"

/* On Windows, NAME_MAX is not defined. */
#ifndef NAME_MAX
#define NAME_MAX FILENAME_MAX
#endif

int
optgroup_realpath_available (void)
{
#ifdef HAVE_REALPATH
  return 1;
#else
  return 0;
#endif
}

char *
do_realpath (const char *path)
{
#ifdef HAVE_REALPATH
  char *ret;

  CHROOT_IN;
  ret = realpath (path, NULL);
  CHROOT_OUT;
  if (ret == NULL) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  return ret;			/* caller frees */
#else
  NOT_AVAILABLE (NULL);
#endif
}

char *
do_case_sensitive_path (const char *path)
{
  char ret[PATH_MAX+1] = "/";
  size_t next = 1;
  int fd_cwd;

  /* 'fd_cwd' here is a surrogate for the current working directory, so
   * that we don't have to actually call chdir(2).
   */
  fd_cwd = open (sysroot, O_RDONLY | O_DIRECTORY);
  if (fd_cwd == -1) {
    reply_with_perror ("%s", sysroot);
    return NULL;
  }

  /* First character is a '/'.  Take each subsequent path element
   * and follow it.
   */
  while (*path) {
    size_t i = strcspn (path, "/");
    if (i == 0) {
      path++;
      continue;
    }

    if ((i == 1 && path[0] == '.') ||
        (i == 2 && path[0] == '.' && path[1] == '.')) {
      reply_with_error ("path contained . or .. elements");
      goto error;
    }
    if (i > NAME_MAX) {
      reply_with_error ("path element too long");
      goto error;
    }

    char name[NAME_MAX+1];
    memcpy (name, path, i);
    name[i] = '\0';

    /* Skip to next element in path (for the next loop iteration). */
    path += i;

    /* Read the current directory looking (case insensitively) for
     * this element of the path.
     */
    int fd2 = dup (fd_cwd); /* because closedir will close it */
    if (fd2 == -1) {
      reply_with_perror ("dup");
      goto error;
    }
    DIR *dir = fdopendir (fd2);
    if (dir == NULL) {
      reply_with_perror ("opendir");
      goto error;
    }

    struct dirent *d = NULL;

    errno = 0;
    while ((d = readdir (dir)) != NULL) {
      if (STRCASEEQ (d->d_name, name))
        break;
    }

    if (d == NULL && errno != 0) {
      reply_with_perror ("readdir");
      goto error;
    }

    if (closedir (dir) == -1) {
      reply_with_perror ("closedir");
      goto error;
    }

    if (d == NULL) {
      reply_with_error ("%s: no file or directory found with this name", name);
      goto error;
    }

    /* Add the real name of this path element to the return value. */
    if (next > 1)
      ret[next++] = '/';

    i = strlen (d->d_name);
    if (next + i >= PATH_MAX) {
      reply_with_error ("final path too long");
      goto error;
    }

    strcpy (&ret[next], d->d_name);
    next += i;

    /* Is it a directory?  Try going into it. */
    fd2 = openat (fd_cwd, d->d_name, O_RDONLY | O_DIRECTORY);
    int err = errno;
    close (fd_cwd);
    fd_cwd = fd2;
    errno = err;
    if (fd_cwd == -1) {
      /* ENOTDIR is OK provided we've reached the end of the path. */
      if (errno != ENOTDIR) {
        reply_with_perror ("openat: %s", d->d_name);
        goto error;
      }

      if (*path) {
        reply_with_error ("%s: non-directory element in path", d->d_name);
        goto error;
      }
    }
  }

  if (fd_cwd >= 0)
    close (fd_cwd);

  ret[next] = '\0';
  char *retp = strdup (ret);
  if (retp == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }
  return retp;                  /* caller frees */

 error:
  if (fd_cwd >= 0)
    close (fd_cwd);

  return NULL;
}
