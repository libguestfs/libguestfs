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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <sys/utsname.h>
#include <string.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

guestfs_int_utsname *
do_utsname (void)
{
  struct utsname u;

  if (uname (&u) == -1) {
    reply_with_perror ("uname");
    return NULL;
  }

  CLEANUP_FREE_UTSNAME guestfs_int_utsname *tmp = calloc (1, sizeof *tmp);
  if (!tmp) {
    reply_with_perror ("calloc");
    return NULL;
  }

  if (!(tmp->uts_sysname = strdup (u.sysname)) ||
      !(tmp->uts_release = strdup (u.release)) ||
      !(tmp->uts_version = strdup (u.version)) ||
      !(tmp->uts_machine = strdup (u.machine))) {
    reply_with_perror ("strdup");
    return NULL;
  }

  guestfs_int_utsname *ret = tmp;
  tmp = NULL;

  return ret;
}
