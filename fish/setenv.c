/* guestfish - the filesystem interactive shell
 * Copyright (C) 2011 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fish.h"

int
run_setenv (const char *cmd, size_t argc, char *argv[])
{
  const char *var;
  const char *value;

  if (argc != 2) {
    fprintf (stderr, _("use '%s VAR value' to set an environment variable\n"),
             cmd);
    return -1;
  }

  var = argv[0];
  value = argv[1];

  if (setenv (var, value, 1) == -1) {
    perror ("setenv");
    return -1;
  }

  return 0;
}

int
run_unsetenv (const char *cmd, size_t argc, char *argv[])
{
  const char *var;

  if (argc != 1) {
    fprintf (stderr, _("use '%s VAR' to unset an environment variable\n"),
             cmd);
    return -1;
  }

  var = argv[0];

  if (unsetenv (var) == -1) {
    perror ("unsetenv");
    return -1;
  }

  return 0;
}
