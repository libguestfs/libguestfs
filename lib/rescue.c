/* libguestfs
 * Copyright (C) 2017 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/**
 * Support for virt-rescue(1).
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

int
guestfs_impl_internal_get_console_socket (guestfs_h *g)
{
  if (!g->conn) {
    error (g, _("no console socket, the handle must be launched"));
    return -1;
  }

  if (!g->conn->ops->get_console_sock)
    NOT_SUPPORTED (g, -1,
           _("connection class does not support getting the console socket"));

  return g->conn->ops->get_console_sock (g, g->conn);
}
