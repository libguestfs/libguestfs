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

#include "daemon.h"
#include "actions.h"

char **
do_ls (const char *path)
{
  DECLARE_STRINGSBUF (ret);
  DIR *dir;
  struct dirent *d;

  CHROOT_IN;
  dir = opendir (path);
  CHROOT_OUT;

  if (!dir) {
    reply_with_perror ("opendir: %s", path);
    return NULL;
  }

  while ((d = readdir (dir)) != NULL) {
    if (STREQ (d->d_name, ".") || STREQ (d->d_name, ".."))
      continue;

    if (add_string (&ret, d->d_name) == -1) {
      closedir (dir);
      return NULL;
    }
  }

  if (ret.size > 0)
    sort_strings (ret.argv, ret.size);

  if (end_stringsbuf (&ret) == -1) {
    closedir (dir);
    return NULL;
  }

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: %s", path);
    free_stringslen (ret.argv, ret.size);
    return NULL;
  }

  return ret.argv;
}

/* Because we can't chroot and run the ls command (since 'ls' won't
 * necessarily exist in the chroot), this command can be used to escape
 * from the sysroot (eg. 'll /..').  This command is not meant for
 * serious use anyway, just for quick interactive sessions.
 */

char *
do_ll (const char *path)
{
  int r;
  char *out, *err;
  char *spath;

  spath = sysroot_path (path);
  if (!spath) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "ls", "-la", spath, NULL);
  free (spath);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);
  return out;			/* caller frees */
}

char *
do_llz (const char *path)
{
  int r;
  char *out, *err;
  char *spath;

  spath = sysroot_path (path);
  if (!spath) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = command (&out, &err, "ls", "-laZ", spath, NULL);
  free (spath);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);
  return out;			/* caller frees */
}
