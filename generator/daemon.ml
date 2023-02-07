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

let generate_header = generate_header ~inputs:["generator/daemon.ml"]

(* Generate daemon/actions.h. *)
let generate_daemon_actions_h () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef GUESTFSD_ACTIONS_H\n";
  pr "#define GUESTFSD_ACTIONS_H\n";
  pr "\n";

  pr "#include \"guestfs_protocol.h\"\n";
  pr "#include \"daemon.h\"\n";
  pr "\n";

  List.iter (
    function
    | { style = _, _, [] } -> ()
    | { name = shortname; style = _, _, (_::_ as optargs) } ->
        List.iteri (
          fun i arg ->
            let uc_shortname = String.uppercase_ascii shortname in
            let n = name_of_optargt arg in
            let uc_n = String.uppercase_ascii n in
            pr "#define GUESTFS_%s_%s_BITMASK (UINT64_C(1)<<%d)\n"
              uc_shortname uc_n i
        ) optargs
  ) (actions |> daemon_functions |> sort);

  List.iter (
    fun { name; style = ret, args, optargs } ->
      let args_passed_to_daemon = args @ args_of_optargs optargs in
      let args_passed_to_daemon =
        List.filter (function String ((FileIn|FileOut), _) -> false | _ -> true)
                    args_passed_to_daemon in
      let style = ret, args_passed_to_daemon, [] in
      generate_prototype
        ~single_line:true ~newline:true ~in_daemon:true ~prefix:"do_"
        name style;
  ) (actions |> daemon_functions |> sort);

  pr "\n";
  pr "#endif /* GUESTFSD_ACTIONS_H */\n"

let generate_daemon_stubs_h () =
  generate_header CStyle GPLv2plus;

  pr "\
#ifndef GUESTFSD_STUBS_H
#define GUESTFSD_STUBS_H

";

  List.iter (
    fun { name } ->
      pr "extern void %s_stub (XDR *xdr_in);\n" name;
  ) (actions |> daemon_functions |> sort);

  pr "\n";
  pr "#endif /* GUESTFSD_STUBS_H */\n"

(* Generate the server-side stubs. *)
let generate_daemon_stubs actions () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <errno.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include \"daemon.h\"
#include \"c-ctype.h\"
#include \"guestfs_protocol.h\"
#include \"actions.h\"
#include \"optgroups.h\"
#include \"stubs.h\"
#include \"stubs-macros.h\"

