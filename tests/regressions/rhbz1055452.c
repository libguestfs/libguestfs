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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Regression test for RHBZ#1055452.  Check parsing of
 * LIBGUESTFS_BACKEND/LIBGUESTFS_ATTACH_METHOD environment variables.
 *
 * We have to write this in C so that we can call
 * guestfs_parse_environment.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"
#include "guestfs-utils.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  const char *var[] = { "LIBGUESTFS_BACKEND", "LIBGUESTFS_ATTACH_METHOD", NULL };
  const char *value[] = { "appliance", "direct", NULL };
  size_t i, j;
  char *r;

  /* Check that backend can be set to "appliance" or "direct". */

  for (i = 0; var[i] != NULL; ++i) {
    for (j = 0; value[j] != NULL; ++j) {
      setenv (var[i], value[j], 1);

      g = guestfs_create_flags (GUESTFS_CREATE_NO_ENVIRONMENT);
      if (!g)
        error (EXIT_FAILURE, errno, "guestfs_create_flags");

      if (guestfs_parse_environment (g) == -1)
        exit (EXIT_FAILURE);

      guestfs_close (g);

      unsetenv (var[i]);
    }
  }

  /* Check that guestfs_get_attach_method returns "appliance" ... */

  g = guestfs_create ();
  if (!g)
    error (EXIT_FAILURE, errno, "guestfs_create");
  if (guestfs_set_backend (g, "direct") == -1)
    exit (EXIT_FAILURE);

  r = guestfs_get_attach_method (g);
  if (!r)
    exit (EXIT_FAILURE);
  if (STRNEQ (r, "appliance")) {
    fprintf (stderr, "%s: expecting guestfs_get_attach_method to return 'appliance', but it returned '%s'.\n",
             argv[0], r);
    exit (EXIT_FAILURE);
  }
  free (r);

  /* ... but that guestfs_get_backend returns "direct". */

  r = guestfs_get_backend (g);
  if (!r)
    exit (EXIT_FAILURE);
  if (STRNEQ (r, "direct")) {
    fprintf (stderr, "%s: expecting guestfs_get_backend to return 'direct', but it returned '%s'.\n",
             argv[0], r);
    exit (EXIT_FAILURE);
  }
  free (r);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
