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

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_dd (const char *src, const char *dest)
{
  int src_is_dev, dest_is_dev;
  char *if_arg, *of_arg;
  char *err;
  int r;

  src_is_dev = STRPREFIX (src, "/dev/");

  if (src_is_dev)
    r = asprintf (&if_arg, "if=%s", src);
  else
    r = asprintf (&if_arg, "if=%s%s", sysroot, src);
  if (r == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  dest_is_dev = STRPREFIX (dest, "/dev/");

  if (dest_is_dev)
    r = asprintf (&of_arg, "of=%s", dest);
  else
    r = asprintf (&of_arg, "of=%s%s", sysroot, dest);
  if (r == -1) {
    reply_with_perror ("asprintf");
    free (if_arg);
    return -1;
  }

  r = command (NULL, &err, "dd", "bs=1024K", if_arg, of_arg, NULL);
  free (if_arg);
  free (of_arg);

  if (r == -1) {
    reply_with_error ("dd: %s: %s: %s", src, dest, err);
    free (err);
    return -1;
  }
  free (err);

  return 0;
}
