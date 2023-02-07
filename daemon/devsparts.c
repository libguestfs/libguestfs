/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <limits.h>
#include <sys/stat.h>

#include "c-ctype.h"

#include "daemon.h"
#include "actions.h"

#define GUESTFSDIR "/dev/disk/guestfs"

char **
do_list_disk_labels (void)
{
  DIR *dir = NULL;
  struct dirent *d;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);

  dir = opendir (GUESTFSDIR);
  if (!dir) {
    if (errno == ENOENT) {
      /* The directory does not exist, and usually this happens when
       * there are no labels set.  In this case, act as if the directory
       * was empty.
       */
      return empty_list ();
    }
    reply_with_perror ("opendir: %s", GUESTFSDIR);
    return NULL;
  }

  while (errno = 0, (d = readdir (dir)) != NULL) {
    CLEANUP_FREE char *path = NULL;
    char *rawdev;

    if (d->d_name[0] == '.')
      continue;

    if (asprintf (&path, "%s/%s", GUESTFSDIR, d->d_name) == -1) {
      reply_with_perror ("asprintf");
      goto error;
    }

    rawdev = realpath (path, NULL);
    if (rawdev == NULL) {
      reply_with_perror ("realpath: %s", path);
      goto error;
    }

    if (add_string (&ret, d->d_name) == -1) {
      free (rawdev);
      goto error;
    }

    if (add_string_nodup (&ret, rawdev) == -1)
      goto error;
  }

  /* Check readdir didn't fail */
  if (errno != 0) {
    reply_with_perror ("readdir: %s", GUESTFSDIR);
    goto error;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: %s", GUESTFSDIR);
    dir = NULL;
    goto error;
  }

  dir = NULL;

  if (end_stringsbuf (&ret) == -1)
    goto error;

  return take_stringsbuf (&ret);              /* caller frees */

 error:
  if (dir)
    closedir (dir);
  return NULL;
}
