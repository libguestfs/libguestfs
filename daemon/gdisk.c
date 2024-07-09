/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2024 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_gdisk_available (void)
{
  return prog_exists ("sgdisk");
}

int
do_part_expand_gpt(const char *device)
{
  CLEANUP_FREE char *err = NULL;

  int r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                    "sgdisk", "-e", device, NULL);

  if (r == -1) {
    reply_with_error ("%s -e %s: %s", "sgdisk", device, err);
    return -1;
  }

  return 0;
}
