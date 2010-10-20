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

(* Generate ruby bindings. *)
let rec generate_ruby_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>

#include <ruby.h>

#include \"guestfs.h\"

#include \"extconf.h\"

/* For Ruby < 1.9 */
#ifndef RARRAY_LEN
#define RARRAY_LEN(r) (RARRAY((r))->len)
#endif

static VALUE m_guestfs;			/* guestfs module */
static VALUE c_guestfs;			/* guestfs_h handle */
static VALUE e_Error;			/* used for all errors */

static void ruby_guestfs_free (void *p)
{
  if (!p) return;
  guestfs_close ((guestfs_h *) p);
}

static VALUE ruby_guestfs_create (VALUE m)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (!g)
    rb_raise (e_Error, \"failed to create guestfs handle\");

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  /* Wrap it, and make sure the close function is called when the
   * handle goes away.
   */
  return Data_Wrap_Struct (c_guestfs, NULL, ruby_guestfs_free, g);
}

static VALUE ruby_guestfs_close (VALUE gv)
{
  guestfs_h *g;
  Data_Get_Struct (gv, guestfs_h, g);

  ruby_guestfs_free (g);
  DATA_PTR (gv) = NULL;

  return Qnil;
}

";

  List.iter (
    fun (name, (ret, args, optargs as style), _, _, _, _, _) ->
      pr "static VALUE ruby_guestfs_%s (VALUE gv" name;
      List.iter (fun arg -> pr ", VALUE %sv" (name_of_argt arg)) args;
      (* XXX This makes the hash mandatory, meaning that you have
       * to specify {} for no arguments.  We could make it so this
       * can be omitted.  However that is a load of hassle because
       * you have to completely change the way that arguments are
       * passed in.  See:
       * http://www.redhat.com/archives/libvir-list/2008-April/msg00004.html
       *)
      if optargs <> [] then
        pr ", VALUE optargsv";
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g;\n";
      pr "  Data_Get_Struct (gv, guestfs_h, g);\n";
      pr "  if (!g)\n";
      pr "    rb_raise (rb_eArgError, \"%%s: used handle after closing it\", \"%s\");\n"
        name;
      pr "\n";

      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | Key n
        | FileIn n | FileOut n ->
            pr "  Check_Type (%sv, T_STRING);\n" n;
            pr "  const char *%s = StringValueCStr (%sv);\n" n n;
            pr "  if (!%s)\n" n;
            pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
            pr "              \"%s\", \"%s\");\n" n name
        | BufferIn n ->
            pr "  Check_Type (%sv, T_STRING);\n" n;
            pr "  const char *%s = RSTRING (%sv)->ptr;\n" n n;
            pr "  if (!%s)\n" n;
            pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
            pr "              \"%s\", \"%s\");\n" n name;
            pr "  size_t %s_size = RSTRING (%sv)->len;\n" n n
        | OptString n ->
            pr "  const char *%s = !NIL_P (%sv) ? StringValueCStr (%sv) : NULL;\n" n n n
        | StringList n | DeviceList n ->
            pr "  char **%s;\n" n;
            pr "  Check_Type (%sv, T_ARRAY);\n" n;
            pr "  {\n";
            pr "    size_t i, len;\n";
            pr "    len = RARRAY_LEN (%sv);\n" n;
            pr "    %s = guestfs_safe_malloc (g, sizeof (char *) * (len+1));\n"
              n;
            pr "    for (i = 0; i < len; ++i) {\n";
            pr "      VALUE v = rb_ary_entry (%sv, i);\n" n;
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
      ) args;
      pr "\n";

      (* Optional arguments are passed in a final hash parameter. *)
      if optargs <> [] then (
        let uc_name = String.uppercase name in
        pr "  Check_Type (optargsv, T_HASH);\n";
        pr "  struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
        pr "  VALUE v;\n";
        List.iter (
          fun argt ->
            let n = name_of_argt argt in
            let uc_n = String.uppercase n in
            pr "  v = rb_hash_lookup (optargsv, ID2SYM (rb_intern (\"%s\")));\n" n;
            pr "  if (v != Qnil) {\n";
            (match argt with
             | Bool n ->
                 pr "    optargs_s.%s = RTEST (v);\n" n;
             | Int n ->
                 pr "    optargs_s.%s = NUM2INT (v);\n" n;
             | Int64 n ->
                 pr "    optargs_s.%s = NUM2LL (v);\n" n;
             | String _ ->
                 pr "    Check_Type (v, T_STRING);\n";
                 pr "    optargs_s.%s = StringValueCStr (v);\n" n
             | _ -> assert false
            );
            pr "    optargs_s.bitmask |= GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
            pr "  }\n";
        ) optargs;
        pr "\n";
      );

      let error_code =
        match ret with
        | RErr | RInt _ | RBool _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "  const char *r;\n"; "NULL"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
        | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL" in
      pr "\n";

      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _
        | BufferIn _ -> ()
        | StringList n | DeviceList n ->
            pr "  free (%s);\n" n
      ) args;

      pr "  if (r == %s)\n" error_code;
      pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n";
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
           pr "  VALUE rv = rb_str_new2 (r);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
       | RStringList _ ->
           pr "  size_t i, len = 0;\n";
           pr "  for (i = 0; r[i] != NULL; ++i) len++;\n";
           pr "  VALUE rv = rb_ary_new2 (len);\n";
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
           pr "  VALUE rv = rb_hash_new ();\n";
           pr "  size_t i;\n";
           pr "  for (i = 0; r[i] != NULL; i+=2) {\n";
           pr "    rb_hash_aset (rv, rb_str_new2 (r[i]), rb_str_new2 (r[i+1]));\n";
           pr "    free (r[i]);\n";
           pr "    free (r[i+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RBufferOut _ ->
           pr "  VALUE rv = rb_str_new (r, size);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
      );

      pr "}\n";
      pr "\n"
  ) all_functions;

  pr "\
/* Initialize the module. */
void Init__guestfs ()
{
  m_guestfs = rb_define_module (\"Guestfs\");
  c_guestfs = rb_define_class_under (m_guestfs, \"Guestfs\", rb_cObject);
  e_Error = rb_define_class_under (m_guestfs, \"Error\", rb_eStandardError);

#ifdef HAVE_RB_DEFINE_ALLOC_FUNC
  rb_define_alloc_func (c_guestfs, ruby_guestfs_create);
#endif

  rb_define_module_function (m_guestfs, \"create\", ruby_guestfs_create, 0);
  rb_define_method (c_guestfs, \"close\", ruby_guestfs_close, 0);

";
  (* Define the rest of the methods. *)
  List.iter (
    fun (name, (_, args, optargs), _, _, _, _, _) ->
      let nr_args = List.length args + if optargs <> [] then 1 else 0 in
      pr "  rb_define_method (c_guestfs, \"%s\",\n" name;
      pr "        ruby_guestfs_%s, %d);\n" name nr_args
  ) all_functions;

  pr "}\n"

(* Ruby code to return a struct. *)
and generate_ruby_struct_code typ cols =
  pr "  VALUE rv = rb_hash_new ();\n";
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
  pr "  VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  size_t i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    VALUE hv = rb_hash_new ();\n";
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
