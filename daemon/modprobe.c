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
#include <unistd.h>
#include <errno.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_linuxmodules_available (void)
{
  /* If /proc/modules doesn't exist, then the appliance kernel
   * probably has modules support compiled out.  This means modprobe
   * is not supported.
   */
  if (access ("/proc/modules", R_OK) == -1 && errno == ENOENT)
    return 0;

  return prog_exists ("modprobe");
}

int
do_modprobe (const char *module)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err, "modprobe", module, NULL);

  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return r;
}
