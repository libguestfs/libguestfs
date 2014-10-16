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
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <string.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#define HOT_ADD_TIMEOUT 30 /* seconds */
#define HOT_REMOVE_TIMEOUT HOT_ADD_TIMEOUT

static void
hotplug_error (const char *op, const char *path, const char *verb,
               int timeout)
{
  reply_with_error ("%s drive: '%s' did not %s after %d seconds: "
                    "this could mean that virtio-scsi (in qemu or kernel) "
                    "or udev is not working",
                    op, path, verb, timeout);
}

/* Wait for /dev/disk/guestfs/<label> to appear.  Timeout (and error)
 * if it doesn't appear after a reasonable length of time.
 */
int
do_internal_hot_add_drive (const char *label)
{
  time_t start_t, now_t;
  size_t len = strlen (label);
  char path[len+64];
  int r;

  snprintf (path, len+64, "/dev/disk/guestfs/%s", label);

  time (&start_t);

  while (time (&now_t) - start_t <= HOT_ADD_TIMEOUT) {
    udev_settle ();

    r = access (path, F_OK);
    if (r == -1 && errno != ENOENT) {
      reply_with_perror ("%s", path);
      return -1;
    }
    if (r == 0)
      return 0;

    sleep (1);
  }

  hotplug_error ("hot-add", path, "appear", HOT_ADD_TIMEOUT);
  return -1;
}

GUESTFSD_EXT_CMD(str_fuser, fuser);

/* This function is called before a drive is hot-unplugged. */
int
do_internal_hot_remove_drive_precheck (const char *label)
{
  size_t len = strlen (label);
  char path[len+64];
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  /* Ensure there are no requests in flight (thanks Paolo Bonzini). */
  udev_settle ();
  sync_disks ();

  snprintf (path, len+64, "/dev/disk/guestfs/%s", label);

  r = commandr (&out, &err, str_fuser, "-v", "-m", path, NULL);
  if (r == -1) {
    reply_with_error ("fuser: %s: %s", path, err);
    return -1;
  }

  /* "fuser returns a non-zero return code if none of the specified
   * files is accessed or in case of a fatal error. If at least one
   * access has been found, fuser returns zero."
   */
  if (r == 0) {
    reply_with_error ("disk with label '%s' is in use "
                      "(eg. mounted or belongs to a volume group)", label);

    /* Useful for debugging when a drive cannot be unplugged. */
    if (verbose)
      fprintf (stderr, "%s\n", out);

    return -1;
  }

  return 0;
}

/* This function is called after a drive is hot-unplugged.  It checks
 * that it has really gone and udev has finished processing the
 * events, in case the user immediately hotplugs a drive with an
 * identical label.
 */
int
do_internal_hot_remove_drive (const char *label)
{
  time_t start_t, now_t;
  size_t len = strlen (label);
  char path[len+64];
  int r;

  snprintf (path, len+64, "/dev/disk/guestfs/%s", label);

  time (&start_t);

  while (time (&now_t) - start_t <= HOT_REMOVE_TIMEOUT) {
    udev_settle ();

    r = access (path, F_OK);
    if (r == -1) {
      if (errno != ENOENT) {
        reply_with_perror ("%s", path);
        return -1;
      }
      /* else udev has removed the file, so we can return */
      return 0;
    }

    sleep (1);
  }

  hotplug_error ("hot-remove", path, "disappear", HOT_REMOVE_TIMEOUT);
  return -1;
}
