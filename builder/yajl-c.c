/* virt-builder
 * Copyright (C) 2015 Red Hat Inc.
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

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#if HAVE_YAJL
#include <yajl/yajl_tree.h>
#endif

#include <stdio.h>
#include <string.h>

#define Val_none (Val_int (0))

value virt_builder_yajl_is_available (value unit);

#if HAVE_YAJL
value virt_builder_yajl_tree_parse (value stringv);

static value
convert_yajl_value (yajl_val val, int level)
{
  CAMLparam0 ();
  CAMLlocal4 (rv, lv, v, sv);

  if (level > 20)
    caml_invalid_argument ("too many levels of object/array nesting");

  if (YAJL_IS_OBJECT (val)) {
    size_t len = YAJL_GET_OBJECT(val)->len;
    size_t i;
    rv = caml_alloc (1, 3);
    lv = caml_alloc_tuple (len);
    for (i = 0; i < len; ++i) {
      v = caml_alloc_tuple (2);
      sv = caml_copy_string (YAJL_GET_OBJECT(val)->keys[i]);
      Store_field (v, 0, sv);
      sv = convert_yajl_value (YAJL_GET_OBJECT(val)->values[i], level + 1);
      Store_field (v, 1, sv);
      Store_field (lv, i, v);
    }
    Store_field (rv, 0, lv);
  } else if (YAJL_IS_ARRAY (val)) {
    size_t len = YAJL_GET_ARRAY(val)->len;
    size_t i;
    rv = caml_alloc (1, 4);
    lv = caml_alloc_tuple (len);
    for (i = 0; i < len; ++i) {
      v = convert_yajl_value (YAJL_GET_ARRAY(val)->values[i], level + 1);
      Store_field (lv, i, v);
    }
    Store_field (rv, 0, lv);
  } else if (YAJL_IS_STRING (val)) {
    rv = caml_alloc (1, 0);
    v = caml_copy_string (YAJL_GET_STRING(val));
    Store_field (rv, 0, v);
  } else if (YAJL_IS_DOUBLE (val)) {
    rv = caml_alloc (1, 2);
    lv = caml_alloc_tuple (1);
    Store_double_field (lv, 0, YAJL_GET_DOUBLE(val));
    Store_field (rv, 0, lv);
  } else if (YAJL_IS_INTEGER (val)) {
    rv = caml_alloc (1, 1);
    v = caml_copy_int64 (YAJL_GET_INTEGER(val));
    Store_field (rv, 0, v);
  } else if (YAJL_IS_TRUE (val)) {
    rv = caml_alloc (1, 5);
    Store_field (rv, 0, Val_true);
  } else if (YAJL_IS_FALSE (val)) {
    rv = caml_alloc (1, 5);
    Store_field (rv, 0, Val_false);
  } else
    rv = Val_none;

  CAMLreturn (rv);
}

value
virt_builder_yajl_is_available (value unit)
{
  /* NB: noalloc */
  return Val_true;
}

value
virt_builder_yajl_tree_parse (value stringv)
{
  CAMLparam1 (stringv);
  CAMLlocal1 (rv);
  yajl_val tree;
  char error_buf[256];

  tree = yajl_tree_parse (String_val (stringv), error_buf, sizeof error_buf);
  if (tree == NULL) {
    char buf[256 + sizeof error_buf];
    if (strlen (error_buf) > 0)
      snprintf (buf, sizeof buf, "JSON parse error: %s", error_buf);
    else
      snprintf (buf, sizeof buf, "unknown JSON parse error");
    caml_invalid_argument (buf);
  }

  rv = convert_yajl_value (tree, 1);
  yajl_tree_free (tree);

  CAMLreturn (rv);
}

#else
value virt_builder_yajl_tree_parse (value stringv)  __attribute__((noreturn));

value
virt_builder_yajl_is_available (value unit)
{
  /* NB: noalloc */
  return Val_false;
}

value
virt_builder_yajl_tree_parse (value stringv)
{
  caml_invalid_argument ("virt-builder was compiled without yajl support");
}

#endif
