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
  struct utsname uts;
  guestfs_int_utsname *ret;

  if (uname (&uts) == -1) {
    reply_with_perror ("utsname");
    return NULL;
  }

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->uts_sysname = strdup (uts.sysname);
  ret->uts_release = strdup (uts.release);
  ret->uts_version = strdup (uts.version);
  ret->uts_machine = strdup (uts.machine);
  if (!ret->uts_sysname || !ret->uts_release ||
      !ret->uts_version || !ret->uts_machine) {
    reply_with_perror ("strdup");
    free (ret->uts_sysname);
    free (ret->uts_release);
    free (ret->uts_version);
    free (ret->uts_machine);
    free (ret);
    return NULL;
  }

  return ret;
}
