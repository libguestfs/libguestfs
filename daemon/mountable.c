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

#include "daemon.h"
#include "actions.h"
#include "guestfs_protocol.h"

guestfs_int_internal_mountable *
do_internal_parse_mountable (const mountable_t *mountable)
{
  guestfs_int_internal_mountable *ret = calloc (1, sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("calloc");
    return NULL;
  }

  ret->im_type = mountable->type;

  if (mountable->device)
    ret->im_device = strdup (mountable->device);
  else
    ret->im_device = strdup ("");

  if (!ret->im_device) {
    reply_with_perror ("strdup");
    free (ret);
    return NULL;
  }

  if (mountable->volume)
    ret->im_volume = strdup (mountable->volume);
  else
    ret->im_volume = strdup ("");

  if (!ret->im_volume) {
    reply_with_perror ("strdup");
    free (ret->im_device);
    free (ret);
    return NULL;
  }

  return ret;
}
