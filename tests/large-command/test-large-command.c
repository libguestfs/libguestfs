/* libguestfs
 * Copyright (C) 2009-2025 Red Hat Inc.
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

/* This program, which must be statically linked, is used to test the
 * guestfs_command_out and guestfs_sh_out functions.
 */

#include <config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <error.h>

#define STREQ(a,b) (strcmp((a),(b)) == 0)

int
main (int argc, char *argv[])
{
  size_t n, i;

  if (argc > 1) {
    if (sscanf (argv[1], "%zu", &n) != 1)
      error (EXIT_FAILURE, 0, "could not parse parameter: %s", argv[1]);
    for (i = 0; i < n; ++i)
      putchar ('x');
  } else
    error (EXIT_FAILURE, 0, "missing parameter");

  exit (EXIT_SUCCESS);
}
