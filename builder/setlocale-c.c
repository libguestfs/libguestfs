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

#include <locale.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

static const int lc_string_table[7] = {
  LC_ALL,
  LC_CTYPE,
  LC_NUMERIC,
  LC_TIME,
  LC_COLLATE,
  LC_MONETARY,
  LC_MESSAGES
};

#define Val_none (Val_int (0))

extern value virt_builder_setlocale (value val_category, value val_name);

value
virt_builder_setlocale (value val_category, value val_name)
{
  CAMLparam2 (val_category, val_name);
  CAMLlocal2 (rv, rv2);
  const char *locstring;
  char *ret;
  int category;

  category = lc_string_table[Int_val (val_category)];
  locstring = val_name == Val_none ? NULL : String_val (Field (val_name, 0));
  ret = setlocale (category, locstring);
  if (ret) {
    rv2 = caml_copy_string (ret);
    rv = caml_alloc (1, 0);
    Store_field (rv, 0, rv2);
  } else
    rv = Val_none;

  CAMLreturn (rv);
}
