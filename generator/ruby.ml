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
open Events

let generate_header = generate_header ~inputs:["generator/ruby.ml"]

(* Generate ruby bindings. *)
let rec generate_ruby_h () =
  generate_header CStyle LGPLv2plus;

  pr "\
#ifndef GUESTFS_RUBY_ACTIONS_H_
#define GUESTFS_RUBY_ACTIONS_H_

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored \"-Wstrict-prototypes\"
#if defined(__GNUC__) && __GNUC__ >= 6 /* gcc >= 6 */
#pragma GCC diagnostic ignored \"-Wshift-overflow\"
#endif
#include <ruby.h>
#pragma GCC diagnostic pop

/* ruby/defines.h defines '_'. */
#ifdef _
#undef _
#endif

#include \"guestfs.h\"
#include \"guestfs-utils.h\" /* Only for POINTER_NOT_IMPLEMENTED */

#include \"extconf.h\"

/* For Ruby < 1.9 */
#ifndef RARRAY_LEN
#define RARRAY_LEN(r) (RARRAY((r))->len)
#endif

/* For Ruby < 1.8 */
#ifndef RSTRING_LEN
#define RSTRING_LEN(r) (RSTRING((r))->len)
#endif

#ifndef RSTRING_PTR
#define RSTRING_PTR(r) (RSTRING((r))->ptr)
#endif

extern VALUE m_guestfs;			/* guestfs module */
extern VALUE c_guestfs;			/* guestfs_h handle */
extern VALUE e_Error;			/* used for all errors */

extern VALUE guestfs_int_ruby_alloc_handle (VALUE klass);
extern VALUE guestfs_int_ruby_initialize_handle (int argc, VALUE *argv, VALUE m);
extern VALUE guestfs_int_ruby_compat_create_handle (int argc, VALUE *argv, VALUE module);
extern VALUE guestfs_int_ruby_close_handle (VALUE gv);
extern VALUE guestfs_int_ruby_set_event_callback (VALUE gv, VALUE cbv, VALUE event_bitmaskv);
extern VALUE guestfs_int_ruby_delete_event_callback (VALUE gv, VALUE event_handlev);
extern VALUE guestfs_int_ruby_event_to_string (VALUE modulev, VALUE eventsv);

";

  List.iter (
    fun f ->
      let ret, args, optargs = f.style in

      pr "extern VALUE guestfs_int_ruby_%s (" f.name;
      if optargs = [] then (
        pr "VALUE gv";
        List.iter
          (fun arg -> pr ", VALUE %sv" (name_of_argt arg))
          args
      ) else
        pr "int argc, VALUE *argv, VALUE gv";
      pr ");\n"
  ) (actions |> external_functions |> sort);

  pr "\n";
  pr "#endif /* GUESTFS_RUBY_ACTIONS_H_ */\n"

and generate_ruby_c actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include \"actions.h\"

