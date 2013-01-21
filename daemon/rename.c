/* libguestfs - the guestfsd daemon
 * Copyright (C) 2013 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"

int
do_rename (const char *oldpath, const char *newpath)
{
  int r;

  CHROOT_IN;
  r = rename (oldpath, newpath);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("rename: %s: %s", oldpath, newpath);
    return -1;
  }

  return 0;
}
