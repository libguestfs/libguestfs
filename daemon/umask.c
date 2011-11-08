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
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_umask (int mask)
{
  int r;

  if (mask < 0 || mask > 0777) {
    reply_with_error ("0%o: mask negative or out of range", mask);
    return -1;
  }

  r = umask (mask);

  if (r == -1) {
    reply_with_perror ("umask");
    return -1;
  }

  return r;
}

int
do_get_umask (void)
{
  int r;

  r = umask (022);
  if (r == -1) {
    reply_with_perror ("umask");
    return -1;
  }

  /* Restore the umask, since the call above corrupted it. */
  umask (r);

  return r;
}
