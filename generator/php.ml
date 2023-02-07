(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Printf

open Std_utils
open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs
open C

let generate_header = generate_header ~inputs:["generator/php.ml"]

let rec generate_php_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
#ifndef PHP_GUESTFS_PHP_H
#define PHP_GUESTFS_PHP_H 1

#ifdef ZTS
#include \"TSRM.h\"
#endif

#define PHP_GUESTFS_PHP_EXTNAME \"guestfs_php\"
#define PHP_GUESTFS_PHP_VERSION \"1.0\"

PHP_MINIT_FUNCTION (guestfs_php);

#define PHP_GUESTFS_HANDLE_RES_NAME \"guestfs_h\"

PHP_FUNCTION (guestfs_create);
PHP_FUNCTION (guestfs_last_error);
";

  List.iter (
    fun { name } -> pr "PHP_FUNCTION (guestfs_%s);\n" name
  ) (actions |> external_functions |> sort);

  pr "\

extern zend_module_entry guestfs_php_module_entry;
#define phpext_guestfs_php_ptr &guestfs_php_module_entry

#endif /* PHP_GUESTFS_PHP_H */
"

and generate_php_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
/* NOTE: Be very careful with all macros in PHP header files.  The
 * morons who wrote them aren't good at making them safe for inclusion
 * in arbitrary places in C code, eg. not using 'do ... while(0)'
 * or parenthesizing any of the arguments.
 */

/* NOTE (2): Some parts of the API can't be used on 32 bit platforms.
 * Any 64 bit numbers will be truncated.  There's no easy way around
 * this in PHP.
 */

#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>

#include <php.h>
#include <php_guestfs_php.h>

#include \"guestfs.h\"
#include \"guestfs-utils.h\" /* Only for POINTER_NOT_IMPLEMENTED */

static int res_guestfs_h;

/* removed from PHP 8 */
#ifndef TSRMLS_CC
#define TSRMLS_DC
#define TSRMLS_CC
#endif

#if ZEND_MODULE_API_NO >= 20151012
# define GUESTFS_RETURN_STRING(x, duplicate) \\
    do { if (duplicate) { RETURN_STRING(x); } else { RETVAL_STRING(x); efree ((char *)x); return; } } while (0)
# define guestfs_add_assoc_string(arg, key, str, dup) \\
    add_assoc_string(arg, key, str)
# define guestfs_add_assoc_stringl(arg, key, str, len, dup) \\
    add_assoc_stringl(arg, key, str, len)
# define guestfs_add_next_index_string(retval, val, x) \\
    add_next_index_string (retval, val)
# define GUESTFS_ZEND_FETCH_RESOURCE(rsrc, rsrc_type, passed_id, resource_type_name, resource_type) \\
    (rsrc) = (rsrc_type) zend_fetch_resource (Z_RES_P(passed_id), resource_type_name, resource_type)
typedef size_t guestfs_string_length;
#else
# define GUESTFS_RETURN_STRING(x, duplicate) \\
    RETURN_STRING(x, duplicate)
# define guestfs_add_assoc_string(arg, key, str, dup) \\
    add_assoc_string(arg, key, str, dup)
# define guestfs_add_assoc_stringl(arg, key, str, len, dup) \\
    add_assoc_stringl(arg, key, str, len, dup)
# define guestfs_add_next_index_string(retval, val, x) \\
    add_next_index_string (retval, val, x)
# define GUESTFS_ZEND_FETCH_RESOURCE(rsrc, rsrc_type, passed_id, resource_type_name, resource_type) \\
  ZEND_FETCH_RESOURCE(rsrc, rsrc_type, &(passed_id), -1, resource_type_name, resource_type)
typedef int guestfs_string_length;
#endif

/* Declare argument info structures */
ZEND_BEGIN_ARG_INFO_EX(arginfo_create, 0, 0, 0)
ZEND_END_ARG_INFO()

ZEND_BEGIN_ARG_INFO_EX(arginfo_last_error, 0, 0, 1)
  ZEND_ARG_INFO(0, g)
ZEND_END_ARG_INFO()

";
  List.iter (
    fun { name = shortname; style = ret, args, optargs; } ->
      let len = List.length args in
      pr "ZEND_BEGIN_ARG_INFO_EX(arginfo_%s, 0, 0, %d)\n" shortname (len + 1);
      pr "  ZEND_ARG_INFO(0, g)\n";
      List.iter (
        function
        | BufferIn n | Bool n | Int n | Int64 n | OptString n
        | Pointer(_, n) | String (_, n) | StringList (_, n) ->
          pr "  ZEND_ARG_INFO(0, %s)\n" n
        ) args;

      List.iter (
        function
        | OBool n | OInt n | OInt64 n | OString n | OStringList n ->
          pr "  ZEND_ARG_INFO(0, %s)\n" n
      ) optargs;
      pr "ZEND_END_ARG_INFO()\n\n";
  ) (actions |> external_functions |> sort);

  pr "

/* Convert array to list of strings.
 * http://marc.info/?l=pecl-dev&m=112205192100631&w=2
 */
static char**
get_stringlist (zval *val)
{
  char **ret;
  HashTable *a;
  int n;
  HashPosition p;
#if ZEND_MODULE_API_NO >= 20151012
  zval *d;
#else
  zval **d;
#endif
  size_t c = 0;

  a = Z_ARRVAL_P (val);
  n = zend_hash_num_elements (a);
  ret = safe_emalloc (n + 1, sizeof (char *), 0);
  for (zend_hash_internal_pointer_reset_ex (a, &p);
#if ZEND_MODULE_API_NO >= 20151012
       d = zend_hash_get_current_data_ex (a, &p);
#else
       zend_hash_get_current_data_ex (a, (void **) &d, &p) == SUCCESS;
#endif
       zend_hash_move_forward_ex (a, &p)) {
#if ZEND_MODULE_API_NO >= 20151012
    zval t = *d;
#else
    zval t = **d;
#endif
    zval_copy_ctor (&t);
    convert_to_string (&t);
    ret[c] = estrndup (Z_STRVAL(t), Z_STRLEN (t));
    zval_dtor (&t);
    c++;
  }
  ret[c] = NULL;
  return ret;
}

static void
guestfs_efree_stringlist (char **p)
{
  size_t c = 0;

  for (c = 0; p[c] != NULL; ++c)
    efree (p[c]);
  efree (p);
}

#if ZEND_MODULE_API_NO >= 20151012
static void
guestfs_php_handle_dtor (zend_resource *rsrc)
#else
static void
guestfs_php_handle_dtor (zend_rsrc_list_entry *rsrc TSRMLS_DC)
#endif
{
  guestfs_h *g = (guestfs_h *) rsrc->ptr;
  if (g != NULL)
    guestfs_close (g);
}

PHP_MINIT_FUNCTION (guestfs_php)
{
  res_guestfs_h =
    zend_register_list_destructors_ex (guestfs_php_handle_dtor,
    NULL, PHP_GUESTFS_HANDLE_RES_NAME, module_number);
  return SUCCESS;
}

static zend_function_entry guestfs_php_functions[] = {
  PHP_FE (guestfs_create, arginfo_create)
  PHP_FE (guestfs_last_error, arginfo_last_error)
";

  List.iter (
    fun { name } -> pr "  PHP_FE (guestfs_%s, arginfo_%s)\n" name name
  ) (actions |> external_functions |> sort);

  pr "  { NULL, NULL, NULL }
};

zend_module_entry guestfs_php_module_entry = {
#if ZEND_MODULE_API_NO >= 20010901
  STANDARD_MODULE_HEADER,
#endif
  PHP_GUESTFS_PHP_EXTNAME,
  guestfs_php_functions,
  PHP_MINIT (guestfs_php),
  NULL,
  NULL,
  NULL,
  NULL,
#if ZEND_MODULE_API_NO >= 20010901
  PHP_GUESTFS_PHP_VERSION,
#endif
  STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_GUESTFS_PHP
ZEND_GET_MODULE (guestfs_php)
#endif

PHP_FUNCTION (guestfs_create)
{
  guestfs_h *g = guestfs_create ();
  if (g == NULL) {
    RETURN_FALSE;
  }

  guestfs_set_error_handler (g, NULL, NULL);

#if ZEND_MODULE_API_NO >= 20151012
  ZVAL_RES(return_value, zend_register_resource(g, res_guestfs_h));
#else
  ZEND_REGISTER_RESOURCE (return_value, g, res_guestfs_h);
#endif
}

PHP_FUNCTION (guestfs_last_error)
{
  zval *z_g;
  guestfs_h *g;

  if (zend_parse_parameters (ZEND_NUM_ARGS() TSRMLS_CC, \"r\",
                             &z_g) == FAILURE) {
    RETURN_FALSE;
  }

  GUESTFS_ZEND_FETCH_RESOURCE (g, guestfs_h *, z_g,
                               PHP_GUESTFS_HANDLE_RES_NAME, res_guestfs_h);
  if (g == NULL) {
    RETURN_FALSE;
  }

  const char *err = guestfs_last_error (g);
  if (err) {
    GUESTFS_RETURN_STRING (err, 1);
  } else {
    RETURN_NULL ();
  }
}

";

  (* Now generate the PHP bindings for each action. *)
  List.iter (
    fun { name = shortname; style = ret, args, optargs as style;
          c_function; c_optarg_prefix } ->
      pr "PHP_FUNCTION (guestfs_%s)\n" shortname;
      pr "{\n";
      pr "  zval *z_g;\n";
      pr "  guestfs_h *g;\n";

      List.iter (
        function
        | String (_, n)
        | BufferIn n ->
            pr "  char *%s;\n" n;
            pr "  guestfs_string_length %s_size;\n" n
        | OptString n ->
            pr "  char *%s = NULL;\n" n;
            pr "  guestfs_string_length %s_size;\n" n
        | StringList (_, n) ->
            pr "  zval *z_%s;\n" n;
            pr "  char **%s;\n" n;
        | Bool n ->
            pr "  zend_bool %s;\n" n
        | Int n | Int64 n ->
            pr "  long %s;\n" n
        | Pointer (t, n) ->
            pr "  void * /* %s */ %s;\n" t n
        ) args;

      if optargs <> [] then (
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" c_function;
        pr "  struct %s *optargs = &optargs_s;\n" c_function;

        (* XXX Ugh PHP doesn't have proper optional arguments, so we
         * have to use sentinel values.
         *)
        (* Since we don't know if PHP types will exactly match structure
         * types, declare some local variables here.
         *)
        List.iter (
          function
          | OBool n -> pr "  zend_bool optargs_t_%s = -1;\n" n
          | OInt n | OInt64 n -> pr "  long optargs_t_%s = -1;\n" n
          | OString n ->
              pr "  char *optargs_t_%s = NULL;\n" n;
              pr "  guestfs_string_length optargs_t_%s_size = -1;\n" n
          | OStringList n ->
              pr "  zval *optargs_t_%s = NULL;\n" n
        ) optargs
      );

      pr "\n";

      (* Parse the parameters. *)
      let param_string = String.concat "" (
        List.map (
          function
          | String (_, n)
          | BufferIn n -> "s"
          | OptString n -> "s!"
          | StringList (_, n) -> "a"
          | Bool n -> "b"
          | Int n | Int64 n -> "l"
          | Pointer _ -> ""
        ) args
      ) in

      let param_string =
        if optargs <> [] then
          param_string ^ "|" ^
            String.concat "" (
              List.map (
                function
                | OBool _ -> "b"
                | OInt _ | OInt64 _ -> "l"
                | OString _ -> "s"
                | OStringList _ ->
                  (* Because this is an optarg, it can be passed as
                   * NULL, so we must add '!' afterwards.
                   *)
                  "a!"
              ) optargs
            )
        else param_string in

      pr "  if (zend_parse_parameters (ZEND_NUM_ARGS() TSRMLS_CC, \"r%s\",\n"
        param_string;
      pr "        &z_g";
      List.iter (
        function
        | String (_, n)
        | BufferIn n
        | OptString n ->
            pr ", &%s, &%s_size" n n
        | StringList (_, n) ->
            pr ", &z_%s" n
        | Bool n ->
            pr ", &%s" n
        | Int n | Int64 n ->
            pr ", &%s" n
        | Pointer (_, n) -> ()
      ) args;
      List.iter (
        function
        | OBool n | OInt n | OInt64 n ->
            pr ", &optargs_t_%s" n
        | OString n ->
            pr ", &optargs_t_%s, &optargs_t_%s_size" n n
        | OStringList n ->
            pr ", &optargs_t_%s" n
      ) optargs;
      pr ") == FAILURE) {\n";
      pr "    RETURN_FALSE;\n";
      pr "  }\n";
      pr "\n";
      pr "  GUESTFS_ZEND_FETCH_RESOURCE (g, guestfs_h *, z_g,\n";
      pr "                               PHP_GUESTFS_HANDLE_RES_NAME, res_guestfs_h);\n";
      pr "  if (g == NULL) {\n";
      pr "    RETURN_FALSE;\n";
      pr "  }\n";
      pr "\n";

      List.iter (
        function
        | String (_, n) ->
            (* Just need to check the string doesn't contain any ASCII
             * NUL characters, which won't be supported by the C API.
             *)
            pr "  if (strlen (%s) != %s_size) {\n" n n;
            pr "    fprintf (stderr, \"libguestfs: %s: parameter '%s' contains embedded ASCII NUL.\\n\");\n" shortname n;
            pr "    RETURN_FALSE;\n";
            pr "  }\n";
            pr "\n"
        | OptString n ->
            (* Just need to check the string doesn't contain any ASCII
             * NUL characters, which won't be supported by the C API.
             *)
            pr "  if (%s != NULL && strlen (%s) != %s_size) {\n" n n n;
            pr "    fprintf (stderr, \"libguestfs: %s: parameter '%s' contains embedded ASCII NUL.\\n\");\n" shortname n;
            pr "    RETURN_FALSE;\n";
            pr "  }\n";
            pr "\n"
        | BufferIn n -> ()
        | StringList (_, n) ->
            pr "  %s = get_stringlist (z_%s);\n" n n;
            pr "\n"
        | Bool _ | Int _ | Int64 _ -> ()
        | Pointer (t, n) ->
            pr "  %s = POINTER_NOT_IMPLEMENTED (\"%s\");\n" n t
        ) args;

      (* Optional arguments. *)
      if optargs <> [] then (
        List.iter (
          function
          | OBool n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if (optargs_t_%s != (zend_bool)-1) {\n" n;
            pr "    optargs_s.%s = optargs_t_%s;\n" n n;
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            pr "  }\n"
          | OInt n | OInt64 n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if (optargs_t_%s != -1) {\n" n;
            pr "    optargs_s.%s = optargs_t_%s;\n" n n;
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            pr "  }\n"
          | OString n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if (optargs_t_%s != NULL) {\n" n;
            pr "    optargs_s.%s = optargs_t_%s;\n" n n;
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            pr "  }\n"
          | OStringList n ->
            let uc_n = String.uppercase_ascii n in
            pr "  /* We've seen PHP give us a *long* here when we asked for an array, so\n";
            pr "   * positively check that it gave us an array, otherwise ignore it.\n";
            pr "   */\n";
            pr "  if (optargs_t_%s != NULL && Z_TYPE_P (optargs_t_%s) == IS_ARRAY) {\n" n n;
            pr "    optargs_s.%s = get_stringlist (optargs_t_%s);\n" n n;
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            pr "  }\n";
        ) optargs;
        pr "\n"
      );

      (* Return value. *)
      (match ret with
       | RErr -> pr "  int r;\n"
       | RBool _
       | RInt _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ -> pr "  const char *r;\n"
       | RConstOptString _ -> pr "  const char *r;\n"
       | RString _ ->
           pr "  char *r;\n"
       | RStringList _ ->
           pr "  char **r;\n"
       | RStruct (_, typ) ->
           pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) ->
           pr "  struct guestfs_%s_list *r;\n" typ
       | RHashtable _ ->
           pr "  char **r;\n"
       | RBufferOut _ ->
           pr "  char *r;\n";
           pr "  size_t size;\n"
      );

      (* Call the function. *)
      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      pr "\n";

      (* Free up parameters. *)
      List.iter (
        function
        | String _
        | OptString _
        | BufferIn _ -> ()
        | StringList (_, n) ->
            pr "  guestfs_efree_stringlist (%s);\n" n;
            pr "\n"
        | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        ) args;
      List.iter (
        function
        | OBool n | OInt n | OInt64 n | OString n -> ()
        | OStringList n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if ((optargs_s.bitmask & %s_%s_BITMASK) != 0)\n"
              c_optarg_prefix uc_n;
            pr "    guestfs_efree_stringlist ((char **) optargs_s.%s);\n" n;
            pr "\n"
      ) optargs;

      (* Check for errors. *)
      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1) {\n";
           pr "    RETURN_FALSE;\n";
           pr "  }\n"
       | `ErrorIsNULL ->
           pr "  if (r == NULL) {\n";
           pr "    RETURN_FALSE;\n";
           pr "  }\n"
      );
      pr "\n";

      (* Convert the return value. *)
      (match ret with
       | RErr ->
           pr "  RETURN_TRUE;\n"
       | RBool _ ->
           pr "  RETURN_BOOL (r);\n"
       | RInt _ ->
           pr "  RETURN_LONG (r);\n"
       | RInt64 _ ->
           pr "  RETURN_LONG (r);\n"
       | RConstString _ ->
           pr "  GUESTFS_RETURN_STRING (r, 1);\n"
       | RConstOptString _ ->
           pr "  if (r) { GUESTFS_RETURN_STRING (r, 1); }\n";
           pr "  else { RETURN_NULL (); }\n"
       | RString _ ->
           pr "  char *r_copy = estrdup (r);\n";
           pr "  free (r);\n";
           pr "  GUESTFS_RETURN_STRING (r_copy, 0);\n"
       | RBufferOut _ ->
           pr "  char *r_copy = estrndup (r, size);\n";
           pr "  free (r);\n";
           pr "  GUESTFS_RETURN_STRING (r_copy, 0);\n"
       | RStringList _ ->
           pr "  size_t c = 0;\n";
           pr "  array_init (return_value);\n";
           pr "  for (c = 0; r[c] != NULL; ++c) {\n";
           pr "    guestfs_add_next_index_string (return_value, r[c], 1);\n";
           pr "    free (r[c]);\n";
           pr "  }\n";
           pr "  free (r);\n";
       | RHashtable _ ->
           pr "  size_t c = 0;\n";
           pr "  array_init (return_value);\n";
           pr "  for (c = 0; r[c] != NULL; c += 2) {\n";
           pr "    guestfs_add_assoc_string (return_value, r[c], r[c+1], 1);\n";
           pr "    free (r[c]);\n";
           pr "    free (r[c+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
       | RStruct (_, typ) ->
           let cols = cols_of_struct typ in
           generate_php_struct_code typ cols
       | RStructList (_, typ) ->
           let cols = cols_of_struct typ in
           generate_php_struct_list_code typ cols
      );

      pr "}\n";
      pr "\n"
  ) (actions |> external_functions |> sort)

and generate_php_struct_code typ cols =
  pr "  array_init (return_value);\n";
  List.iter (
    function
    | name, FString ->
        pr "  guestfs_add_assoc_string (return_value, \"%s\", r->%s, 1);\n" name name
    | name, FBuffer ->
        pr "  guestfs_add_assoc_stringl (return_value, \"%s\", r->%s, r->%s_len, 1);\n"
          name name name
    | name, FUUID ->
        pr "  guestfs_add_assoc_stringl (return_value, \"%s\", r->%s, 32, 1);\n"
          name name
    | name, (FBytes|FUInt64|FInt64|FInt32|FUInt32) ->
        pr "  add_assoc_long (return_value, \"%s\", r->%s);\n"
          name name
    | name, FChar ->
        pr "  guestfs_add_assoc_stringl (return_value, \"%s\", &r->%s, 1, 1);\n"
          name name
    | name, FOptPercent ->
        pr "  add_assoc_double (return_value, \"%s\", r->%s);\n"
          name name
  ) cols;
  pr "  guestfs_free_%s (r);\n" typ

and generate_php_struct_list_code typ cols =
  pr "  array_init (return_value);\n";
  pr "  size_t c = 0;\n";
  pr "  for (c = 0; c < r->len; ++c) {\n";
  pr "#if ZEND_MODULE_API_NO >= 20151012\n";
  pr "    zval elem;\n";
  pr "    zval *z_elem = &elem;\n";
  pr "#else\n";
  pr "    zval *z_elem;\n";
  pr "    ALLOC_INIT_ZVAL (z_elem);\n";
  pr "#endif\n";
  pr "    array_init (z_elem);\n";
  List.iter (
    function
    | name, FString ->
        pr "    guestfs_add_assoc_string (z_elem, \"%s\", r->val[c].%s, 1);\n"
          name name
    | name, FBuffer ->
        pr "    guestfs_add_assoc_stringl (z_elem, \"%s\", r->val[c].%s, r->val[c].%s_len, 1);\n"
          name name name
    | name, FUUID ->
        pr "    guestfs_add_assoc_stringl (z_elem, \"%s\", r->val[c].%s, 32, 1);\n"
          name name
    | name, (FBytes|FUInt64|FInt64|FInt32|FUInt32) ->
        pr "    add_assoc_long (z_elem, \"%s\", r->val[c].%s);\n"
          name name
    | name, FChar ->
        pr "    guestfs_add_assoc_stringl (z_elem, \"%s\", &r->val[c].%s, 1, 1);\n"
          name name
    | name, FOptPercent ->
        pr "    add_assoc_double (z_elem, \"%s\", r->val[c].%s);\n"
          name name
  ) cols;
  pr "    add_next_index_zval (return_value, z_elem);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ
