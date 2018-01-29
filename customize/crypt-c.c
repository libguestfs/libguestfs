/* virt-sysprep - interface to crypt(3)
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
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#if HAVE_CRYPT_H
#include <crypt.h>
#endif

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

value
virt_customize_crypt (value keyv, value saltv)
{
  CAMLparam2 (keyv, saltv);
  CAMLlocal1 (rv);
  char *r;

  /* Note that crypt returns a pointer to a statically allocated
   * buffer in glibc.  For this and other reasons, this function
   * is not thread safe.
   */
  r = crypt (String_val (keyv), String_val (saltv));
  if (r == NULL)
    unix_error (errno, (char *) "crypt", Nothing);
  rv = caml_copy_string (r);

  CAMLreturn (rv);
}
