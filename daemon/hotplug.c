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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#define HOT_ADD_TIMEOUT 30 /* seconds */

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

  reply_with_error ("hot-add drive: '%s' did not appear after %d seconds: "
                    "this could mean that virtio-scsi (in qemu or kernel) "
                    "or udev is not working",
                    path, HOT_ADD_TIMEOUT);
  return -1;
}
