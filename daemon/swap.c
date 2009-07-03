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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
mkswap (char *device, const char *flag, const char *value)
{
  char *err;
  int r;

  IS_DEVICE (device, -1);

  if (!flag)
    r = command (NULL, &err, "/sbin/mkswap", device, NULL);
  else
    r = command (NULL, &err, "/sbin/mkswap", flag, value, device, NULL);

  if (r == -1) {
    reply_with_error ("mkswap: %s", err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_mkswap (char *device)
{
  return mkswap (device, NULL, NULL);
}

int
do_mkswap_L (char *label, char *device)
{
  return mkswap (device, "-L", label);
}

int
do_mkswap_U (char *uuid, char *device)
{
  return mkswap (device, "-U", uuid);
}
