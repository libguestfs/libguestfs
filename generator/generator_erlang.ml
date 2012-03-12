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

open Generator_types
open Generator_utils
open Generator_pr
open Generator_docstrings
open Generator_optgroups
open Generator_actions
open Generator_structs
open Generator_c
open Generator_events

let rec generate_erlang_erl () =
  generate_header ErlangStyle LGPLv2plus;

  pr "-module(guestfs).\n";
  pr "\n";
  pr "-export([create/0, create/1, close/1, init/1]).\n";
  pr "\n";

  (* Export the public actions. *)
  List.iter (
    fun (name, (_, args, optargs), _, _, _, _, _) ->
      let nr_args = List.length args in
      if optargs = [] then
        pr "-export([%s/%d]).\n" name (nr_args+1)
      else
        pr "-export([%s/%d, %s/%d]).\n" name (nr_args+1) name (nr_args+2)
  ) all_functions_sorted;

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
    fun (name, (_, args, optargs), _, _, _, _, _) ->
      pr "%s(G" name;
      List.iter (
        fun arg ->
          pr ", %s" (String.capitalize (name_of_argt arg))
      ) args;
      if optargs <> [] then
        pr ", Optargs";
      pr ") ->\n";

      pr "  call_port(G, {%s" name;
      List.iter (
        fun arg ->
          pr ", %s" (String.capitalize (name_of_argt arg))
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
            pr ", %s" (String.capitalize (name_of_argt arg))
        ) args;
        pr ") ->\n";

        pr "  %s(G" name;
        List.iter (
          fun arg ->
            pr ", %s" (String.capitalize (name_of_argt arg))
        ) args;
        pr ", []";
        pr ").\n"
      );

      pr "\n"
  ) all_functions_sorted

and generate_erlang_c () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <erl_interface.h>
#include <ei.h>

#include \"guestfs.h\"

extern guestfs_h *g;

extern ETERM *dispatch (ETERM *message);
extern int atom_equals (ETERM *atom, const char *name);
extern ETERM *make_error (const char *funname);
extern ETERM *unknown_optarg (const char *funname, ETERM *optargname);
extern ETERM *unknown_function (ETERM *fun);
extern ETERM *make_string_list (char **r);
extern ETERM *make_table (char **r);
extern ETERM *make_bool (int r);
extern char **get_string_list (ETERM *term);
extern int get_bool (ETERM *term);
extern void free_strings (char **r);

#define ARG(i) (ERL_TUPLE_ELEMENT(message,(i)+1))

