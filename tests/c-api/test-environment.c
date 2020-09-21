/* libguestfs
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Test how libguestfs uses the environment, guestfs_create_flags,
 * guestfs_parse_environment, guestfs_parse_environment_list.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <assert.h>

#include "guestfs.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int r, default_memsize;

  /* What's the default memsize? */
  g = guestfs_create ();
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create");
  default_memsize = guestfs_get_memsize (g);
  if (default_memsize == -1) exit (EXIT_FAILURE);
  guestfs_close (g);

  /* Check that guestfs_create parses the environment. */
  setenv ("LIBGUESTFS_MEMSIZE", "799", 1);
  g = guestfs_create ();
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create");
  assert (guestfs_get_memsize (g) == 799);
  guestfs_close (g);

  /* Check that guestfs_create_flags with no flags parses the environment. */
  setenv ("LIBGUESTFS_MEMSIZE", "798", 1);
  g = guestfs_create_flags (0);
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create_flags");
  assert (guestfs_get_memsize (g) == 798);
  guestfs_close (g);

  /* Check guestfs_create_flags + explicit guestfs_parse_environment. */
  setenv ("LIBGUESTFS_MEMSIZE", "797", 1);
  g = guestfs_create_flags (GUESTFS_CREATE_NO_ENVIRONMENT);
  assert (guestfs_get_memsize (g) == default_memsize);
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create_flags");
  setenv ("LIBGUESTFS_MEMSIZE", "796", 1);
  r = guestfs_parse_environment (g);
  if (r == -1) exit (EXIT_FAILURE);
  assert (guestfs_get_memsize (g) == 796);
  guestfs_close (g);

  /* Check guestfs_parse_environment_list. */
  setenv ("LIBGUESTFS_MEMSIZE", "795", 1);
  g = guestfs_create_flags (GUESTFS_CREATE_NO_ENVIRONMENT);
  assert (guestfs_get_memsize (g) == default_memsize);
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create_flags");
  setenv ("LIBGUESTFS_MEMSIZE", "794", 1);
  const char *local_environment[] = {
    "LIBGUESTFS_MEMSIZE=793",
    "LIBGUESTFS_MEMSIZE_NOT_REALLY_A_VARIABLE=1",
    "FOO=bar",
    "HOME=/homes",
    "BLAH",
    NULL
  };
  r = guestfs_parse_environment_list (g, (char **) local_environment);
  if (r == -1) exit (EXIT_FAILURE);
  assert (guestfs_get_memsize (g) == 793);
  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
