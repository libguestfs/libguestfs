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

GUESTFSD_EXT_CMD(str_btrfs, btrfs);
GUESTFSD_EXT_CMD(str_dosfslabel, dosfslabel);
GUESTFSD_EXT_CMD(str_e2label, e2label);
GUESTFSD_EXT_CMD(str_ntfslabel, ntfslabel);
GUESTFSD_EXT_CMD(str_xfs_admin, xfs_admin);

static int
btrfslabel (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, str_btrfs, "filesystem", "label",
               device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static int
dosfslabel (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, str_dosfslabel, device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static int
e2label (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (strlen (label) > EXT2_LABEL_MAX) {
    reply_with_error ("%s: ext2 labels are limited to %d bytes",
                      label, EXT2_LABEL_MAX);
    return -1;
  }

  r = command (NULL, &err, str_e2label, device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static int
ntfslabel (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  /* XXX We should check if the label is longer than 128 unicode
   * characters and return an error.  This is not so easy since we
   * don't have the required libraries.
   */
  r = command (NULL, &err, str_ntfslabel, device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

static int
xfslabel (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  /* Don't allow the special value "---".  If people want to clear
   * the label we'll have to add another call to do that.
   */
  if (STREQ (label, "---")) {
    reply_with_error ("xfs: invalid new label");
    return -1;
  }

  if (strlen (label) > XFS_LABEL_MAX) {
    reply_with_error ("%s: xfs labels are limited to %d bytes",
                      label, XFS_LABEL_MAX);
    return -1;
  }

  r = command (NULL, &err, str_xfs_admin, "-L", label, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_set_label (const mountable_t *mountable, const char *label)
{
  int r;

  /* How we set the label depends on the filesystem type. */
  CLEANUP_FREE char *vfs_type = do_vfs_type (mountable);
  if (vfs_type == NULL)
    return -1;

  if (STREQ (vfs_type, "btrfs"))
    r = btrfslabel (mountable->device, label);

  else if (STREQ (vfs_type, "msdos") ||
           STREQ (vfs_type, "fat") ||
           STREQ (vfs_type, "vfat"))
    r = dosfslabel (mountable->device, label);

  else if (fstype_is_extfs (vfs_type))
    r = e2label (mountable->device, label);

  else if (STREQ (vfs_type, "ntfs"))
    r = ntfslabel (mountable->device, label);

  else if (STREQ (vfs_type, "xfs"))
    r = xfslabel (mountable->device, label);

  else {
    reply_with_error ("don't know how to set the label for '%s' filesystems",
                      vfs_type);
    r = -1;
  }

  return r;
}
