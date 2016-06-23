/* virt tools interface to statvfs
 * Copyright (C) 2013-2016 Red Hat Inc.
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
#include <sys/statvfs.h>
#include <stdint.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

extern value guestfs_int_mllib_statvfs_free_space (value pathv);

value
guestfs_int_mllib_statvfs_free_space (value pathv)
{
  CAMLparam1 (pathv);
  CAMLlocal1 (rv);
  struct statvfs buf;
  int64_t free_space;

  if (statvfs (String_val (pathv), &buf) == -1) {
    perror ("statvfs");
    caml_failwith ("statvfs");
  }

  free_space = (int64_t) buf.f_bsize * buf.f_bavail;
  rv = caml_copy_int64 (free_space);

  CAMLreturn (rv);
}
