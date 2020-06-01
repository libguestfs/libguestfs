(* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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

let generate_header = generate_header ~inputs:["generator/erlang.ml"]

let rec generate_erlang_erl () =
  generate_header ErlangStyle LGPLv2plus;

  pr "-module(guestfs).\n";
  pr "\n";
  pr "-export([create/0, create/1, close/1, init/1]).\n";
  pr "\n";

  (* Export the public actions. *)
  List.iter (
    fun { name; style = _, args, optargs; non_c_aliases = aliases } ->
      let nr_args = List.length args in
      let export name =
        if optargs = [] then
          pr "-export([%s/%d]).\n" name (nr_args+1)
        else
          pr "-export([%s/%d, %s/%d]).\n" name (nr_args+1) name (nr_args+2)
      in
      export name;
      List.iter export aliases
  ) (actions |> external_functions |> sort);

  pr "\n";

  pr "\
create() ->
  create(\"erl-guestfs\").

create(ExtProg) ->
  G = spawn(?MODULE, init, [ExtProg]),
  {ok, G}.

close(G) ->
  G ! close,
  ok.

call_port(G, Args) ->
  G ! {call, self(), Args},
  receive
    {guestfs, Result} ->
      Result
  end.

init(ExtProg) ->
  process_flag(trap_exit, true),
  Port = open_port({spawn, ExtProg}, [{packet, 4}, binary]),
  loop(Port).
loop(Port) ->
  receive
    {call, Caller, Args} ->
      Port ! { self(), {command, term_to_binary(Args)}},
      receive
        {Port, {data, Result}} ->
          Caller ! { guestfs, binary_to_term(Result)}
      end,
      loop(Port);
    close ->
      port_close(Port),
      exit(normal);
    { 'EXIT', Port, _ } ->
      exit(port_terminated)
  end.

";

  (* These bindings just marshal the parameters and call the back-end
   * process which dispatches them to the port.
   *)
  List.iter (
    fun { name; style = _, args, optargs; non_c_aliases = aliases } ->
      pr "%s(G" name;
      List.iter (
        fun arg ->
          pr ", %s" (String.capitalize_ascii (name_of_argt arg))
      ) args;
      if optargs <> [] then
        pr ", Optargs";
      pr ") ->\n";

      pr "  call_port(G, {%s" name;
      List.iter (
        fun arg ->
          pr ", %s" (String.capitalize_ascii (name_of_argt arg))
      ) args;
      if optargs <> [] then
        pr ", Optargs";
      pr "}).\n";

      (* For functions with optional arguments, make a variant that
       * has no optarg array, which just calls the function above with
       * an empty list as the final arg.
       *)
      if optargs <> [] then (
        pr "%s(G" name;
        List.iter (
          fun arg ->
            pr ", %s" (String.capitalize_ascii (name_of_argt arg))
        ) args;
        pr ") ->\n";

        pr "  %s(G" name;
        List.iter (
          fun arg ->
            pr ", %s" (String.capitalize_ascii (name_of_argt arg))
        ) args;
        pr ", []";
        pr ").\n"
      );

      (* Aliases. *)
      List.iter (
        fun alias ->
          pr "%s(G" alias;
          List.iter (
            fun arg ->
              pr ", %s" (String.capitalize_ascii (name_of_argt arg))
          ) args;
          if optargs <> [] then
            pr ", Optargs";
          pr ") ->\n";

          pr "  %s(G" name;
          List.iter (
            fun arg ->
              pr ", %s" (String.capitalize_ascii (name_of_argt arg))
          ) args;
          if optargs <> [] then
            pr ", Optargs";
          pr ").\n";

          if optargs <> [] then (
            pr "%s(G" alias;
            List.iter (
              fun arg ->
                pr ", %s" (String.capitalize_ascii (name_of_argt arg))
            ) args;
            pr ") ->\n";

            pr "  %s(G" name;
            List.iter (
              fun arg ->
                pr ", %s" (String.capitalize_ascii (name_of_argt arg))
            ) args;
            pr ").\n"
          )
      ) aliases;

      pr "\n"
  ) (actions |> external_functions |> sort)

and generate_erlang_actions_h () =
  generate_header CStyle GPLv2plus;

  pr "\
#ifndef GUESTFS_ERLANG_ACTIONS_H_
#define GUESTFS_ERLANG_ACTIONS_H_

extern guestfs_h *g;

extern int dispatch (ei_x_buff *retbuff, const char *buff, int *index);
extern int make_error (ei_x_buff *retbuff, const char *funname);
extern int unknown_optarg (ei_x_buff *retbuff, const char *funname, const char *optargname);
extern int unknown_function (ei_x_buff *retbuff, const char *fun);
extern int make_string_list (ei_x_buff *buff, char **r);
extern int make_table (ei_x_buff *buff, char **r);
extern int make_bool (ei_x_buff *buff, int r);
extern int atom_equals (const char *atom, const char *name);
extern int decode_string_list (const char *buff, int *index, char ***res);
extern int decode_string (const char *buff, int *index, char **res);
extern int decode_binary (const char *buff, int *index, char **res, size_t *size);
extern int decode_bool (const char *buff, int *index, int *res);
extern int decode_int (const char *buff, int *index, int *res);
extern int decode_int64 (const char *buff, int *index, int64_t *res);

";

  let emit_copy_list_decl typ =
    pr "int make_%s_list (ei_x_buff *buff, const struct guestfs_%s_list *%ss);\n"
       typ typ typ;
  in
  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "int make_%s (ei_x_buff *buff, const struct guestfs_%s *%s);\n" typ typ typ;
  ) external_structs;

  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        emit_copy_list_decl typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> external_functions));

  pr "\n";

  List.iter (
    fun { name } ->
      pr "int run_%s (ei_x_buff *retbuff, const char *buff, int *index);\n" name
  ) (actions |> external_functions |> sort);

  pr "\n";
  pr "#endif /* GUESTFS_ERLANG_ACTIONS_H_ */\n"

