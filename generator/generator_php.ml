(* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

open Generator_types
open Generator_utils
open Generator_pr
open Generator_docstrings
open Generator_optgroups
open Generator_actions
open Generator_structs
open Generator_c

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
    fun (shortname, _, _, _, _, _, _) ->
      pr "PHP_FUNCTION (guestfs_%s);\n" shortname
  ) all_functions_sorted;

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

#include <stdio.h>
#include <stdlib.h>

#include <php.h>
#include <php_guestfs_php.h>

#include \"guestfs.h\"

static int res_guestfs_h;

static void
guestfs_php_handle_dtor (zend_rsrc_list_entry *rsrc TSRMLS_DC)
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
}

static function_entry guestfs_php_functions[] = {
  PHP_FE (guestfs_create, NULL)
  PHP_FE (guestfs_last_error, NULL)
";

  List.iter (
    fun (shortname, _, _, _, _, _, _) ->
      pr "  PHP_FE (guestfs_%s, NULL)\n" shortname
  ) all_functions_sorted;

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

  ZEND_REGISTER_RESOURCE (return_value, g, res_guestfs_h);
}

PHP_FUNCTION (guestfs_last_error)
{
  zval *z_g;
  guestfs_h *g;

  if (zend_parse_parameters (ZEND_NUM_ARGS() TSRMLS_CC, \"r\",
                             &z_g) == FAILURE) {
    RETURN_FALSE;
  }

  ZEND_FETCH_RESOURCE (g, guestfs_h *, &z_g, -1, PHP_GUESTFS_HANDLE_RES_NAME,
                       res_guestfs_h);
  if (g == NULL) {
    RETURN_FALSE;
  }

  const char *err = guestfs_last_error (g);
  if (err) {
    RETURN_STRING (err, 1);
  } else {
    RETURN_NULL ();
  }
}

";

  (* Now generate the PHP bindings for each action. *)
  List.iter (
    fun (shortname, (ret, args, optargs as style), _, _, _, _, _) ->
      pr "PHP_FUNCTION (guestfs_%s)\n" shortname;
      pr "{\n";
      pr "  zval *z_g;\n";
      pr "  guestfs_h *g;\n";

      List.iter (
        function
        | String n | Device n | Pathname n | Dev_or_Path n
        | FileIn n | FileOut n | Key n
        | OptString n
        | BufferIn n ->
            pr "  char *%s;\n" n;
            pr "  int %s_size;\n" n
        | StringList n
        | DeviceList n ->
            pr "  zval *z_%s;\n" n;
            pr "  char **%s;\n" n;
        | Bool n ->
            pr "  zend_bool %s;\n" n
        | Int n | Int64 n | Pointer (_, n) ->
            pr "  long %s;\n" n
        ) args;

      if optargs <> [] then (
        pr "  struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" shortname;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" shortname;

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
              pr "  int optargs_t_%s_size = -1;\n" n
        ) optargs
      );

      pr "\n";

      (* Parse the parameters. *)
      let param_string = String.concat "" (
        List.map (
          function
          | String n | Device n | Pathname n | Dev_or_Path n
          | FileIn n | FileOut n | BufferIn n | Key n -> "s"
          | OptString n -> "s!"
          | StringList n | DeviceList n -> "a"
          | Bool n -> "b"
          | Int n | Int64 n | Pointer (_, n) -> "l"
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
              ) optargs
            )
        else param_string in

      pr "  if (zend_parse_parameters (ZEND_NUM_ARGS() TSRMLS_CC, \"r%s\",\n"
        param_string;
      pr "        &z_g";
      List.iter (
        function
        | String n | Device n | Pathname n | Dev_or_Path n
        | FileIn n | FileOut n | BufferIn n | Key n
        | OptString n ->
            pr ", &%s, &%s_size" n n
        | StringList n | DeviceList n ->
            pr ", &z_%s" n
        | Bool n ->
            pr ", &%s" n
        | Int n | Int64 n | Pointer (_, n) ->
            pr ", &%s" n
      ) args;
      List.iter (
        function
        | OBool n | OInt n | OInt64 n ->
            pr ", &optargs_t_%s" n
        | OString n ->
            pr ", &optargs_t_%s, &optargs_t_%s_size" n n
      ) optargs;
      pr ") == FAILURE) {\n";
      pr "    RETURN_FALSE;\n";
      pr "  }\n";
      pr "\n";
      pr "  ZEND_FETCH_RESOURCE (g, guestfs_h *, &z_g, -1, PHP_GUESTFS_HANDLE_RES_NAME,\n";
      pr "                       res_guestfs_h);\n";
      pr "  if (g == NULL) {\n";
      pr "    RETURN_FALSE;\n";
      pr "  }\n";
      pr "\n";

      List.iter (
        function
        | String n | Device n | Pathname n | Dev_or_Path n
        | FileIn n | FileOut n | Key n
        | OptString n ->
            (* Just need to check the string doesn't contain any ASCII
             * NUL characters, which won't be supported by the C API.
             *)
            pr "  if (strlen (%s) != %s_size) {\n" n n;
            pr "    fprintf (stderr, \"libguestfs: %s: parameter '%s' contains embedded ASCII NUL.\\n\");\n" shortname n;
            pr "    RETURN_FALSE;\n";
            pr "  }\n";
            pr "\n"
        | BufferIn n -> ()
        | StringList n
        | DeviceList n ->
            (* Convert array to list of strings.
             * http://marc.info/?l=pecl-dev&m=112205192100631&w=2
             *)
            pr "  {\n";
            pr "    HashTable *a;\n";
            pr "    int n;\n";
            pr "    HashPosition p;\n";
            pr "    zval **d;\n";
            pr "    size_t c = 0;\n";
            pr "\n";
            pr "    a = Z_ARRVAL_P (z_%s);\n" n;
            pr "    n = zend_hash_num_elements (a);\n";
            pr "    %s = safe_emalloc (n + 1, sizeof (char *), 0);\n" n;
            pr "    for (zend_hash_internal_pointer_reset_ex (a, &p);\n";
            pr "         zend_hash_get_current_data_ex (a, (void **) &d, &p) == SUCCESS;\n";
            pr "         zend_hash_move_forward_ex (a, &p)) {\n";
            pr "      zval t = **d;\n";
            pr "      zval_copy_ctor (&t);\n";
            pr "      convert_to_string (&t);\n";
            pr "      %s[c] = Z_STRVAL (t);\n" n;
            pr "      c++;\n";
            pr "    }\n";
            pr "    %s[c] = NULL;\n" n;
            pr "  }\n";
            pr "\n"
        | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        ) args;

      (* Optional arguments. *)
      if optargs <> [] then (
        let uc_shortname = String.uppercase shortname in
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "  if (optargs_t_%s != " n;
            (match argt with
             | OBool _ -> pr "((zend_bool)-1)"
             | OInt _ | OInt64 _ -> pr "-1"
             | OString _ -> pr "NULL"
            );
            pr ") {\n";
            pr "    optargs_s.%s = optargs_t_%s;\n" n n;
            pr "    optargs_s.bitmask |= GUESTFS_%s_%s_BITMASK;\n"
              uc_shortname uc_n;
            pr "  }\n"
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
      if optargs = [] then
        pr "  r = guestfs_%s " shortname
      else
        pr "  r = guestfs_%s_argv " shortname;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      pr "\n";

      (* Free up parameters. *)
      List.iter (
        function
        | String n | Device n | Pathname n | Dev_or_Path n
        | FileIn n | FileOut n | Key n
        | OptString n -> ()
        | BufferIn n -> ()
        | StringList n
        | DeviceList n ->
            pr "  {\n";
            pr "    size_t c = 0;\n";
            pr "\n";
            pr "    for (c = 0; %s[c] != NULL; ++c)\n" n;
            pr "      efree (%s[c]);\n" n;
            pr "    efree (%s);\n" n;
            pr "  }\n";
            pr "\n"
        | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        ) args;

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
           pr "  RETURN_STRING (r, 1);\n"
       | RConstOptString _ ->
           pr "  if (r) { RETURN_STRING (r, 1); }\n";
           pr "  else { RETURN_NULL (); }\n"
       | RString _ ->
           pr "  char *r_copy = estrdup (r);\n";
           pr "  free (r);\n";
           pr "  RETURN_STRING (r_copy, 0);\n"
       | RBufferOut _ ->
           pr "  char *r_copy = estrndup (r, size);\n";
           pr "  free (r);\n";
           pr "  RETURN_STRING (r_copy, 0);\n"
       | RStringList _ ->
           pr "  size_t c = 0;\n";
           pr "  array_init (return_value);\n";
           pr "  for (c = 0; r[c] != NULL; ++c) {\n";
           pr "    add_next_index_string (return_value, r[c], 1);\n";
           pr "    free (r[c]);\n";
           pr "  }\n";
           pr "  free (r);\n";
       | RHashtable _ ->
           pr "  size_t c = 0;\n";
           pr "  array_init (return_value);\n";
           pr "  for (c = 0; r[c] != NULL; c += 2) {\n";
           pr "    add_assoc_string (return_value, r[c], r[c+1], 1);\n";
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
  ) all_functions_sorted

