/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 8

int
optgroup_clevisluks_available (void)
{
  return prog_exists ("clevis-luks-unlock");
}

int
do_clevis_luks_unlock (const char *device, const char *mapname)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;

  ADD_ARG (argv, i, "clevis");
  ADD_ARG (argv, i, "luks");
  ADD_ARG (argv, i, "unlock");
  ADD_ARG (argv, i, "-d");
  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, "-n");
  ADD_ARG (argv, i, mapname);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", device, mapname, err);
    return -1;
  }

  udev_settle ();
  return 0;
}