";

  List.iter (
    fun { name; style = ret, args, optargs; optional } ->
      (* Generate server-side stubs. *)
      let uc_name = String.uppercase_ascii name in

      let args_passed_to_daemon = args @ args_of_optargs optargs in
      let args_passed_to_daemon =
        List.filter (function String ((FileIn|FileOut), _) -> false | _ -> true)
                    args_passed_to_daemon in

      if args_passed_to_daemon <> [] then (
        pr "#ifdef HAVE_ATTRIBUTE_CLEANUP\n";
        pr "\n";
        pr "#define CLEANUP_XDR_FREE_%s_ARGS \\\n" uc_name;
        pr "    __attribute__((cleanup(cleanup_xdr_free_%s_args)))\n" name;
        pr "\n";
        pr "static void\n";
        pr "cleanup_xdr_free_%s_args (struct guestfs_%s_args *argsp)\n"
           name name;
        pr "{\n";
        pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_args, (char *) argsp);\n"
           name;
        pr "}\n";
        pr "\n";
        pr "#else /* !HAVE_ATTRIBUTE_CLEANUP */\n";
        pr "#define CLEANUP_XDR_FREE_%s_ARGS\n" uc_name;
        pr "#endif /* !HAVE_ATTRIBUTE_CLEANUP */\n";
        pr "\n"
      );

      pr "void\n";
      pr "%s_stub (XDR *xdr_in)\n" name;
      pr "{\n";
      (match ret with
       | RErr | RInt _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RBool _ -> pr "  int r;\n"
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString _ -> pr "  CLEANUP_FREE char *r = NULL;\n"
       | RStringList _ | RHashtable _ -> pr "  CLEANUP_FREE_STRING_LIST char **r = NULL;\n"
       | RStruct (_, typ) -> pr "  CLEANUP_FREE guestfs_int_%s *r = NULL;\n" typ
       | RStructList (_, typ) -> pr "  CLEANUP_FREE guestfs_int_%s_list *r = NULL;\n" typ
       | RBufferOut _ ->
           pr "  size_t size = 1;\n";
           pr "  CLEANUP_FREE char *r = NULL;\n"
      );

      if args_passed_to_daemon <> [] then (
        pr "  CLEANUP_XDR_FREE_%s_ARGS struct guestfs_%s_args args;\n"
           uc_name name;
        pr "  memset (&args, 0, sizeof args);\n";
        List.iter (
          function
          | String ((Device|Dev_or_Path), n) ->
            pr "  CLEANUP_FREE char *%s = NULL;\n" n
          | String ((Pathname|PlainString|Key|GUID), n)
          | OptString n ->
            pr "  const char *%s;\n" n
          | String ((Mountable|Mountable_or_Path), n) ->
            pr "  CLEANUP_FREE_MOUNTABLE mountable_t %s\n" n;
            pr "      = { .device = NULL, .volume = NULL };\n"
          | StringList ((PlainString|Filename), n) ->
            pr "  char **%s;\n" n
          | StringList (Device, n) ->
            pr "  CLEANUP_FREE_STRING_LIST char **%s = NULL;\n" n
          | Bool n -> pr "  int %s;\n" n
          | Int n -> pr "  int %s;\n" n
          | Int64 n -> pr "  int64_t %s;\n" n
          | BufferIn n ->
              pr "  const char *%s;\n" n;
              pr "  size_t %s_size;\n" n
          | String ((FileIn|FileOut|Filename), _)
          | StringList ((Mountable|Pathname|FileIn|FileOut|Key|GUID
                         |Dev_or_Path|Mountable_or_Path), _)
          | Pointer _ -> assert false
        ) args_passed_to_daemon
      );
      pr "\n";

      let is_filein =
        List.exists (function String (FileIn, _) -> true | _ -> false) args in

      (* Reject Optional functions that are not available (RHBZ#679737). *)
      (match optional with
      | Some group ->
        pr "  /* The caller should have checked before calling this. */\n";
        pr "  if (! optgroup_%s_available ()) {\n" group;
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_unavailable_feature (\"%s\");\n" group;
        pr "    return;\n";
        pr "  }\n";
        pr "\n"
      | None -> ()
      );

      (* Reject unknown optional arguments.
       * Note this code is included even for calls with no optional
       * args because the caller must not pass optargs_bitmask != 0
       * in that case.
       *)
      if optargs <> [] then (
        let len = List.length optargs in
        let mask = Int64.lognot (Int64.pred (Int64.shift_left 1L len)) in
        pr "  if (optargs_bitmask & UINT64_C(0x%Lx)) {\n" mask;
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_error (\"unknown option in optional arguments bitmask (this can happen if a program is compiled against a newer version of libguestfs, then run against an older version of the daemon)\");\n";
        pr "    return;\n";
        pr "  }\n";
      ) else (
        pr "  if (optargs_bitmask != 0) {\n";
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_error (\"header optargs_bitmask field must be passed as 0 for calls that don't take optional arguments\");\n";
        pr "    return;\n";
        pr "  }\n";
      );
      pr "\n";

      (* Decode arguments. *)
      if args_passed_to_daemon <> [] then (
        pr "  if (!xdr_guestfs_%s_args (xdr_in, &args)) {\n" name;
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_error (\"daemon failed to decode procedure arguments\");\n";
        pr "    return;\n";
        pr "  }\n";
        let pr_args n =
          pr "  %s = args.%s;\n" n n
        in
        List.iter (
          function
          | String (Pathname, n) ->
              pr_args n;
              pr "  ABS_PATH (%s, %b, return);\n" n is_filein;
          | String (Device, n) ->
              pr "  RESOLVE_DEVICE (args.%s, %s, %b);\n" n n is_filein;
          | String (Mountable, n) ->
              pr "  RESOLVE_MOUNTABLE (args.%s, %s, %b);\n" n n is_filein;
          | String (Dev_or_Path, n) ->
              pr "  REQUIRE_ROOT_OR_RESOLVE_DEVICE (args.%s, %s, %b);\n"
                n n is_filein;
          | String (Mountable_or_Path, n) ->
              pr "  REQUIRE_ROOT_OR_RESOLVE_MOUNTABLE (args.%s, %s, %b);\n"
                n n is_filein;
          | String ((PlainString|Key|GUID), n) -> pr_args n
          | OptString n -> pr "  %s = args.%s ? *args.%s : NULL;\n" n n n
          | StringList ((PlainString|Filename) as arg, n) ->
            (match arg with
            | Filename ->
              pr "  {\n";
              pr "    size_t i;\n";
              pr "    for (i = 0; i < args.%s.%s_len; ++i) {\n" n n;
              pr "      if (strchr (args.%s.%s_val[i], '/') != NULL) {\n" n n;
              if is_filein then
                pr "        cancel_receive ();\n";
              pr "        reply_with_error (\"%%s: '%%s' is not a file name\", __func__, args.%s.%s_val[i]);\n"
                n n;
              pr "        return;\n";
              pr "      }\n";
              pr "    }\n";
              pr "  }\n"
            | _ -> ()
            );
            pr "  /* Ugly, but safe and avoids copying the strings. */\n";
            pr "  %s = realloc (args.%s.%s_val,\n" n n n;
            pr "                sizeof (char *) * (args.%s.%s_len+1));\n" n n;
            pr "  if (%s == NULL) {\n" n;
            if is_filein then
              pr "    cancel_receive ();\n";
            pr "    reply_with_perror (\"realloc\");\n";
            pr "    return;\n";
            pr "  }\n";
            pr "  %s[args.%s.%s_len] = NULL;\n" n n n;
            pr "  args.%s.%s_val = %s;\n" n n n
          | StringList (Device, n) ->
            pr "  /* Copy the string list and apply device name translation\n";
            pr "   * to each one.\n";
            pr "   */\n";
            pr "  %s = calloc (args.%s.%s_len+1, sizeof (char *));\n" n n n;
            pr "  {\n";
            pr "    size_t i;\n";
            pr "    for (i = 0; i < args.%s.%s_len; ++i)\n" n n;
            pr "      RESOLVE_DEVICE (args.%s.%s_val[i], %s[i], %b);\n"
               n n n is_filein;
            pr "    %s[i] = NULL;\n" n;
            pr "  }\n"
          | Bool n -> pr "  %s = args.%s;\n" n n
          | Int n -> pr "  %s = args.%s;\n" n n
          | Int64 n -> pr "  %s = args.%s;\n" n n
          | BufferIn n ->
              pr "  %s = args.%s.%s_val;\n" n n n;
              pr "  %s_size = args.%s.%s_len;\n" n n n
          | String ((FileIn|FileOut|Filename), _)
          | StringList ((Mountable|Pathname|FileIn|FileOut|Key|GUID
                         |Dev_or_Path|Mountable_or_Path), _)
          | Pointer _ -> assert false
        ) args_passed_to_daemon;
        pr "\n"
      );

      (* this is used at least for do_equal *)
      if List.exists (function String (Pathname, _) -> true
                             | _ -> false) args then (
        (* Emit NEED_ROOT just once, even when there are two or
           more Pathname args *)
        pr "  NEED_ROOT (%b, return);\n" is_filein
      );

      (* Don't want to call the impl with any FileIn or FileOut
       * parameters, since these go "outside" the RPC protocol.
       *)
      let () =
        let args' =
          List.filter
            (function String ((FileIn|FileOut), _) -> false | _ -> true) args in
        let style = ret, args' @ args_of_optargs optargs, [] in
        pr "  r = do_%s " name;
        generate_c_call_args ~in_daemon:true style;
        pr ";\n" in

      (match ret with
       | RConstOptString _ -> assert false
       | RErr | RInt _ | RInt64 _ | RBool _
       | RConstString _
       | RString _ | RStringList _ | RHashtable _
       | RStruct (_, _) | RStructList (_, _) ->
           let errcode =
             match errcode_of_ret ret with
             | `CannotReturnError -> assert false
             | (`ErrorIsMinusOne | `ErrorIsNULL) as e -> e in
           pr "  if (r == %s)\n" (string_of_errcode errcode);
           pr "    /* do_%s has already called reply_with_error */\n" name;
           pr "    return;\n";
           pr "\n"
       | RBufferOut _ ->
           pr "  /* size == 0 && r == NULL could be a non-error case (just\n";
           pr "   * an ordinary zero-length buffer), so be careful ...\n";
           pr "   */\n";
           pr "  if (size == 1 && r == NULL)\n";
           pr "    /* do_%s has already called reply_with_error */\n" name;
           pr "    return;\n";
           pr "\n"
      );

      (* If there are any FileOut parameters, then the impl must
       * send its own reply.
       *)
      let no_reply =
        List.exists (function String (FileOut, _) -> true | _ -> false) args in
      if no_reply then
        pr "  /* do_%s has already sent a reply */\n" name
      else (
        match ret with
        | RErr -> pr "  reply (NULL, NULL);\n"
        | RInt n | RInt64 n | RBool n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = r;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RString (RPlainString, n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = r;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RString ((RDevice|RMountable), n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  CLEANUP_FREE char *rr = reverse_device_name_translation (r);\n";
            pr "  if (rr == NULL)\n";
            pr "    /* reverse_device_name_translation has already called reply_with_error */\n";
            pr "    return;\n";
            pr "  ret.%s = rr;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStringList (RPlainString, n)
        | RHashtable (RPlainString, RPlainString, n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_len = guestfs_int_count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStringList ((RDevice|RMountable), n)
        | RHashtable ((RDevice|RMountable), (RDevice|RMountable), n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  size_t i;\n";
            pr "  for (i = 0; r[i] != NULL; ++i) {\n";
            pr "    char *rr = reverse_device_name_translation (r[i]);\n";
            pr "    if (rr == NULL)\n";
            pr "      /* reverse_device_name_translation has already called reply_with_error */\n";
            pr "      return;\n";
            pr "    free (r[i]);\n";
            pr "    r[i] = rr;\n";
            pr "  }\n";
            pr "  ret.%s.%s_len = guestfs_int_count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RHashtable ((RDevice|RMountable), RPlainString, n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  size_t i;\n";
            pr "  for (i = 0; r[i] != NULL; i += 2) {\n";
            pr "    char *rr = reverse_device_name_translation (r[i]);\n";
            pr "    if (rr == NULL)\n";
            pr "      /* reverse_device_name_translation has already called reply_with_error */\n";
            pr "      return;\n";
            pr "    free (r[i]);\n";
            pr "    r[i] = rr;\n";
            pr "  }\n";
            pr "  ret.%s.%s_len = guestfs_int_count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RHashtable (RPlainString, (RDevice|RMountable), n) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  size_t i;\n";
            pr "  for (i = 0; r[i] != NULL; i += 2) {\n";
            pr "    char *rr = reverse_device_name_translation (r[i+1]);\n";
            pr "    if (rr == NULL)\n";
            pr "      /* reverse_device_name_translation has already called reply_with_error */\n";
            pr "      return;\n";
            pr "    free (r[i+1]);\n";
            pr "    r[i+1] = rr;\n";
            pr "  }\n";
            pr "  ret.%s.%s_len = guestfs_int_count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStruct (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStructList (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RBufferOut n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  ret.%s.%s_len = size;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
      );
      pr "}\n\n";
  ) (actions |> daemon_functions |> sort)

let generate_daemon_caml_callbacks_ml () =
  generate_header OCamlStyle GPLv2plus;

  if actions |> impl_ocaml_functions <> [] then (
    pr "let init_callbacks () =\n";
    pr "  (* Initialize callbacks to OCaml code. *)\n";
    List.iter (
      fun ({ name; style = ret, args, optargs } as f) ->
        let ocaml_function =
          match f.impl with
          | OCaml f -> f
          | C -> assert false in

        pr "  Callback.register %S %s;\n" ocaml_function ocaml_function
    ) (actions |> impl_ocaml_functions |> sort)
  )
  else
    pr "let init_callbacks () = ()\n"

let rec generate_daemon_caml_interface modname () =
  generate_header OCamlStyle GPLv2plus;

  let is_ocaml_module_function = function
    | { impl = OCaml m } when String.is_prefix m (modname ^ ".") -> true
    | { impl = OCaml _ } -> false
    | { impl = C } -> false
  in

  let ocaml_actions = actions |> (List.filter is_ocaml_module_function) in
  if ocaml_actions == [] then
    failwithf "no OCaml implementations for module %s" modname;

  let prefix_length = String.length modname + 1 in
  List.iter (
    fun { name; style; impl } ->
      let ocaml_function =
        match impl with
        | OCaml f ->
            String.sub f prefix_length (String.length f - prefix_length)
        | C -> assert false in

      generate_ocaml_daemon_prototype ocaml_function style
  ) ocaml_actions

and generate_ocaml_daemon_prototype name (ret, args, optargs) =
  let type_for_stringt = function
    | Mountable
    | Mountable_or_Path -> "Mountable.t"
    | PlainString
    | Device
    | Pathname
    | FileIn
    | FileOut
    | Key
    | GUID
    | Filename
    | Dev_or_Path -> "string"
  in
  let type_for_rstringt = function
    | RMountable -> "Mountable.t"
    | RPlainString
    | RDevice -> "string"
  in
  pr "val %s : " name;
  List.iter (
    function
    | OBool n -> pr "?%s:bool -> " n
    | OInt n -> pr "?%s:int -> " n
    | OInt64 n -> pr "?%s:int64 -> " n
    | OString n -> pr "?%s:string -> " n
    | OStringList n -> pr "?%s:string array -> " n
  ) optargs;
  if args <> [] then
    List.iter (
      function
      | String (typ, _) -> pr "%s -> " (type_for_stringt typ)
      | BufferIn _ -> pr "string -> "
      | OptString _ -> pr "string option -> "
      | StringList (typ, _) -> pr "%s array -> " (type_for_stringt typ)
      | Bool _ -> pr "bool -> "
      | Int _ -> pr "int -> "
      | Int64 _ | Pointer _ -> pr "int64 -> "
    ) args
  else
    pr "unit -> ";
  (match ret with
   | RErr -> pr "unit" (* all errors are turned into exceptions *)
   | RInt _ -> pr "int"
   | RInt64 _ -> pr "int64"
   | RBool _ -> pr "bool"
   | RConstString _ -> pr "string"
   | RConstOptString _ -> pr "string option"
   | RString (typ, _) -> pr "%s" (type_for_rstringt typ)
   | RBufferOut _ -> pr "string"
   | RStringList (typ, _) -> pr "%s list" (type_for_rstringt typ)
   | RStruct (_, typ) -> pr "Structs.%s" typ
   | RStructList (_, typ) -> pr "Structs.%s list" typ
   | RHashtable (typea, typeb, _) ->
       pr "(%s * %s) list" (type_for_rstringt typea) (type_for_rstringt typeb)
  );
  pr "\n"

(* Generate stubs for the functions implemented in OCaml.
 * Basically we implement the do_<name> function here, and
 * have it call out to OCaml code.
 *)
let generate_daemon_caml_stubs () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include \"daemon.h\"
#include \"actions.h\"
#include \"daemon-c.h\"

";

  (* Implement code for returning structs and struct lists. *)
  let emit_return_struct typ =
    let struc = Structs.lookup_struct typ in
    let uc_typ = String.uppercase_ascii typ in
    pr "/* Implement RStruct (%S, _). */\n" typ;
    pr "static guestfs_int_%s *\n" typ;
    pr "return_%s (value retv)\n" typ;
    pr "{\n";
    pr "  CLEANUP_FREE_%s guestfs_int_%s *ret = NULL;\n" uc_typ typ;
    pr "  guestfs_int_%s *real_ret;\n" typ;
    pr "  value v;\n";
    pr "\n";
    pr "  ret = calloc (1, sizeof (*ret));\n";
    pr "  if (ret == NULL) {\n";
    pr "    reply_with_perror (\"calloc\");\n";
    pr "    return NULL;\n";
    pr "  }\n";
    pr "\n";
    List.iteri (
      fun i ->
        pr "  v = Field (retv, %d);\n" i;
        function
        | n, (FString|FUUID) ->
           pr "  ret->%s = strdup (String_val (v));\n" n;
           pr "  if (ret->%s == NULL) return NULL;\n" n
        | n, FBuffer ->
           pr "  ret->%s_len = caml_string_length (v);\n" n;
           pr "  ret->%s = strdup (String_val (v));\n" n;
           pr "  if (ret->%s == NULL) return NULL;\n" n
        | n, (FBytes|FInt64|FUInt64) ->
           pr "  ret->%s = Int64_val (v);\n" n
        | n, (FInt32|FUInt32) ->
           pr "  ret->%s = Int32_val (v);\n" n
        | n, FOptPercent ->
           pr "  if (v == Val_int (0)) /* None */\n";
           pr "    ret->%s = -1;\n" n;
           pr "  else {\n";
           pr "    v = Field (v, 0);\n";
           pr "    ret->%s = Double_val (v);\n" n;
           pr "  }\n"
        | n, FChar ->
           pr "  ret->%s = Int_val (v);\n" n
    ) struc.s_cols;
    pr "\n";
    pr "  real_ret = ret;\n";
    pr "  ret = NULL;\n";
    pr "  return real_ret;\n";
    pr "}\n";
    pr "\n"

  and emit_return_struct_list typ =
    let uc_typ = String.uppercase_ascii typ in
    pr "/* Implement RStructList (%S, _). */\n" typ;
    pr "static guestfs_int_%s_list *\n" typ;
    pr "return_%s_list (value retv)\n" typ;
    pr "{\n";
    pr "  CLEANUP_FREE_%s_LIST guestfs_int_%s_list *ret = NULL;\n" uc_typ typ;
    pr "  guestfs_int_%s_list *real_ret;\n" typ;
    pr "  guestfs_int_%s *r;\n" typ;
    pr "  size_t i, len;\n";
    pr "  value v, rv;\n";
    pr "\n";
    pr "  /* Count the number of elements in the list. */\n";
    pr "  rv = retv;\n";
    pr "  len = 0;\n";
    pr "  while (rv != Val_int (0)) {\n";
    pr "    len++;\n";
    pr "    rv = Field (rv, 1);\n";
    pr "  }\n";
    pr "\n";
    pr "  ret = calloc (1, sizeof *ret);\n";
    pr "  if (ret == NULL) {\n";
    pr "    reply_with_perror (\"calloc\");\n";
    pr "    return NULL;\n";
    pr "  }\n";
    pr "  if (len > 0) {\n";
    pr "    ret->guestfs_int_%s_list_val =\n" typ;
    pr "      calloc (len, sizeof (guestfs_int_%s));\n" typ;
    pr "    if (ret->guestfs_int_%s_list_val == NULL) {\n" typ;
    pr "      reply_with_perror (\"calloc\");\n";
    pr "      return NULL;\n";
    pr "    }\n";
    pr "    ret->guestfs_int_%s_list_len = len;\n" typ;
    pr "  }\n";
    pr "\n";
    pr "  rv = retv;\n";
    pr "  for (i = 0; i < len; ++i) {\n";
    pr "    v = Field (rv, 0);\n";
    pr "    r = return_%s (v);\n" typ;
    pr "    if (r == NULL)\n";
    pr "      return NULL;\n";
    pr "    memcpy (&ret->guestfs_int_%s_list_val[i], r, sizeof (*r));\n" typ;
    pr "    free (r);\n";
    pr "    rv = Field (rv, 1);\n";
    pr "  }\n";
    pr "\n";
    pr "  real_ret = ret;\n";
    pr "  ret = NULL;\n";
    pr "  return real_ret;\n";
    pr "}\n";
    pr "\n";
  in

  List.iter (
    function
    | typ, RStructOnly ->
       emit_return_struct typ
    | typ, (RStructListOnly | RStructAndList) ->
       emit_return_struct typ;
       emit_return_struct_list typ
  ) (rstructs_used_by (actions |> impl_ocaml_functions));

  (* Implement the wrapper functions. *)
  List.iter (
    fun ({ name; style = ret, args, optargs } as f) ->
      let uc_name = String.uppercase_ascii name in
      let ocaml_function =
        match f.impl with
        | OCaml f -> f
        | C -> assert false in

      pr "/* Wrapper for OCaml function ‘%s’. */\n" ocaml_function;

      let args_do_function = args @ args_of_optargs optargs in
      let args_do_function =
        List.filter (function
                     | String ((FileIn|FileOut), _) -> false | _ -> true)
                    args_do_function in
      let style = ret, args_do_function, [] in
      generate_prototype ~extern:false ~semicolon:false
                         ~single_line:false ~newline:false
                         ~in_daemon:true ~prefix:"do_"
                         name style;
      pr "\n";

      let add_unit_arg =
        let args = List.filter
                     (function
                      | String ((FileIn|FileOut), _) -> false | _ -> true)
                 args in
        args = [] in
      let nr_args = List.length args_do_function in

      pr "{\n";
      pr "  static const value *cb = NULL;\n";
      pr "  CAMLparam0 ();\n";
      pr "  CAMLlocal2 (v, retv);\n";
      pr "  CAMLlocalN (args, %d);\n"
         (nr_args + if add_unit_arg then 1 else 0);
      pr "\n";
      pr "  if (cb == NULL)\n";
      pr "    cb = caml_named_value (\"%s\");\n" ocaml_function;
      pr "\n";

      (* Construct the actual call, but note that we want to pass
       * the optional arguments first in the list.
       *)
      let i = ref 0 in
      List.iter (
        fun optarg ->
          let n = name_of_optargt optarg in
          let uc_n = String.uppercase_ascii n in

          (* optargs are all passed as [None|Some _] *)
          pr "  if ((optargs_bitmask & GUESTFS_%s_%s_BITMASK) == 0)\n"
             uc_name uc_n;
          pr "    args[%d] = Val_int (0); /* None */\n" !i;
          pr "  else {\n";
          pr "    v = ";
          (match optarg with
           | OBool _ ->
              pr "Val_bool (%s)" n;
           | OInt _ -> assert false
           | OInt64 _ -> assert false
           | OString _ ->
              pr "caml_copy_string (%s)" n
           | OStringList _ -> assert false
          );
          pr ";\n";
          pr "    args[%d] = caml_alloc (1, 0);\n" !i;
          pr "    Store_field (args[%d], 0, v);\n" !i;
          pr "  }\n";
          incr i
      ) optargs;
      List.iter (
        fun arg ->
          pr "  args[%d] = " !i;
          (match arg with
           | Bool n -> pr "Val_bool (%s)" n
           | Int n -> pr "Val_int (%s)" n
           | Int64 n -> pr "caml_copy_int64 (%s)" n
           | String ((PlainString|Device|Pathname|Dev_or_Path|Key), n) ->
              pr "caml_copy_string (%s)" n
           | String ((Mountable|Mountable_or_Path), n) ->
              pr "guestfs_int_daemon_copy_mountable (%s)" n
           | String _ -> assert false
           | OptString _ -> assert false
           | StringList _ -> assert false
           | BufferIn _ -> assert false
           | Pointer _ -> assert false
          );
          pr ";\n";
          incr i
      ) args;
      assert (!i = nr_args);

      (* If there are no non-optional arguments, we add a unit arg. *)
      if add_unit_arg then
        pr "  args[%d] = Val_unit;\n" !i;

      pr "  retv = caml_callbackN_exn (*cb, %d, args);\n"
         (nr_args + if add_unit_arg then 1 else 0);
      pr "\n";
      pr "  if (Is_exception_result (retv)) {\n";
      pr "    retv = Extract_exception (retv);\n";
      pr "    guestfs_int_daemon_exn_to_reply_with_error (%S, retv);\n" name;
      (match errcode_of_ret ret with
       | `CannotReturnError ->
          pr "    CAMLreturn0;\n"
       | `ErrorIsMinusOne ->
          pr "    CAMLreturnT (int, -1);\n"
       | `ErrorIsNULL ->
          pr "    CAMLreturnT (void *, NULL);\n"
      );
      pr "  }\n";
      pr "\n";

      (match ret with
       | RErr ->
          pr "  CAMLreturnT (int, 0);\n"
       | RInt _ ->
          pr "  CAMLreturnT (int, Int_val (retv));\n"
       | RInt64 _ ->
          pr "  CAMLreturnT (int, Int64_val (retv));\n"
       | RBool _ ->
          pr "  CAMLreturnT (int, Bool_val (retv));\n"
       | RConstString _ -> assert false
       | RConstOptString _ -> assert false
       | RString ((RPlainString|RDevice), _) ->
          pr "  char *ret = strdup (String_val (retv));\n";
          pr "  if (ret == NULL) {\n";
          pr "    reply_with_perror (\"strdup\");\n";
          pr "    CAMLreturnT (char *, NULL);\n";
          pr "  }\n";
          pr "  CAMLreturnT (char *, ret); /* caller frees */\n"
       | RString (RMountable, _) ->
          pr "  char *ret =\n";
          pr "    guestfs_int_daemon_return_string_mountable (retv);\n";
          pr "  CAMLreturnT (char *, ret); /* caller frees */\n"
       | RStringList ((RPlainString|RDevice), _) ->
          pr "  char **ret = guestfs_int_daemon_return_string_list (retv);\n";
          pr "  CAMLreturnT (char **, ret); /* caller frees */\n"
       | RStringList (RMountable, _) ->
          pr "  char **ret =\n";
          pr "    guestfs_int_daemon_return_string_mountable_list (retv);\n";
          pr "  CAMLreturnT (char **, ret); /* caller frees */\n"
       | RStruct (_, typ) ->
          pr "  guestfs_int_%s *ret =\n" typ;
          pr "    return_%s (retv);\n" typ;
          pr "  /* caller frees */\n";
          pr "  CAMLreturnT (guestfs_int_%s *, ret);\n" typ
       | RStructList (_, typ) ->
          pr "  guestfs_int_%s_list *ret =\n" typ;
          pr "    return_%s_list (retv);\n" typ;
          pr "  /* caller frees */\n";
          pr "  CAMLreturnT (guestfs_int_%s_list *, ret);\n" typ
       | RHashtable (RPlainString, RPlainString, _)
       | RHashtable (RPlainString, RDevice, _) ->
          pr "  char **ret =\n";
          pr "    guestfs_int_daemon_return_hashtable_string_string (retv);\n";
          pr "  CAMLreturnT (char **, ret); /* caller frees */\n"
       | RHashtable (RMountable, RPlainString, _) ->
          pr "  char **ret =\n";
          pr "    guestfs_int_daemon_return_hashtable_mountable_string (retv);\n";
          pr "  CAMLreturnT (char **, ret); /* caller frees */\n"
       | RHashtable (RPlainString, RMountable, _) ->
          pr "  char **ret =\n";
          pr "    guestfs_int_daemon_return_hashtable_string_mountable (retv);\n";
          pr "  CAMLreturnT (char **, ret); /* caller frees */\n"
       | RHashtable _ -> assert false
       | RBufferOut _ -> assert false
      );
      pr "}\n";
      pr "\n"
  ) (actions |> impl_ocaml_functions |> sort)

let generate_daemon_dispatch () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <errno.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include \"daemon.h\"
#include \"c-ctype.h\"
#include \"guestfs_protocol.h\"
#include \"actions.h\"
#include \"optgroups.h\"
#include \"stubs.h\"

";

  (* Dispatch function. *)
  pr "void\n";
  pr "dispatch_incoming_message (XDR *xdr_in)\n";
  pr "{\n";
  pr "  switch (proc_nr) {\n";

  List.iter (
    fun { name } ->
      pr "    case GUESTFS_PROC_%s:\n" (String.uppercase_ascii name);
      pr "      %s_stub (xdr_in);\n" name;
      pr "      break;\n"
  ) (actions |> daemon_functions |> sort);

  pr "    default:\n";
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d, set LIBGUESTFS_PATH to point to the matching libguestfs appliance directory\", proc_nr);\n";
  pr "  }\n";
  pr "}\n";
  pr "\n"

let generate_daemon_lvm_tokenization () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <errno.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include \"daemon.h\"
#include \"c-ctype.h\"
#include \"guestfs_protocol.h\"
#include \"actions.h\"
#include \"optgroups.h\"

";

  (* LVM columns and tokenization functions. *)
  (* XXX This generates crap code.  We should rethink how we
   * do this parsing.
   *)
  List.iter (
    function
    | typ, cols ->
        pr "static const char lvm_%s_cols[] = \"%s\";\n"
          typ (String.concat "," (List.map fst cols));
        pr "\n";

        pr "static int lvm_tokenize_%s (char *str, guestfs_int_lvm_%s *r)\n" typ typ;
        pr "{\n";
        pr "  char *tok, *p, *next;\n";
        pr "  size_t i, j;\n";
        pr "\n";
        (*
          pr "  fprintf (stderr, \"%%s: <<%%s>>\\n\", __func__, str);\n";
          pr "\n";
        *)
        pr "  if (!str) {\n";
        pr "    fprintf (stderr, \"%%s: failed: passed a NULL string\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  if (!*str || c_isspace (*str)) {\n";
        pr "    fprintf (stderr, \"%%s: failed: passed a empty string or one beginning with whitespace\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  tok = str;\n";
        List.iter (
          fun (name, coltype) ->
            pr "  if (!tok) {\n";
            pr "    fprintf (stderr, \"%%s: failed: string finished early, around token %%s\\n\", __func__, \"%s\");\n" name;
            pr "    return -1;\n";
            pr "  }\n";
            pr "  p = strchrnul (tok, '\\r');\n";
            pr "  if (*p) next = p+1; else next = NULL;\n";
            pr "  *p = '\\0';\n";
            (match coltype with
             | FString ->
                 pr "  r->%s = strdup (tok);\n" name;
                 pr "  if (r->%s == NULL) {\n" name;
                 pr "    perror (\"strdup\");\n";
                 pr "    return -1;\n";
                 pr "  }\n"
             | FUUID ->
                 pr "  for (i = j = 0; i < 32; ++j) {\n";
                 pr "    if (tok[j] == '\\0') {\n";
                 pr "      fprintf (stderr, \"%%s: failed to parse UUID from '%%s'\\n\", __func__, tok);\n";
                 pr "      return -1;\n";
                 pr "    } else if (tok[j] != '-')\n";
                 pr "      r->%s[i++] = tok[j];\n" name;
                 pr "  }\n";
             | FBytes ->
                 pr "  if (sscanf (tok, \"%%\" SCNi64, &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FInt64 ->
                 pr "  if (sscanf (tok, \"%%\" SCNi64, &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse int '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FOptPercent ->
                 pr "  if (tok[0] == '\\0')\n";
                 pr "    r->%s = -1;\n" name;
                 pr "  else if (sscanf (tok, \"%%f\", &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse float '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FBuffer | FInt32 | FUInt32 | FUInt64 | FChar ->
                 assert false (* can never be an LVM column *)
            );
            pr "  tok = next;\n";
        ) cols;

        pr "  if (tok != NULL) {\n";
        pr "    fprintf (stderr, \"%%s: failed: extra tokens at end of string\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  return 0;\n";
        pr "}\n";
        pr "\n";

        pr "guestfs_int_lvm_%s_list *\n" typ;
        pr "parse_command_line_%ss (void)\n" typ;
        pr "{\n";
        pr "  char *out, *err;\n";
        pr "  char *p, *pend;\n";
        pr "  int r, i;\n";
        pr "  guestfs_int_lvm_%s_list *ret;\n" typ;
        pr "  void *newp;\n";
        pr "\n";
        pr "  ret = malloc (sizeof *ret);\n";
        pr "  if (!ret) {\n";
        pr "    reply_with_perror (\"malloc\");\n";
        pr "    return NULL;\n";
        pr "  }\n";
        pr "\n";
        pr "  ret->guestfs_int_lvm_%s_list_len = 0;\n" typ;
        pr "  ret->guestfs_int_lvm_%s_list_val = NULL;\n" typ;
        pr "\n";
        pr "  r = command (&out, &err,\n";
        pr "	       \"lvm\", \"%ss\",\n" typ;
        pr "	       \"-o\", lvm_%s_cols, \"--unbuffered\", \"--noheadings\",\n" typ;
        pr "	       \"--nosuffix\", \"--separator\", \"\\r\", \"--units\", \"b\", NULL);\n";
        pr "  if (r == -1) {\n";
        pr "    reply_with_error (\"%%s\", err);\n";
        pr "    free (out);\n";
        pr "    free (err);\n";
        pr "    free (ret);\n";
        pr "    return NULL;\n";
        pr "  }\n";
        pr "\n";
        pr "  free (err);\n";
        pr "\n";
        pr "  /* Tokenize each line of the output. */\n";
        pr "  p = out;\n";
        pr "  i = 0;\n";
        pr "  while (p) {\n";
        pr "    pend = strchr (p, '\\n');	/* Get the next line of output. */\n";
        pr "    if (pend) {\n";
        pr "      *pend = '\\0';\n";
        pr "      pend++;\n";
        pr "    }\n";
        pr "\n";
        pr "    while (*p && c_isspace (*p))	/* Skip any leading whitespace. */\n";
        pr "      p++;\n";
        pr "\n";
        pr "    if (!*p) {			/* Empty line?  Skip it. */\n";
        pr "      p = pend;\n";
        pr "      continue;\n";
        pr "    }\n";
        pr "\n";
        pr "    /* Allocate some space to store this next entry. */\n";
        pr "    newp = realloc (ret->guestfs_int_lvm_%s_list_val,\n" typ;
        pr "		    sizeof (guestfs_int_lvm_%s) * (i+1));\n" typ;
        pr "    if (newp == NULL) {\n";
        pr "      reply_with_perror (\"realloc\");\n";
        pr "      free (ret->guestfs_int_lvm_%s_list_val);\n" typ;
        pr "      free (ret);\n";
        pr "      free (out);\n";
        pr "      return NULL;\n";
        pr "    }\n";
        pr "    ret->guestfs_int_lvm_%s_list_val = newp;\n" typ;
        pr "\n";
        pr "    /* Tokenize the next entry. */\n";
        pr "    r = lvm_tokenize_%s (p, &ret->guestfs_int_lvm_%s_list_val[i]);\n" typ typ;
        pr "    if (r == -1) {\n";
        pr "      reply_with_error (\"failed to parse output of '%ss' command\");\n" typ;
        pr "      free (ret->guestfs_int_lvm_%s_list_val);\n" typ;
        pr "      free (ret);\n";
        pr "      free (out);\n";
        pr "      return NULL;\n";
        pr "    }\n";
        pr "\n";
        pr "    ++i;\n";
        pr "    p = pend;\n";
        pr "  }\n";
        pr "\n";
        pr "  ret->guestfs_int_lvm_%s_list_len = i;\n" typ;
        pr "\n";
        pr "  free (out);\n";
        pr "  return ret;\n";
        pr "}\n"

  ) ["pv", lvm_pv_cols; "vg", lvm_vg_cols; "lv", lvm_lv_cols]

(* Generate a list of function names, for debugging in the daemon.. *)
let generate_daemon_names () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "\n";

  pr "/* This array is indexed by proc_nr.  See guestfs_protocol.x. */\n";
  pr "const char *function_names[] = {\n";
  List.iter (
    function
    | { name; proc_nr = Some proc_nr } ->
      pr "  [%d] = \"%s\",\n" proc_nr name
    | { proc_nr = None } -> assert false
  ) (actions |> daemon_functions |> sort);
  pr "};\n"

(* Generate the optional groups for the daemon to implement
 * guestfs_available.
 *)
let generate_daemon_optgroups_c () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <caml/mlvalues.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"optgroups.h\"\n";
  pr "\n";

  if optgroups_retired <> [] then (
    pr "static int\n";
    pr "dummy_available (void)\n";
    pr "{\n";
    pr "  return 1;\n";
    pr "}\n";
    pr "\n";
  );

  pr "struct optgroup optgroups[] = {\n";
  List.iter (
    fun group ->
      if List.mem group optgroups_retired then
        pr "  { \"%s\", dummy_available },\n" group
      else
        pr "  { \"%s\", optgroup_%s_available },\n" group group
  ) optgroups_names_all;
  pr "  { NULL, NULL }\n";
  pr "};\n";
  pr "\n";
  pr "/* Wrappers so these functions can be called from OCaml code. */\n";
  List.iter (
    fun group ->
      pr "extern value guestfs_int_daemon_optgroup_%s_available (value);\n"
         group;
      pr "\n";
      pr "/* NB: This is a [@@noalloc] call. */\n";
      pr "value\n";
      pr "guestfs_int_daemon_optgroup_%s_available (value unitv)\n" group;
      pr "{\n";
      pr "  return Val_bool (optgroup_%s_available ());\n" group;
      pr "}\n";
      pr "\n"
  ) optgroups_names

let generate_daemon_optgroups_h () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef GUESTFSD_OPTGROUPS_H\n";
  pr "#define GUESTFSD_OPTGROUPS_H\n";
  pr "\n";

  List.iter (
    fun group ->
      pr "extern int optgroup_%s_available (void);\n" group
  ) optgroups_names;

  pr "\n";

  pr "\
/* These macros can be used to disable an entire group of functions.
 * The advantage of generating this code is that it avoids an
 * undetected error when a new function in a group is added, but
 * the appropriate abort function is not added to the daemon (because
 * the developers rarely test that the daemon builds when a library
 * is not present).
 */

";
  List.iter (
    fun (group, fns) ->
      pr "#define OPTGROUP_%s_NOT_AVAILABLE \\\n"
         (String.uppercase_ascii group);
      List.iter (
        fun { name; style = ret, args, optargs } ->
          let style = ret, args @ args_of_optargs optargs, [] in
          pr "  ";
          generate_prototype
            ~prefix:"do_"
            ~attribute_noreturn:true
            ~single_line:true ~newline:false
            ~extern:false ~in_daemon:true
            ~semicolon:false
            name style;
          pr " { abort (); } \\\n"
      ) fns;
      pr "  int optgroup_%s_available (void) { return 0; }\n" group;
      pr "\n"
  ) optgroups;

  pr "#endif /* GUESTFSD_OPTGROUPS_H */\n"

(* Generate optgroup available functions in OCaml. *)
let generate_daemon_optgroups_ml () =
  generate_header OCamlStyle GPLv2plus;

  List.iter (
    fun group ->
      pr "external %s_available : unit -> bool =\n" group;
      pr "  \"guestfs_int_daemon_optgroup_%s_available\" [@@noalloc]\n" group
  ) optgroups_names

let generate_daemon_optgroups_mli () =
  generate_header OCamlStyle GPLv2plus;

  List.iter (
    fun group ->
      pr "val %s_available : unit -> bool\n" group
  ) optgroups_names

(* Generate structs-cleanups.c file. *)
let generate_daemon_structs_cleanups_c () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include \"daemon.h\"
#include \"guestfs_protocol.h\"

";

  pr "/* Cleanup functions used by CLEANUP_* macros.  Do not call\n";
  pr " * these functions directly.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      pr "void\n";
      pr "cleanup_free_int_%s (void *ptr)\n" typ;
      pr "{\n";
      pr "  struct guestfs_int_%s *x = (* (struct guestfs_int_%s **) ptr);\n" typ typ;
      pr "\n";
      pr "  if (x) {\n";
      pr "    xdr_free ((xdrproc_t) xdr_guestfs_int_%s, (char *) x);\n" typ;
      pr "    free (x);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";

      pr "void\n";
      pr "cleanup_free_int_%s_list (void *ptr)\n" typ;
      pr "{\n";
      pr "  struct guestfs_int_%s_list *x = (* (struct guestfs_int_%s_list **) ptr);\n"
        typ typ;
      pr "\n";
      pr "  if (x) {\n";
      pr "    xdr_free ((xdrproc_t) xdr_guestfs_int_%s_list, (char *) x);\n"
        typ;
      pr "    free (x);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";

  ) structs

(* Generate structs-cleanups.h file. *)
let generate_daemon_structs_cleanups_h () =
  generate_header CStyle GPLv2plus;

  pr "\
/* These CLEANUP_* macros automatically free the struct or struct list
 * pointed to by the local variable at the end of the current scope.
 */

#ifndef GUESTFS_DAEMON_STRUCTS_CLEANUPS_H_
#define GUESTFS_DAEMON_STRUCTS_CLEANUPS_H_

#ifdef HAVE_ATTRIBUTE_CLEANUP
";

  List.iter (
    fun { s_name = name } ->
      pr "#define CLEANUP_FREE_%s \\\n" (String.uppercase_ascii name);
      pr "  __attribute__((cleanup(cleanup_free_int_%s)))\n" name;
      pr "#define CLEANUP_FREE_%s_LIST \\\n" (String.uppercase_ascii name);
      pr "  __attribute__((cleanup(cleanup_free_int_%s_list)))\n" name
  ) structs;

  pr "#else /* !HAVE_ATTRIBUTE_CLEANUP */\n";

  List.iter (
    fun { s_name = name } ->
      pr "#define CLEANUP_FREE_%s\n" (String.uppercase_ascii name);
      pr "#define CLEANUP_FREE_%s_LIST\n" (String.uppercase_ascii name)
  ) structs;

  pr "\
#endif /* !HAVE_ATTRIBUTE_CLEANUP */

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */

";

  List.iter (
    fun { s_name = name } ->
      pr "extern void cleanup_free_int_%s (void *ptr);\n"
        name;
      pr "extern void cleanup_free_int_%s_list (void *ptr);\n"
        name
  ) structs;

  pr "\n";
  pr "#endif /* GUESTFS_INTERNAL_FRONTEND_CLEANUPS_H_ */\n"