and generate_erlang_structs () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#include <ei.h>

#include \"guestfs.h\"
#include \"guestfs-utils.h\"

#include \"actions.h\"
";

  (* Struct copy functions. *)
  let emit_copy_list_function typ =
    pr "\n";
    pr "int\n";
    pr "make_%s_list (ei_x_buff *buff, const struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  size_t len = %ss->len;\n" typ;
    pr "  size_t i;\n";
    pr "\n";
    pr "  if (ei_x_encode_list_header (buff, len) != 0) return -1;\n";
    pr "  for (i = 0; i < len; ++i) {\n";
    pr "    if (make_%s (buff, &%ss->val[i]) != 0) return -1;\n" typ typ;
    pr "  }\n";
    pr "  if (len > 0)\n";
    pr "    if (ei_x_encode_empty_list (buff) != 0) return -1;\n";
    pr "\n";
    pr "  return 0;\n";
    pr "}\n";
  in

  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "\n";
      pr "int\n";
      pr "make_%s (ei_x_buff *buff, const struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  if (ei_x_encode_list_header (buff, %d) !=0) return -1;\n" (List.length cols);
      pr "\n";
      List.iteri (
        fun i col ->
          (match col with
           | name, FString ->
               pr "  if (ei_x_encode_string (buff, %s->%s) != 0) return -1;\n" typ name
           | name, FBuffer ->
               pr "  if (ei_x_encode_string_len (buff, %s->%s, %s->%s_len) != 0) return -1;\n"
                 typ name typ name
           | name, FUUID ->
               pr "  if (ei_x_encode_string_len (buff, %s->%s, 32) != 0) return -1;\n" typ name
           | name, (FBytes|FInt64|FUInt64) ->
               pr "  if (ei_x_encode_longlong (buff, %s->%s) != 0) return -1;\n" typ name
           | name, (FInt32|FUInt32) ->
               pr "  if (ei_x_encode_long (buff, %s->%s) != 0) return -1;\n" typ name
           | name, FOptPercent ->
               pr "  if (%s->%s >= 0) {\n" typ name;
               pr "    if (ei_x_encode_double (buff, %s->%s) != 0) return -1;\n" typ name;
               pr "  } else {\n";
               pr "    if (ei_x_encode_atom (buff, \"undefined\") != 0) return -1;\n";
               pr "  }\n"
           | name, FChar ->
               pr "  if (ei_x_encode_char (buff, %s->%s) != 0) return -1;\n" typ name
          );
      ) cols;
      if cols <> [] then (
        pr "\n";
        pr "  if (ei_x_encode_empty_list (buff) != 0) return -1;\n"
      );
      pr "\n";
      pr "  return 0;\n";
      pr "}\n";
  ) external_structs;

  (* Emit a copy_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_copy_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> external_functions));

