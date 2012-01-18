/* Regression test for RHBZ#501893.
 * Test that String parameters are checked for != NULL.
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
#include <assert.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g = guestfs_create ();

  /* Call some non-daemon functions that have a String parameter, but
   * setting that parameter to NULL.  Previously this would cause a
   * segfault inside libguestfs.  After this bug was fixed, this
   * turned into an error message.
   */

  assert (guestfs_add_drive (g, NULL) == -1);
  assert (guestfs_config (g, NULL, NULL) == -1);

  /* This optional argument must not be NULL. */

  assert (guestfs_add_drive_opts (g, "/dev/null",
                                  GUESTFS_ADD_DRIVE_OPTS_FORMAT, NULL,
                                  -1) == -1);

  /* These can be safely set to NULL, should be no error. */

  assert (guestfs_set_path (g, NULL) == 0);
  assert (guestfs_set_append (g, NULL) == 0);
  assert (guestfs_set_qemu (g, NULL) == 0);

  guestfs_close (g);
  exit (EXIT_SUCCESS);
}
