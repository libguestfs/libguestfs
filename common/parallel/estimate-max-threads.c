/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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
#include <error.h>
#include <errno.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-utils.h"
#include "estimate-max-threads.h"

static char *read_line_from (const char *cmd);

/* The actual overhead is likely much smaller than this, but err on
 * the safe side.
 */
#define MBYTES_PER_THREAD 650

/**
 * This function uses the output of C<free -m> to estimate how many
 * libguestfs appliances could be safely started in parallel.  Note
 * that it always returns E<ge> 1.
 */
size_t
estimate_max_threads (void)
{
  CLEANUP_FREE char *mbytes_str = NULL;
  size_t mbytes;

  /* Choose the number of threads based on the amount of free memory. */
  mbytes_str = read_line_from ("LANG=C free -m | "
                               "grep '^Mem' | awk '{print $4+$6+$7}'");
  if (mbytes_str == NULL)
    return 1;

  if (sscanf (mbytes_str, "%zu", &mbytes) != 1)
    return 1;

  return MAX (1, mbytes / MBYTES_PER_THREAD);
}

/**
 * Run external command and read the first line of output.
 */
static char *
read_line_from (const char *cmd)
{
  FILE *pp;
  char *ret = NULL;
  size_t allocsize = 0;

  pp = popen (cmd, "r");
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "%s: external command failed", cmd);

  if (getline (&ret, &allocsize, pp) == -1)
    error (EXIT_FAILURE, errno, "could not read line from external command");

  if (pclose (pp) == -1)
    error (EXIT_FAILURE, errno, "pclose");

  return ret;
}