and generate_erlang_actions actions () =
  generate_header CStyle GPLv2plus;

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

#include <ei.h>

#include \"guestfs.h\"
#include \"guestfs-utils.h\"

#include \"actions.h\"
";

  (* The wrapper functions. *)
  List.iter (
    fun { name; style = (ret, args, optargs as style);
          c_function; c_optarg_prefix } ->
      pr "\n";
      pr "int\n";
      pr "run_%s (ei_x_buff *retbuff, const char *buff, int *idx)\n" name;
      pr "{\n";

      List.iteri (
        fun i ->
          function
          | String (_, n) ->
            pr "  CLEANUP_FREE char *%s;\n" n;
            pr "  if (decode_string (buff, idx, &%s) != 0) return -1;\n" n
          | OptString n ->
            pr "  CLEANUP_FREE char *%s;\n" n;
            pr "  char %s_opt[MAXATOMLEN];\n" n;
            pr "  if (ei_decode_atom(buff, idx, %s_opt) == 0) {\n" n;
            pr "    if (atom_equals (%s_opt, \"undefined\"))\n" n;
            pr "      %s = NULL;\n" n;
            pr "    else\n";
            pr "      %s = %s_opt;\n" n n;
            pr "  } else {\n";
            pr "    if (decode_string (buff, idx, &%s) != 0) return -1;\n" n;
            pr "  }\n"
          | BufferIn n ->
            pr "  CLEANUP_FREE char *%s;\n" n;
            pr "  size_t %s_size;\n" n;
            pr "  if (decode_binary (buff, idx, &%s, &%s_size) != 0) return -1;\n" n n
          | StringList (_, n) ->
            pr "  CLEANUP_FREE_STRING_LIST char **%s;\n" n;
            pr "  if (decode_string_list (buff, idx, &%s) != 0) return -1;\n" n
          | Bool n ->
            pr "  int %s;\n" n;
            pr "  if (decode_bool (buff, idx, &%s) != 0) return -1;\n" n
          | Int n ->
            pr "  int %s;\n" n;
            pr "  if (decode_int (buff, idx, &%s) != 0) return -1;\n" n
          | Int64 n ->
            pr "  int64_t %s;\n" n;
            pr "  if (decode_int64 (buff, idx, &%s) != 0) return -1;\n" n
          | Pointer (t, n) ->
            pr "  void * /* %s */ %s = POINTER_NOT_IMPLEMENTED (\"%s\");\n" t n t
      ) args;

      (* Optional arguments. *)
      if optargs <> [] then (
        pr "\n";
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" c_function;
        pr "  struct %s *optargs = &optargs_s;\n" c_function;
        pr "  int optargsize;\n";
        pr "  if (ei_decode_list_header (buff, idx, &optargsize) != 0) return -1;\n";
        pr "  for (int i = 0; i < optargsize; i++) {\n";
        pr "    int hd;\n";
        pr "    if (ei_decode_tuple_header (buff, idx, &hd) != 0) return -1;\n";
        pr "    char hd_name[MAXATOMLEN];\n";
        pr "    if (ei_decode_atom (buff, idx, hd_name) != 0) return -1;\n";
        pr "\n";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase_ascii n in
            pr "    if (atom_equals (hd_name, \"%s\")) {\n" n;
            pr "      optargs_s.bitmask |= %s_%s_BITMASK;\n"
              c_optarg_prefix uc_n;
            pr "      ";
            (match argt with
             | OBool _ -> pr "if (decode_bool (buff, idx, &optargs_s.%s) != 0) return -1;" n
             | OInt _ -> pr "if (decode_int (buff, idx, &optargs_s.%s) != 0) return -1" n
             | OInt64 _ -> pr "if (decode_int64 (buff, idx, &optargs_s.%s) != 0) return -1" n
             | OString _ -> pr "if (decode_string (buff, idx, (char **) &optargs_s.%s) != 0) return -1" n
             | OStringList n -> pr "if (decode_string_list (buff, idx, (char ***) &optargs_s.%s) != 0) return -1" n
            );
            pr ";\n";
            pr "    }\n";
            pr "    else\n";
        ) optargs;
        pr "      return unknown_optarg (retbuff, \"%s\", hd_name);\n" name;
        pr "  }\n";
        pr "  if (optargsize > 0 && buff[*idx] == ERL_NIL_EXT)\n";
        pr "    (*idx)++;\n";
        pr "\n";
      );

      (match ret with
       | RErr -> pr "  int r;\n"
       | RInt _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RBool _ -> pr "  int r;\n"
       | RConstString _ | RConstOptString _ ->
           pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
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
      pr "\n";

      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Free strings if we copied them above. *)
      List.iter (
        function
        | OBool _ | OInt _ | OInt64 _ -> ()
        | OString n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if ((optargs_s.bitmask & %s_%s_BITMASK))\n"
              c_optarg_prefix uc_n;
            pr "    free ((char *) optargs_s.%s);\n" n
        | OStringList n ->
            let uc_n = String.uppercase_ascii n in
            pr "  if ((optargs_s.bitmask & %s_%s_BITMASK))\n"
              c_optarg_prefix uc_n;
            pr "    guestfs_int_free_string_list ((char **) optargs_s.%s);\n" n
      ) optargs;

      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1)\n";
           pr "    return make_error (retbuff, \"%s\");\n" name;
       | `ErrorIsNULL ->
           pr "  if (r == NULL)\n";
           pr "    return make_error (retbuff, \"%s\");\n" name;
      );
      pr "\n";

      (match ret with
       | RErr -> pr "  if (ei_x_encode_atom (retbuff, \"ok\") != 0) return -1;\n"
       | RInt _ -> pr "  if (ei_x_encode_long (retbuff, r) != 0) return -1;\n"
       | RInt64 _ -> pr "  if (ei_x_encode_longlong (retbuff, r) != 0) return -1;\n"
       | RBool _ -> pr "  if (make_bool (retbuff, r) != 0) return -1;\n"
       | RConstString _ -> pr "  if (ei_x_encode_string (retbuff, r) != 0) return -1;\n"
       | RConstOptString _ ->
           pr "  if (r) {\n";
           pr "    if (ei_x_encode_string (retbuff, r) != 0) return -1;\n";
           pr "  } else {\n";
           pr "    if (ei_x_encode_atom (retbuff, \"undefined\") != 0) return -1;\n";
           pr "  }\n"
       | RString _ ->
           pr "  if (ei_x_encode_string (retbuff, r) != 0) return -1;\n";
           pr "  free (r);\n";
       | RStringList _ ->
           pr "  if (make_string_list (retbuff, r) != 0) return -1;\n";
           pr "  guestfs_int_free_string_list (r);\n"
       | RStruct (_, typ) ->
           pr "  if (make_%s (retbuff, r) != 0) return -1;\n" typ;
           pr "  guestfs_free_%s (r);\n" typ
       | RStructList (_, typ) ->
           pr "  if (make_%s_list (retbuff, r) != 0) return -1;\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ
       | RHashtable _ ->
           pr "  if (make_table (retbuff, r) != 0) return -1;\n";
           pr "  guestfs_int_free_string_list (r);\n"
       | RBufferOut _ ->
           pr "  if (ei_x_encode_binary (retbuff, r, size) != 0) return -1;\n";
           pr "  free (r);\n";
      );

      pr "  return 0;\n";
      pr "}\n";
  ) (actions |> external_functions |> sort);

and generate_erlang_dispatch () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#include <ei.h>

#include \"guestfs.h\"
#include \"guestfs-utils.h\"

#include \"actions.h\"

int
dispatch (ei_x_buff *retbuff, const char *buff, int *index)
{
  int arity;
  char fun[MAXATOMLEN];

  if (ei_decode_tuple_header (buff, index, &arity) != 0) return -1;
  if (ei_decode_atom (buff, index, fun) != 0) return -1;

  /* XXX We should use gperf here. */
  ";

  List.iter (
    fun { name; style = ret, args, optargs } ->
      pr "if (atom_equals (fun, \"%s\"))\n" name;
      pr "    return run_%s (retbuff, buff, index);\n" name;
      pr "  else ";
  ) (actions |> external_functions |> sort);

  pr "return unknown_function (retbuff, fun);
}
";
