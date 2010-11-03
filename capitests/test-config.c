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

  /* If these fail, the default error handler will print an error
   * message to stderr, so we don't need to print anything.  This code
   * is very pedantic, but after all we are testing the details of the
   * C API.
   */

  if (guestfs_set_verbose (g, 1) == -1)
    exit (EXIT_FAILURE);
  r = guestfs_get_verbose (g);
  if (r == -1)
    exit (EXIT_FAILURE);
  if (!r) {
    fprintf (stderr, "set_verbose not true\n");
    exit (EXIT_FAILURE);
  }
  if (guestfs_set_verbose (g, 0) == -1)
    exit (EXIT_FAILURE);
  r = guestfs_get_verbose (g);
  if (r == -1)
    exit (EXIT_FAILURE);
  if (r) {
    fprintf (stderr, "set_verbose not false\n");
    exit (EXIT_FAILURE);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