";

  (* Struct copy functions. *)
  let emit_copy_list_function typ =
    pr "static ETERM *\n";
    pr "make_%s_list (const struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  ETERM *t[%ss->len];\n" typ;
    pr "  size_t i;\n";
    pr "\n";
    pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
    pr "    t[i] = make_%s (&%ss->val[i]);\n" typ typ;
    pr "\n";
    pr "  return erl_mk_list (t, %ss->len);\n" typ;
    pr "}\n";
    pr "\n";
  in

  List.iter (
    fun (typ, cols) ->
      pr "static ETERM *\n";
      pr "make_%s (const struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  ETERM *t[%d];\n" (List.length cols);
      pr "\n";
      iteri (
        fun i col ->
          (match col with
           | name, FString ->
               pr "  t[%d] = erl_mk_string (%s->%s);\n" i typ name
           | name, FBuffer ->
               pr "  t[%d] = erl_mk_estring (%s->%s, %s->%s_len);\n"
                 i typ name typ name
           | name, FUUID ->
               pr "  t[%d] = erl_mk_estring (%s->%s, 32);\n" i typ name
           | name, (FBytes|FInt64|FUInt64) ->
               pr "  t[%d] = erl_mk_longlong (%s->%s);\n" i typ name
           | name, (FInt32|FUInt32) ->
               pr "  t[%d] = erl_mk_int (%s->%s);\n" i typ name
           | name, FOptPercent ->
               pr "  if (%s->%s >= 0)\n" typ name;
               pr "    t[%d] = erl_mk_float (%s->%s);\n" i typ name;
               pr "  else\n";
               pr "    t[%d] = erl_mk_atom (\"undefined\");\n" i;
           | name, FChar ->
               pr "  t[%d] = erl_mk_int (%s->%s);\n" i typ name
          );
      ) cols;
      pr "\n";
      pr "  return erl_mk_list (t, %d);\n" (List.length cols);
      pr "}\n";
      pr "\n";
  ) structs;

  (* Emit a copy_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_copy_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* The wrapper functions. *)
  List.iter (
    fun (name, ((ret, args, optargs) as style), _, _, _, _, _) ->
      pr "static ETERM *\n";
      pr "run_%s (ETERM *message)\n" name;
      pr "{\n";

      iteri (
        fun i ->
          function
          | Pathname n
          | Device n | Dev_or_Path n
          | String n
          | FileIn n
          | FileOut n
          | Key n ->
            pr "  char *%s = erl_iolist_to_string (ARG (%d));\n" n i
          | OptString n ->
            pr "  char *%s;\n" n;
            pr "  if (atom_equals (ARG (%d), \"undefined\"))\n" i;
            pr "    %s = NULL;\n" n;
            pr "  else\n";
            pr "    %s = erl_iolist_to_string (ARG (%d));\n" n i
          | BufferIn n ->
            pr "  size_t %s_size = erl_iolist_length (ARG (%d));\n" n i;
            pr "  char *%s = erl_iolist_to_string (ARG (%d));\n" n i
          | StringList n | DeviceList n ->
            pr "  char **%s = get_string_list (ARG (%d));\n" n i
          | Bool n ->
            pr "  int %s = get_bool (ARG (%d));\n" n i
          | Int n ->
            pr "  int %s = ERL_INT_VALUE (ARG (%d));\n" n i
          | Int64 n ->
            pr "  int64_t %s = ERL_LL_VALUE (ARG (%d));\n" n i
          | Pointer (t, n) ->
            assert false
      ) args;

      let uc_name = String.uppercase name in

      (* Optional arguments. *)
      if optargs <> [] then (
        pr "\n";
        pr "  struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name;
        pr "  ETERM *optargst = ARG (%d);\n" (List.length args);
        pr "  while (!ERL_IS_EMPTY_LIST (optargst)) {\n";
        pr "    ETERM *hd = ERL_CONS_HEAD (optargst);\n";
        pr "    ETERM *hd_name = ERL_TUPLE_ELEMENT (hd, 0);\n";
        pr "    ETERM *hd_value = ERL_TUPLE_ELEMENT (hd, 1);\n";
        pr "\n";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            pr "    if (atom_equals (hd_name, \"%s\")) {\n" n;
            pr "      optargs_s.bitmask |= GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
            pr "      optargs_s.%s = " n;
            (match argt with
             | OBool _ -> pr "get_bool (hd_value)"
             | OInt _ -> pr "ERL_INT_VALUE (hd_value)"
             | OInt64 _ -> pr "ERL_LL_VALUE (hd_value)"
             | OString _ -> pr "erl_iolist_to_string (hd_value)"
            );
            pr ";\n";
            pr "    }\n";
            pr "    else\n";
        ) optargs;
        pr "      return unknown_optarg (\"%s\", hd_name);\n" name;
        pr "    optargst = ERL_CONS_TAIL (optargst);\n";
        pr "  }\n";
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

      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Free strings if we copied them above. *)
      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | OptString n
        | FileIn n | FileOut n | BufferIn n | Key n ->
            pr "  free (%s);\n" n
        | StringList n | DeviceList n ->
            pr "  free_strings (%s);\n" n;
        | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
      ) args;
      List.iter (
        function
        | OBool _ | OInt _ | OInt64 _ -> ()
        | OString n ->
            let uc_n = String.uppercase n in
            pr "  if ((optargs_s.bitmask & GUESTFS_%s_%s_BITMASK))\n"
              uc_name uc_n;
            pr "    free ((char *) optargs_s.%s);\n" n
      ) optargs;

      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
           pr "  if (r == -1)\n";
           pr "    return make_error (\"%s\");\n" name;
       | `ErrorIsNULL ->
           pr "  if (r == NULL)\n";
           pr "    return make_error (\"%s\");\n" name;
      );
      pr "\n";

      (match ret with
       | RErr -> pr "  return erl_mk_atom (\"ok\");\n"
       | RInt _ -> pr "  return erl_mk_int (r);\n"
       | RInt64 _ -> pr "  return erl_mk_longlong (r);\n"
       | RBool _ -> pr "  return make_bool (r);\n"
       | RConstString _ -> pr "  return erl_mk_string (r);\n"
       | RConstOptString _ ->
           pr "  ETERM *rt;\n";
           pr "  if (r)\n";
           pr "    rt = erl_mk_string (r);\n";
           pr "  else\n";
           pr "    rt = erl_mk_atom (\"undefined\");\n";
           pr "  return rt;\n"
       | RString _ ->
           pr "  ETERM *rt = erl_mk_string (r);\n";
           pr "  free (r);\n";
           pr "  return rt;\n"
       | RStringList _ ->
           pr "  ETERM *rt = make_string_list (r);\n";
           pr "  free_strings (r);\n\n";
           pr "  return rt;\n"
       | RStruct (_, typ) ->
           pr "  ETERM *rt = make_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ;
           pr "  return rt;\n"
       | RStructList (_, typ) ->
           pr "  ETERM *rt = make_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ;
           pr "  return rt;\n"
       | RHashtable _ ->
           pr "  ETERM *rt = make_table (r);\n";
           pr "  free_strings (r);\n";
           pr "  return rt;\n"
       | RBufferOut _ ->
           pr "  ETERM *rt = erl_mk_estring (r, size);\n";
           pr "  free (r);\n";
           pr "  return rt;\n"
      );

      pr "}\n";
      pr "\n";
  ) all_functions_sorted;

  pr "\

ETERM *
dispatch (ETERM *message)
{
  ETERM *fun;

  fun = ERL_TUPLE_ELEMENT (message, 0);

  /* XXX We should use gperf here. */
  ";

  List.iter (
    fun (name, (ret, args, optargs), _, _, _, _, _) ->
      pr "if (atom_equals (fun, \"%s\"))\n" name;
      pr "    return run_%s (message);\n" name;
      pr "  else ";
  ) all_functions_sorted;

  pr "return unknown_function (fun);
}
";
