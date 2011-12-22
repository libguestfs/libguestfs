/* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
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
 * guestfs_command and guestfs_command_lines functions.
 */

#include <config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STREQ(a,b) (strcmp((a),(b)) == 0)

int
main (int argc, char *argv[])
{
  if (argc > 1) {
    if (STREQ (argv[1], "1")) {
      printf ("Result1");
    } else if (STREQ (argv[1], "2")) {
      printf ("Result2\n");
    } else if (STREQ (argv[1], "3")) {
      printf ("\nResult3");
    } else if (STREQ (argv[1], "4")) {
      printf ("\nResult4\n");
    } else if (STREQ (argv[1], "5")) {
      printf ("\nResult5\n\n");
    } else if (STREQ (argv[1], "6")) {
      printf ("\n\nResult6\n\n");
    } else if (STREQ (argv[1], "7")) {
      /* nothing */
    } else if (STREQ (argv[1], "8")) {
      printf ("\n");
    } else if (STREQ (argv[1], "9")) {
      printf ("\n\n");
    } else if (STREQ (argv[1], "10")) {
      printf ("Result10-1\nResult10-2\n");
    } else if (STREQ (argv[1], "11")) {
      printf ("Result11-1\nResult11-2");
    } else {
      fprintf (stderr, "unknown parameter: %s\n", argv[1]);
      exit (EXIT_FAILURE);
    }
  } else {
    fprintf (stderr, "missing parameter\n");
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}
