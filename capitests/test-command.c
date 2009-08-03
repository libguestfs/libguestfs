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

int
main (int argc, char *argv[])
{
  if (argc > 1) {
    if (strcmp (argv[1], "1") == 0) {
      printf ("Result1");
    } else if (strcmp (argv[1], "2") == 0) {
      printf ("Result2\n");
    } else if (strcmp (argv[1], "3") == 0) {
      printf ("\nResult3");
    } else if (strcmp (argv[1], "4") == 0) {
      printf ("\nResult4\n");
    } else if (strcmp (argv[1], "5") == 0) {
      printf ("\nResult5\n\n");
    } else if (strcmp (argv[1], "6") == 0) {
      printf ("\n\nResult6\n\n");
    } else if (strcmp (argv[1], "7") == 0) {
      /* nothing */
    } else if (strcmp (argv[1], "8") == 0) {
      printf ("\n");
    } else if (strcmp (argv[1], "9") == 0) {
      printf ("\n\n");
    } else if (strcmp (argv[1], "10") == 0) {
      printf ("Result10-1\nResult10-2\n");
    } else if (strcmp (argv[1], "11") == 0) {
      printf ("Result11-1\nResult11-2");
    } else {
      fprintf (stderr, "unknown parameter: %s\n", argv[1]);
      exit (1);
    }
  } else {
    fprintf (stderr, "missing parameter\n");
    exit (1);
  }

  exit (0);
}
