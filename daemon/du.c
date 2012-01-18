/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <inttypes.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int64_t
do_du (const char *path)
{
  int r;
  int64_t rv;
  char *out, *err;
  char *buf;

  /* Make the path relative to /sysroot. */
  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  pulse_mode_start ();

  r = command (&out, &err, "du", "-s", buf, NULL);
  free (buf);
  if (r == -1) {
    pulse_mode_cancel ();
    reply_with_error ("%s: %s", path, err);
    free (out);
    free (err);
    return -1;
  }

  free (err);

  if (sscanf (out, "%"SCNi64, &rv) != 1) {
    pulse_mode_cancel ();
    reply_with_error ("%s: could not read output: %s", path, out);
    free (out);
    return -1;
  }

  free (out);

  pulse_mode_end ();

  return rv;
}
