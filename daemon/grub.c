/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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

GUESTFSD_EXT_CMD(str_grub_install, grub-install);

int
optgroup_grub_available (void)
{
  return prog_exists (str_grub_install);
}

int
do_grub_install (const char *root, const char *device)
{
  int r;
  CLEANUP_FREE char *err = NULL, *buf = NULL, *out = NULL;

  if (asprintf_nowarn (&buf, "--root-directory=%R", root) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  r = command (verbose ? &out : NULL, &err,
               str_grub_install, buf, device, NULL);

  if (r == -1) {
    if (verbose)
      fprintf (stderr, "grub output:\n%s\n", out);
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}
