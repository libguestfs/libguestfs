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

#include <jansson.h>

#include <stdio.h>
#include <string.h>

#define Val_none (Val_int (0))

value virt_builder_yajl_tree_parse (value stringv);

static value
convert_json_t (json_t *val, int level)
{
  CAMLparam0 ();
  CAMLlocal4 (rv, lv, v, sv);

  if (level > 20)
    caml_invalid_argument ("too many levels of object/array nesting");

  if (json_is_object (val)) {
    const size_t len = json_object_size (val);
    size_t i;
    const char *key;
    json_t *jvalue;
    rv = caml_alloc (1, 3);
    lv = caml_alloc_tuple (len);
    i = 0;
    json_object_foreach (val, key, jvalue) {
      v = caml_alloc_tuple (2);
      sv = caml_copy_string (key);
      Store_field (v, 0, sv);
      sv = convert_json_t (jvalue, level + 1);
      Store_field (v, 1, sv);
      Store_field (lv, i, v);
      ++i;
    }
    Store_field (rv, 0, lv);
  } else if (json_is_array (val)) {
    const size_t len = json_array_size (val);
    size_t i;
    json_t *jvalue;
    rv = caml_alloc (1, 4);
    lv = caml_alloc_tuple (len);
    json_array_foreach (val, i, jvalue) {
      v = convert_json_t (jvalue, level + 1);
      Store_field (lv, i, v);
    }
    Store_field (rv, 0, lv);
  } else if (json_is_string (val)) {
    rv = caml_alloc (1, 0);
    v = caml_copy_string (json_string_value (val));
    Store_field (rv, 0, v);
  } else if (json_is_real (val)) {
    rv = caml_alloc (1, 2);
    v = caml_copy_double (json_real_value (val));
    Store_field (rv, 0, v);
  } else if (json_is_integer (val)) {
    rv = caml_alloc (1, 1);
    v = caml_copy_int64 (json_integer_value (val));
    Store_field (rv, 0, v);
  } else if (json_is_true (val)) {
    rv = caml_alloc (1, 5);
    Store_field (rv, 0, Val_true);
  } else if (json_is_false (val)) {
    rv = caml_alloc (1, 5);
    Store_field (rv, 0, Val_false);
  } else
    rv = Val_none;

  CAMLreturn (rv);
}

value
virt_builder_yajl_tree_parse (value stringv)
{
  CAMLparam1 (stringv);
  CAMLlocal1 (rv);
  json_t *tree;
  json_error_t err;

  tree = json_loads (String_val (stringv), JSON_DECODE_ANY, &err);
  if (tree == NULL) {
    char buf[256 + JSON_ERROR_TEXT_LENGTH];
    if (strlen (err.text) > 0)
      snprintf (buf, sizeof buf, "JSON parse error: %s", err.text);
    else
      snprintf (buf, sizeof buf, "unknown JSON parse error");
    caml_invalid_argument (buf);
  }

  rv = convert_json_t (tree, 1);
  json_decref (tree);

  CAMLreturn (rv);
}
