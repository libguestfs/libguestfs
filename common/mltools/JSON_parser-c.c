/* JSON parser
 * Copyright (C) 2015-2018 Red Hat Inc.
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

#define JSON_NULL       (Val_int (0)) /* Variants without parameters. */
#define JSON_STRING_TAG 0             /* Variants with parameters. */
#define JSON_INT_TAG    1
#define JSON_FLOAT_TAG  2
#define JSON_BOOL_TAG   3
#define JSON_LIST_TAG   4
#define JSON_DICT_TAG   5

value virt_builder_json_parser_tree_parse (value stringv);

static value
convert_json_t (json_t *val, int level)
{
  CAMLparam0 ();
  CAMLlocal5 (rv, v, tv, sv, consv);

  if (level > 20)
    caml_invalid_argument ("too many levels of object/array nesting");

  if (json_is_object (val)) {
    const char *key;
    json_t *jvalue;

    rv = caml_alloc (1, JSON_DICT_TAG);
    v = Val_int (0);
    /* This will create the OCaml list backwards, but JSON
     * dictionaries are supposed to be unordered so that shouldn't
     * matter, right?  Well except that for some consumers this does
     * matter (eg. simplestreams which incorrectly uses a dict when it
     * really should use an array).
     */
    json_object_foreach (val, key, jvalue) {
      tv = caml_alloc_tuple (2);
      sv = caml_copy_string (key);
      Store_field (tv, 0, sv);
      sv = convert_json_t (jvalue, level + 1);
      Store_field (tv, 1, sv);
      consv = caml_alloc (2, 0);
      Store_field (consv, 1, v);
      Store_field (consv, 0, tv);
      v = consv;
    }
    Store_field (rv, 0, v);
  }
  else if (json_is_array (val)) {
    const size_t len = json_array_size (val);
    size_t i;
    json_t *jvalue;

    rv = caml_alloc (1, JSON_LIST_TAG);
    v = Val_int (0);
    for (i = 0; i < len; ++i) {
      /* Note we have to create the OCaml list backwards. */
      jvalue = json_array_get (val, len-i-1);
      tv = convert_json_t (jvalue, level + 1);
      consv = caml_alloc (2, 0);
      Store_field (consv, 1, v);
      Store_field (consv, 0, tv);
      v = consv;
    }
    Store_field (rv, 0, v);
  }
  else if (json_is_string (val)) {
    rv = caml_alloc (1, JSON_STRING_TAG);
    v = caml_copy_string (json_string_value (val));
    Store_field (rv, 0, v);
  }
  else if (json_is_real (val)) {
    rv = caml_alloc (1, JSON_FLOAT_TAG);
    v = caml_copy_double (json_real_value (val));
    Store_field (rv, 0, v);
  }
  else if (json_is_integer (val)) {
    rv = caml_alloc (1, JSON_INT_TAG);
    v = caml_copy_int64 (json_integer_value (val));
    Store_field (rv, 0, v);
  }
  else if (json_is_true (val)) {
    rv = caml_alloc (1, JSON_BOOL_TAG);
    Store_field (rv, 0, Val_true);
  }
  else if (json_is_false (val)) {
    rv = caml_alloc (1, JSON_BOOL_TAG);
    Store_field (rv, 0, Val_false);
  }
  else
    rv = JSON_NULL;

  CAMLreturn (rv);
}

value
virt_builder_json_parser_tree_parse (value stringv)
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
