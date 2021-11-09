/* guestfsd
 * Copyright (C) 2017 Red Hat Inc.
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

/**
 * Bindings for utility functions.
 *
 * Note that functions called from OCaml code B<must never> call
 * any of the C<reply*> functions.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>

#include "daemon.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_get_verbose_flag (value unitv)
{
  return Val_bool (verbose);
}

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_is_device_parameter (value device)
{
  return Val_bool (is_device_parameter (String_val (device)));
}

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_is_root_device (value device)
{
  return Val_bool (is_root_device (String_val (device)));
}

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_prog_exists (value prog)
{
  return Val_bool (prog_exists (String_val (prog)));
}

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_udev_settle (value optfilenamev, value unitv)
{
  const char *file;

  if (optfilenamev == Val_int (0))
    file = NULL;
  else
    file = String_val (Field (optfilenamev, 0));

  udev_settle_file (file);

  return Val_unit;
}
