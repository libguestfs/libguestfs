/* libguestfs - the guestfsd daemon
 * Copyright (C) 2011 Red Hat Inc.
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

char **
do_list_9p (void)
{
  reply_with_perror ("9p support was removed in libguestfs 1.48");
  return NULL;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mount_9p (const char *mount_tag, const char *mountpoint, const char *options)
{
  reply_with_perror ("9p support was removed in libguestfs 1.48");
  return -1;
}
