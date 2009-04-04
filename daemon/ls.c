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
#include <fcntl.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

char **
do_ls (const char *path)
{
  reply_with_error ("ls command is not yet implemented");
  return NULL;
}

char *
do_ll (const char *path)
{
  int r, len;
  char *out, *err;
  char *spath;

  if (path[0] != '/') {
    reply_with_error ("ll: path must start with a / character");
    return NULL;
  }

  /* This exposes the /sysroot, because we can't chroot and run the ls
   * command (since 'ls' won't necessarily exist in the chroot).  This
   * command is not meant for serious use anyway, just for quick
   * interactive sessions.  For the same reason, you can also "escape"
   * the sysroot (eg. 'll /..').
   */
  len = strlen (path) + 9;
  spath = malloc (len);
  if (!spath) {
    reply_with_perror ("malloc");
    return NULL;
  }
  snprintf (spath, len, "/sysroot%s", path);

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
