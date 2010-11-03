/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int r;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  r = guestfs_add_drive_opts (g, "/dev/null", -1);
  if (r == -1)
    exit (EXIT_FAILURE);
  r = guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1);
  if (r == -1)
    exit (EXIT_FAILURE);
  r = guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1);
  if (r == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