and generate_php_struct_code typ cols =
  pr "  array_init (return_value);\n";
  List.iter (
    function
    | name, FString ->
        pr "  add_assoc_string (return_value, \"%s\", r->%s, 1);\n" name name
    | name, FBuffer ->
        pr "  add_assoc_stringl (return_value, \"%s\", r->%s, r->%s_len, 1);\n"
          name name name
    | name, FUUID ->
        pr "  add_assoc_stringl (return_value, \"%s\", r->%s, 32, 1);\n"
          name name
    | name, (FBytes|FUInt64|FInt64|FInt32|FUInt32) ->
        pr "  add_assoc_long (return_value, \"%s\", r->%s);\n"
          name name
    | name, FChar ->
        pr "  add_assoc_stringl (return_value, \"%s\", &r->%s, 1, 1);\n"
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
  pr "    zval *z_elem;\n";
  pr "    ALLOC_INIT_ZVAL (z_elem);\n";
  pr "    array_init (z_elem);\n";
  List.iter (
    function
    | name, FString ->
        pr "    add_assoc_string (z_elem, \"%s\", r->val[c].%s, 1);\n"
          name name
    | name, FBuffer ->
        pr "    add_assoc_stringl (z_elem, \"%s\", r->val[c].%s, r->val[c].%s_len, 1);\n"
          name name name
    | name, FUUID ->
        pr "    add_assoc_stringl (z_elem, \"%s\", r->val[c].%s, 32, 1);\n"
          name name
    | name, (FBytes|FUInt64|FInt64|FInt32|FUInt32) ->
        pr "    add_assoc_long (z_elem, \"%s\", r->val[c].%s);\n"
          name name
    | name, FChar ->
        pr "    add_assoc_stringl (z_elem, \"%s\", &r->val[c].%s, 1, 1);\n"
          name name
    | name, FOptPercent ->
        pr "    add_assoc_double (z_elem, \"%s\", r->val[c].%s);\n"
          name name
  ) cols;
  pr "    add_next_index_zval (return_value, z_elem);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ
