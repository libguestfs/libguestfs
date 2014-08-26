/* virt-builder
 * Copyright (C) 2014 Red Hat Inc.
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

#include <stdlib.h>
#include <errno.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

value
virt_builder_mkdtemp (value val_pattern)
{
  CAMLparam1 (val_pattern);
  CAMLlocal1 (rv);
  char *pattern, *ret;

  pattern = strdup (String_val (val_pattern));
  if (pattern == NULL)
    unix_error (errno, (char *) "strdup", val_pattern);

  ret = mkdtemp (pattern);
  if (ret == NULL)
    unix_error (errno, (char *) "mkdtemp", val_pattern);

  rv = caml_copy_string (ret);
  free (pattern);

  CAMLreturn (rv);
}
