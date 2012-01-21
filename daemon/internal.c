/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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

/* Internal functions are not part of the public API. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

/* Older versions of libguestfs used to issue separate 'umount_all'
 * and 'sync' commands just before closing the handle.  Since
 * libguestfs 1.9.7 the library issues this 'internal_autosync'
 * internal operation instead, allowing more control in the daemon.
 */
int
do_internal_autosync (void)
{
  int r = 0;

  if (autosync_umount)
    r = do_umount_all ();

  sync_disks ();

  return r;
}
