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
#include <fcntl.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_scrub_available (void)
{
  return prog_exists ("scrub");
}

int
do_scrub_device (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err, "scrub", device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_scrub_file (const char *file)
{
  CLEANUP_FREE char *buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  /* Resolve the path to the file, and make the result relative to /sysroot.
   * If it fails, then the file most probably does not exist or "file" is
   * a symlink pointing outside the chroot.
   */
  buf = sysroot_realpath (file);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "scrub", "-r", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", file, err);
    return -1;
  }

  return 0;
}

int
do_scrub_freespace (const char *dir)
{
  CLEANUP_FREE char *buf = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  /* Make the path relative to /sysroot. */
  buf = sysroot_path (dir);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "scrub", "-X", buf, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", dir, err);
    return -1;
  }

  return 0;
}