";

  List.iter (
    fun f ->
      let ret, args, optargs = f.style in

      (* Generate rdoc. *)
      if is_documented f then (
        let doc = String.replace f.longdesc "C<guestfs_" "C<g." in
        let doc =
          if optargs <> [] then
            doc ^ "\n\nOptional arguments are supplied in the final hash parameter, which is a hash of the argument name to its value.  Pass an empty {} for no optional arguments."
          else doc in
        let doc =
          if f.protocol_limit_warning then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc = pod2text ~width:60 f.name doc in
        let doc = String.concat "\n * " doc in
        let doc = String.trim doc in
        let doc =
          match version_added f with
          | None -> doc
          | Some version -> doc ^ (sprintf "\n *\n * [Since] Added in version %s." version) in
        let doc =
          match f with
          | { deprecated_by = Not_deprecated } -> doc
          | { deprecated_by = Replaced_by alt } ->
            doc ^
              sprintf "\n *\n * [Deprecated] In new code, use rdoc-ref:%s instead." alt
          | { deprecated_by = Deprecated_no_replacement } ->
            doc ^ "\n *\n * [Deprecated] There is no documented replacement" in
        let doc =
          match f.optional with
          | None -> doc
          | Some opt ->
            doc ^ sprintf "\n *\n * [Feature] This function depends on the feature +%s+.  See also {#feature_available}[rdoc-ref:feature_available]." opt in

        (* Because Ruby documentation appears as C comments, we must
         * replace any instance of "/*".
         *)
        let doc = String.replace doc "/*" "/ *" in

        let args = List.map name_of_argt args in
        let args = if optargs <> [] then args @ ["{optargs...}"] else args in
        let args = String.concat ", " args in

        let ret =
          match ret with
          | RErr -> "nil"
          | RBool _ -> "[True|False]"
          | RInt _ -> "fixnum"
          | RInt64 _ -> "fixnum"
          | RConstString _ -> "string"
          | RConstOptString _ -> "string"
          | RString _ -> "string"
          | RBufferOut _ -> "string"
          | RStruct _
          | RHashtable _ -> "hash"
          | RStringList _
          | RStructList _ -> "list" in

        pr "\
/*
 * call-seq:
 *   g.%s(%s) -> %s
 *
 * %s
 *
 * %s
 *
 * [C API] For the C API documentation for this function, see
 *         {guestfs_%s}[http://libguestfs.org/guestfs.3.html#guestfs_%s].
 */
" f.name args ret f.shortdesc doc f.name f.name
      ) else (
        pr "\
/*
 * call-seq:
 *   g.%s
 *
 * :nodoc:
 */
" f.name
      );

      (* Generate the function.  Prototype is completely different
       * depending on whether it's got optargs or not.
       *
       * See:
       * http://stackoverflow.com/questions/7626745/extending-ruby-in-c-how-to-specify-default-argument-values-to-function
       *)
      pr "VALUE\n";
      pr "guestfs_int_ruby_%s (" f.name;
      if optargs = [] then (
        pr "VALUE gv";
        List.iter
          (fun arg -> pr ", VALUE %sv" (name_of_argt arg))
          args
      ) else
        pr "int argc, VALUE *argv, VALUE gv";
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g;\n";
      pr "  Data_Get_Struct (gv, guestfs_h, g);\n";
      pr "  if (!g)\n";
      pr "    rb_raise (rb_eArgError, \"%%s: used handle after closing it\", \"%s\");\n"
        f.name;
      pr "\n";

      (* For optargs case, get the arg VALUEs into local variables.
       * Note for compatibility with old code we're still expecting
       * just a single optional hash parameter as the final element
       * containing all the optargs.
       *)
      if optargs <> [] then (
        let nr_args = List.length args in
        pr "  if (argc < %d || argc > %d)\n" nr_args (nr_args+1);
        pr "    rb_raise (rb_eArgError, \"expecting %d or %d arguments\");\n" nr_args (nr_args+1);
        pr "\n";
        List.iteri (
          fun i arg ->
            pr "  volatile VALUE %sv = argv[%d];\n" (name_of_argt arg) i
        ) args;
        pr "  volatile VALUE optargsv = argc > %d ? argv[%d] : rb_hash_new ();\n"
          nr_args nr_args;
        pr "\n"
      );

      (match f.deprecated_by with
      | Not_deprecated -> ()
      | Replaced_by alt ->
        pr "  rb_warn (\"Guestfs#%s is deprecated; use #%s instead\");\n" f.name alt;
        pr "\n"
      | Deprecated_no_replacement ->
        pr "  rb_warn (\"Guestfs#%s is deprecated\");\n" f.name;
        pr "\n"
      );

      List.iter (
        function
        | String (_, n) ->
          pr "  const char *%s = StringValueCStr (%sv);\n" n n;
        | BufferIn n ->
          pr "  Check_Type (%sv, T_STRING);\n" n;
          pr "  const char *%s = RSTRING_PTR (%sv);\n" n n;
          pr "  if (!%s)\n" n;
          pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
          pr "              \"%s\", \"%s\");\n" n f.name;
          pr "  size_t %s_size = RSTRING_LEN (%sv);\n" n n
        | OptString n ->
          pr "  const char *%s = !NIL_P (%sv) ? StringValueCStr (%sv) : NULL;\n" n n n
        | StringList (_, n) ->
          pr "  char **%s;\n" n;
          pr "  Check_Type (%sv, T_ARRAY);\n" n;
          pr "  {\n";
          pr "    size_t i, len;\n";
          pr "    len = RARRAY_LEN (%sv);\n" n;
          pr "    %s = ALLOC_N (char *, len+1);\n"
            n;
          pr "    for (i = 0; i < len; ++i) {\n";
          pr "      volatile VALUE v = rb_ary_entry (%sv, i);\n" n;
          pr "      %s[i] = StringValueCStr (v);\n" n;
          pr "    }\n";
          pr "    %s[len] = NULL;\n" n;
          pr "  }\n";
        | Bool n ->
          pr "  int %s = RTEST (%sv);\n" n n
        | Int n ->
          pr "  int %s = NUM2INT (%sv);\n" n n
        | Int64 n ->
          pr "  long long %s = NUM2LL (%sv);\n" n n
        | Pointer (t, n) ->
          pr "  (void) %sv;\n" n;
          pr "  void * /* %s */ %s = POINTER_NOT_IMPLEMENTED (\"%s\");\n" t n t
      ) args;
      pr "\n";

      (* Optional arguments are passed in a final hash parameter. *)
      if optargs <> [] then (
        pr "  Check_Type (optargsv, T_HASH);\n";
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" f.c_function;
        pr "  struct %s *optargs = &optargs_s;\n" f.c_function;
        pr "  volatile VALUE v;\n";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase_ascii n in
            pr "  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern (\"%s\")));\n" n;
            pr "  if (v != Qnil) {\n";
            (match argt with
             | OBool n ->
                 pr "    optargs_s.%s = RTEST (v);\n" n;
             | OInt n ->
                 pr "    optargs_s.%s = NUM2INT (v);\n" n;
             | OInt64 n ->
                 pr "    optargs_s.%s = NUM2LL (v);\n" n;
             | OString _ ->
                 pr "    optargs_s.%s = StringValueCStr (v);\n" n
             | OStringList _ ->
               pr "  Check_Type (v, T_ARRAY);\n";
               pr "  {\n";
               pr "    size_t i, len;\n";
               pr "    char **r;\n";
               pr "\n";
               pr "    len = RARRAY_LEN (v);\n";
               pr "    r = ALLOC_N (char *, len+1);\n";
               pr "    for (i = 0; i < len; ++i) {\n";
               pr "      volatile VALUE sv = rb_ary_entry (v, i);\n";
               pr "      r[i] = StringValueCStr (sv);\n";
               pr "    }\n";
               pr "    r[len] = NULL;\n";
               pr "    optargs_s.%s = r;\n" n;
               pr "  }\n"
            );
            pr "    optargs_s.bitmask |= %s_%s_BITMASK;\n" f.c_optarg_prefix uc_n;
            pr "  }\n";
        ) optargs;
        pr "\n";
      );

      (match ret with
       | RErr | RInt _ | RBool _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ | RConstOptString _ ->
           pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) ->
           pr "  struct guestfs_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  char *r;\n";
           pr "  size_t size;\n"
      );
      pr "\n";

      pr "  r = %s " f.c_function;
      generate_c_call_args ~handle:"g" f.style;
      pr ";\n";

      List.iter (
        function
        | String _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ | Pointer _ -> ()
        | StringList (_, n) ->
            pr "  free (%s);\n" n
      ) args;

      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1)\n";
           pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n"
       | `ErrorIsNULL ->
           pr "  if (r == NULL)\n";
           pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n"
      );
      pr "\n";

      (match ret with
       | RErr ->
           pr "  return Qnil;\n"
       | RInt _ | RBool _ ->
           pr "  return INT2NUM (r);\n"
       | RInt64 _ ->
           pr "  return ULL2NUM (r);\n"
       | RConstString _ ->
           pr "  return rb_str_new2 (r);\n";
       | RConstOptString _ ->
           pr "  if (r)\n";
           pr "    return rb_str_new2 (r);\n";
           pr "  else\n";
           pr "    return Qnil;\n";
       | RString _ ->
           pr "  volatile VALUE rv = rb_str_new2 (r);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
       | RStringList _ ->
           pr "  size_t i, len = 0;\n";
           pr "  for (i = 0; r[i] != NULL; ++i) len++;\n";
           pr "  volatile VALUE rv = rb_ary_new2 (len);\n";
           pr "  for (i = 0; r[i] != NULL; ++i) {\n";
           pr "    rb_ary_push (rv, rb_str_new2 (r[i]));\n";
           pr "    free (r[i]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RStruct (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_code typ cols
       | RStructList (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_list_code typ cols
       | RHashtable _ ->
           pr "  volatile VALUE rv = rb_hash_new ();\n";
           pr "  size_t i;\n";
           pr "  for (i = 0; r[i] != NULL; i+=2) {\n";
           pr "    rb_hash_aset (rv, rb_str_new2 (r[i]), rb_str_new2 (r[i+1]));\n";
           pr "    free (r[i]);\n";
           pr "    free (r[i+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RBufferOut _ ->
           pr "  volatile VALUE rv = rb_str_new (r, size);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
      );

      pr "}\n";
      pr "\n"
  ) (actions |> external_functions |> sort)

and generate_ruby_module () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include \"actions.h\"

VALUE m_guestfs;                  /* guestfs module */
VALUE c_guestfs;                  /* guestfs_h handle */
VALUE e_Error;                    /* used for all errors */

extern void Init__guestfs (void); /* keep GCC warnings happy */

/* Initialize the module. */
void
Init__guestfs (void)
{
  m_guestfs = rb_define_module (\"Guestfs\");
  c_guestfs = rb_define_class_under (m_guestfs, \"Guestfs\", rb_cObject);
  e_Error = rb_define_class_under (m_guestfs, \"Error\", rb_eStandardError);

#ifdef HAVE_RB_DEFINE_ALLOC_FUNC
#ifndef HAVE_TYPE_RB_ALLOC_FUNC_T
#define rb_alloc_func_t void*
#endif
  rb_define_alloc_func (c_guestfs, (rb_alloc_func_t) guestfs_int_ruby_alloc_handle);
#endif

  rb_define_method (c_guestfs, \"initialize\",
                    guestfs_int_ruby_initialize_handle, -1);
  rb_define_method (c_guestfs, \"close\",
                    guestfs_int_ruby_close_handle, 0);
  rb_define_method (c_guestfs, \"set_event_callback\",
                    guestfs_int_ruby_set_event_callback, 2);
  rb_define_method (c_guestfs, \"delete_event_callback\",
                    guestfs_int_ruby_delete_event_callback, 1);
  rb_define_module_function (m_guestfs, \"event_to_string\",
                             guestfs_int_ruby_event_to_string, 1);

  /* For backwards compatibility with older code, define a ::create
   * module function.
   */
  rb_define_module_function (m_guestfs, \"create\",
                             guestfs_int_ruby_compat_create_handle, -1);

";

  (* Constants. *)
  List.iter (
    fun (name, bitmask) ->
      pr "  rb_define_const (m_guestfs, \"EVENT_%s\",\n"
        (String.uppercase_ascii name);
      pr "                   ULL2NUM (UINT64_C (0x%x)));\n" bitmask;
  ) events;
  pr "  rb_define_const (m_guestfs, \"EVENT_ALL\",\n";
  pr "                   ULL2NUM (UINT64_C (0x%x)));\n" all_events_bitmask;
  pr "\n";

  (* Methods. *)
  List.iter (
    fun { name; style = _, args, optargs; non_c_aliases } ->
      let nr_args = if optargs = [] then List.length args else -1 in
      pr "  rb_define_method (c_guestfs, \"%s\",\n" name;
      pr "                    guestfs_int_ruby_%s, %d);\n" name nr_args;

      (* Aliases. *)
      List.iter (
        fun alias ->
          pr "  rb_define_method (c_guestfs, \"%s\",\n" alias;
          pr "                    guestfs_int_ruby_%s, %d);\n" name nr_args
      ) non_c_aliases
  ) (actions |> external_functions |> sort);

  pr "}\n"

(* Ruby code to return a struct. *)
and generate_ruby_struct_code typ cols =
  pr "  volatile VALUE rv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new2 (r->%s));\n" name name
    | name, FBuffer ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, r->%s_len));\n" name name name
    | name, FUUID ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
    | name, FInt64 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), LL2NUM (r->%s));\n" name name
    | name, FUInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), UINT2NUM (r->%s));\n" name name
    | name, FInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), INT2NUM (r->%s));\n" name name
    | name, FOptPercent ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_dbl2big (r->%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
  ) cols;
  pr "  guestfs_free_%s (r);\n" typ;
  pr "  return rv;\n"

(* Ruby code to return a struct list. *)
and generate_ruby_struct_list_code typ cols =
  pr "  volatile VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  size_t i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    volatile VALUE hv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new2 (r->val[i].%s));\n" name name
    | name, FBuffer ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, r->val[i].%s_len));\n" name name name
    | name, FUUID ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
    | name, FInt64 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), LL2NUM (r->val[i].%s));\n" name name
    | name, FUInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), UINT2NUM (r->val[i].%s));\n" name name
    | name, FInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), INT2NUM (r->val[i].%s));\n" name name
    | name, FOptPercent ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_dbl2big (r->val[i].%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
  ) cols;
  pr "    rb_ary_push (rv, hv);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ;
  pr "  return rv;\n"
