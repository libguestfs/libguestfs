/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 64

int
optgroup_luks_available (void)
{
  return prog_exists ("cryptsetup");
}

char *
do_luks_uuid (const char *device)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;

  ADD_ARG (argv, i, "cryptsetup");
  ADD_ARG (argv, i, "luksUUID");
  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  char *out = NULL;
  CLEANUP_FREE char *err = NULL;
  int r = commandv (&out, &err, (const char * const *) argv);

  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  trim (out);

  return out;
}
