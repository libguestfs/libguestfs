/* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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

/* Test error messages from the appliance.
 *
 * Note that we already test errno from the appliance (see
 * tests/c-api/test-last-errno.c) so we don't need to test that here.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"
#include "guestfs_protocol.h" /* For GUESTFS_ERROR_LEN. */

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  size_t i;
  int lengths[] = { 0, 1, 1024,
                    GUESTFS_ERROR_LEN-2, GUESTFS_ERROR_LEN-1,
                    GUESTFS_ERROR_LEN, GUESTFS_ERROR_LEN+1,
                    GUESTFS_ERROR_LEN+2,
                    GUESTFS_ERROR_LEN*2, -1 };
  char len_s[64];
  char *args[2];

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive (g, "/dev/null") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_push_error_handler (g, NULL, NULL);

  for (i = 0; lengths[i] != -1; ++i) {
    snprintf (len_s, sizeof len_s, "%d", lengths[i]);
    args[0] = len_s;
    args[1] = NULL;

    if (guestfs_debug (g, "error", args) != NULL) {
      fprintf (stderr, "%s: unexpected return value from 'debug error'\n",
               argv[0]);
      exit (EXIT_FAILURE);
    }
    /* EROFS is a magic value returned by debug_error in the daemon. */
    if (guestfs_last_errno (g) != EROFS) {
      fprintf (stderr, "%s: unexpected error from 'debug error': %s\n",
               argv[0], guestfs_last_error (g));
      exit (EXIT_FAILURE);
    }
    /* else OK */
  }

  guestfs_pop_error_handler (g);
  guestfs_close (g);
  exit (EXIT_SUCCESS);
}
