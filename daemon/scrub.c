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
#include <fcntl.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

int
do_scrub_device (char *device)
{
  char *err;
  int r;

  r = command (NULL, &err, "scrub", device, NULL);
  if (r == -1) {
    reply_with_error ("scrub_device: %s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_scrub_file (char *file)
{
  char *buf;
  char *err;
  int r;

  NEED_ROOT (-1);
  ABS_PATH (file, return -1);

  /* Make the path relative to /sysroot. */
  buf = sysroot_path (file);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "scrub", "-r", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("scrub_file: %s: %s", file, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_scrub_freespace (char *dir)
{
  char *buf;
  char *err;
  int r;

  NEED_ROOT (-1);
  ABS_PATH (dir, return -1);

  /* Make the path relative to /sysroot. */
  buf = sysroot_path (dir);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "scrub", "-X", buf, NULL);
  free (buf);
  if (r == -1) {
    reply_with_error ("scrub_freespace: %s: %s", dir, err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}
