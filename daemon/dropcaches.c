/* libguestfs - the guestfsd daemon
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
#include <fcntl.h>

#include "daemon.h"
#include "actions.h"

#define PROCFILE "/proc/sys/vm/drop_caches"

int
do_drop_caches (int what)
{
  FILE *fp;

  if (sync_disks () == -1) {
    reply_with_perror ("sync");
    return -1;
  }

  fp = fopen (PROCFILE, "w");
  if (fp == NULL) {
    reply_with_perror (PROCFILE);
    return -1;
  }

  fprintf (fp, "%d", what);
  if (fclose (fp) == EOF) {
    reply_with_perror (PROCFILE);
    return -1;
  }

  return 0;
}
