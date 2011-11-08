/* guestfish - the filesystem interactive shell
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>

#include "fish.h"

int
run_time (const char *cmd, size_t argc, char *argv[])
{
  struct timeval start_t, end_t;
  int64_t start_us, end_us, elapsed_us;

  if (argc < 1) {
    fprintf (stderr, _("use 'time command [args...]'\n"));
    return -1;
  }

  gettimeofday (&start_t, NULL);

  if (issue_command (argv[0], &argv[1], NULL, 0) == -1)
    return -1;

  gettimeofday (&end_t, NULL);

  start_us = (int64_t) start_t.tv_sec * 1000000 + start_t.tv_usec;
  end_us = (int64_t) end_t.tv_sec * 1000000 + end_t.tv_usec;
  elapsed_us = end_us - start_us;
  printf ("elapsed time: %d.%02d seconds\n",
          (int) (elapsed_us / 1000000),
          (int) ((elapsed_us / 10000) % 100));

  return 0;
}
