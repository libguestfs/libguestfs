/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

static int
e2label (const char *device, const char *label)
{
  int r;
  char *err;

  char prog[] = "e2label";
  if (e2prog (prog) == -1)
    return -1;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  r = command (NULL, &err, prog, device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

static int
ntfslabel (const char *device, const char *label)
{
  int r;
  char *err;

  /* XXX We should check if the label is longer than 128 unicode
   * characters and return an error.  This is not so easy since we
   * don't have the required libraries.
   */
  r = command (NULL, &err, "ntfslabel", device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_set_label (const char *device, const char *label)
{
  char *vfs_type;
  int r;

  /* How we set the label depends on the filesystem type. */
  vfs_type = do_vfs_type (device);
  if (vfs_type == NULL)
    return -1;

  if (STREQ (vfs_type, "ext2") || STREQ (vfs_type, "ext3")
      || STREQ (vfs_type, "ext4"))
    r = e2label (device, label);

  else if (STREQ (vfs_type, "ntfs"))
    r = ntfslabel (device, label);

  else {
    reply_with_error ("don't know how to set the label for '%s' filesystems",
                      vfs_type);
    r = -1;
  }

  free (vfs_type);
  return r;
}
