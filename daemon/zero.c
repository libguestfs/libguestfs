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
#include <fcntl.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

int
do_zero (char *device)
{
  int fd, i;
  char buf[4096];

  IS_DEVICE (device, -1);

  fd = open (device, O_WRONLY);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return -1;
  }

  memset (buf, 0, sizeof buf);

  for (i = 0; i < 32; ++i)
    (void) write (fd, buf, sizeof buf);

  close (fd);

  return 0;
}
