/* guestfish - guest filesystem shell
 * Copyright (C) 2009-2026 Red Hat Inc.
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

/**
 * This file implements the guestfish C<not> command.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <libintl.h>

#include "fish.h"
#include "run.h"

int
run_not (const char *cmd, size_t argc, char *argv[])
{
  int r;

  if (argc < 1) {
    fprintf (stderr, _("use 'not command [args...]'\n"));
    return -1;
  }

  r = issue_command (argv[0], &argv[1], NULL, 0);
  switch (r) {
  case RUN_WRONG_ARGS:
    return r;
  case RUN_ERROR:
    return 0;
  case 0:
    return RUN_ERROR;
  default:
    /* I don't think this can happen. */
    abort ();
  }
}
