/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <error.h>
#include <errno.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "boot-analysis-utils.h"

void
get_time (struct timespec *ts)
{
  if (clock_gettime (CLOCK_REALTIME, ts) == -1)
    error (EXIT_FAILURE, errno, "clock_gettime: CLOCK_REALTIME");
}

int64_t
timespec_diff (const struct timespec *x, const struct timespec *y)
{
  int64_t nsec;

  nsec = (y->tv_sec - x->tv_sec) * UINT64_C(1000000000);
  nsec += y->tv_nsec - x->tv_nsec;
  return nsec;
}
