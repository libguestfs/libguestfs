/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2011 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_grub_available (void)
{
  return prog_exists ("grub-install");
}

int
do_grub_install (const char *root, const char *device)
{
  int r;
  char *err;
  char *buf;

  if (asprintf_nowarn (&buf, "--root-directory=%R", root) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  r = command (NULL, &err, "grub-install", buf, device, NULL);
  free (buf);

  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
