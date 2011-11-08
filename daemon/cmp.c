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

#include "daemon.h"
#include "actions.h"

int
do_equal (const char *file1, const char *file2)
{
  char *file1buf, *file2buf;
  char *err;
  int r;

  file1buf = sysroot_path (file1);
  if (file1buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  file2buf = sysroot_path (file2);
  if (file2buf == NULL) {
    reply_with_perror ("malloc");
    free (file1buf);
    return -1;
  }

  r = commandr (NULL, &err, "cmp", "-s", file1buf, file2buf, NULL);

  free (file1buf);
  free (file2buf);

  if (r == -1 || r > 1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  return r == 0;
}
