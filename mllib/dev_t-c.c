/* libguestfs OCaml tools common code
 * Copyright (C) 2016 Red Hat Inc.
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
#include <sys/types.h>

#include <caml/mlvalues.h>

/* OCaml doesn't bind the dev_t calls makedev, major and minor. */

extern value guestfs_int_mllib_dev_t_makedev (value majv, value minv);
extern value guestfs_int_mllib_dev_t_major (value devv);
extern value guestfs_int_mllib_dev_t_minor (value devv);

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_makedev (value majv, value minv)
{
  return Val_int (makedev (Int_val (majv), Int_val (minv)));
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_major (value devv)
{
  return Val_int (major (Int_val (devv)));
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_minor (value devv)
{
  return Val_int (minor (Int_val (devv)));
}
