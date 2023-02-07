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

let generate_header = generate_header ~inputs:["generator/tests_c_api.ml"]

(* Generate the C API tests. *)
let rec generate_c_api_tests () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

/* It is safe to call deprecated functions from this file. */
#define GUESTFS_NO_WARN_DEPRECATED
#undef GUESTFS_NO_DEPRECATED

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#include \"guestfs.h\"
#include \"guestfs-utils.h\"
#include \"structs-cleanups.h\"

#include \"tests.h\"

";

  (* Generate a list of commands which are not tested anywhere. *)
  pr "void\n";
  pr "no_test_warnings (void)\n";
  pr "{\n";
  pr "  size_t i;\n";
  pr "  const char *no_tests[] = {\n";

  let hash : (string, bool) Hashtbl.t = Hashtbl.create 13 in
  List.iter (
    fun { tests } ->
      let seqs = List.filter_map (
        function
        | (_, (Always|IfAvailable _|IfNotCrossAppliance), test, cleanup) ->
          Some (seq_of_test test @ cleanup)
        | (_, Disabled, _, _) -> None
      ) tests in
      let cmds_tested = List.map List.hd (List.concat seqs) in
      List.iter (fun cmd -> Hashtbl.replace hash cmd true) cmds_tested
  ) actions;

  List.iter (
    fun { name } ->
      if not (Hashtbl.mem hash name) then
        pr "    \"%s\",\n" name
  ) (actions |> sort);

  pr "    NULL\n";
  pr "  };\n";
  pr "\n";
  pr "  for (i = 0; no_tests[i] != NULL; ++i)\n";
  pr "    fprintf (stderr, \"warning: \\\"guestfs_%%s\\\" has no tests\\n\",\n";
  pr "             no_tests[i]);\n";
  pr "}\n";
  pr "\n";

  (* Generate the actual tests. *)
  let test_names =
    List.map (
      fun { name; optional; tests } ->
        List.mapi (generate_one_test name optional) tests
    ) (actions |> sort) in
  let test_names = List.concat test_names in

  let nr_tests = List.length test_names in
  pr "size_t nr_tests = %d;\n" nr_tests;
  pr "\n";
  pr "struct test tests[%d] = {\n" nr_tests;
  List.iter (
    fun name ->
      pr "  { .name = \"%s\", .test_fn = %s },\n" (c_quote name) name
  ) test_names;
  pr "};\n"

and generate_one_test name optional i (init, prereq, test, cleanup) =
  let test_name = sprintf "test_%s_%d" name i in
  let not_disabled = prereq != Disabled in

  pr "static int %s_skip (void);\n" test_name;

  if not_disabled then (
    pr "static int %s_perform (guestfs_h *);\n" test_name;
    if cleanup <> [] then
      pr "static int %s_cleanup (guestfs_h *);\n" test_name;
  );
  pr "\n";

  pr "\
static int
%s (guestfs_h *g)
{
  if (%s_skip ()) {
    skipped (\"%s\", \"environment variable set\");
    return 0;
  }

" test_name test_name test_name;

  (* Optional functions should only be tested if the relevant
   * support is available in the daemon.
   *)
  let group_test group =
    let sym = gensym "features" in
    pr "  const char *%s[] = { \"%s\", NULL };\n" sym group;
    pr "  if (!guestfs_feature_available (g, (char **) %s)) {\n" sym;
    pr "    skipped (\"%s\", \"group %%s not available in daemon\",\n"
      test_name;
    pr "             %s[0]);\n" sym;
    pr "    return 0;\n";
    pr "  }\n";
    pr "\n"
  in

  let utsname_test () =
    pr "  if (using_cross_appliance ()) {\n";
    pr "    skipped (\"%s\", \"cannot run when appliance and host are different\");\n"
      test_name;
    pr "    return 0;\n";
    pr "  }\n";
    pr "\n"
  in

  (match optional with
  | Some group -> group_test group
  | None -> ()
  );

  (match prereq with
   | Disabled ->
     pr "  skipped (\"%s\", \"test disabled in generator\");\n" test_name;
     pr "  return 0;\n"
   | IfAvailable group ->
     group_test group;
     generate_one_test_body name i test_name init cleanup
   | Always ->
     generate_one_test_body name i test_name init cleanup
   | IfNotCrossAppliance ->
     utsname_test ();
     generate_one_test_body name i test_name init cleanup
  );

  pr "}\n";
  pr "\n";

  pr "\
static int
%s_skip (void)
{
  const char *str;

  str = getenv (\"TEST_ONLY\");
  if (str)
    return strstr (str, \"%s\") == NULL;
  str = getenv (\"SKIP_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  str = getenv (\"SKIP_TEST_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  return 0;
}

" test_name name
     (String.uppercase_ascii test_name)
     (String.uppercase_ascii name);

  if not_disabled then (
    generate_test_perform name i test_name test;
    if cleanup <> [] then
      generate_test_cleanup test_name cleanup;
  );

  test_name

and generate_one_test_body name i test_name init cleanup =
  (match init with
   | InitNone ->
     pr "  if (init_none (g) == -1)\n";
     pr "    return -1;\n"
   | InitEmpty ->
     pr "  if (init_empty (g) == -1)\n";
     pr "    return -1;\n"
   | InitPartition ->
     pr "  if (init_partition (g) == -1)\n";
     pr "    return -1;\n"
   | InitGPT ->
     pr "  if (init_gpt (g) == -1)\n";
     pr "    return -1;\n"
   | InitBasicFS ->
     pr "  if (init_basic_fs (g) == -1)\n";
     pr "    return -1;\n"
   | InitBasicFSonLVM ->
     pr "  if (init_basic_fs_on_lvm (g) == -1)\n";
     pr "    return -1;\n"
   | InitISOFS ->
     pr "  if (init_iso_fs (g) == -1)\n";
     pr "    return -1;\n"
   | InitScratchFS ->
     pr "  if (init_scratch_fs (g) == -1)\n";
     pr "    return -1;\n"
  );
  pr "\n";

  if cleanup = [] then
    pr "  return %s_perform (g);\n" test_name
  else (
    pr "  int ret = %s_perform (g);\n" test_name;
    pr "  if (%s_cleanup (g) == -1) {\n" test_name;
    pr "    fprintf (stderr, \"%%s (%%d): unexpected error during test cleanups\\n\",\n";
    pr "             \"%s\", %d);\n" name i;
    pr "    return -1;\n";
    pr "  }\n";
    pr "  return ret;\n"
  )

and generate_test_perform name i test_name test =
  pr "static int\n";
  pr "%s_perform (guestfs_h *g)\n" test_name;
  pr "{\n";

  let get_seq_last = function
    | [] ->
        failwithf "%s: you cannot use [] (empty list) when expecting a command"
          test_name
    | seq ->
        let seq = List.rev seq in
        List.rev (List.tl seq), List.hd seq
  in

  (match test with
  | TestRun seq ->
    pr "  /* TestRun for %s (%d) */\n" name i;
    List.iter (generate_test_command_call test_name) seq

  | TestResult (seq, expr) ->
    pr "  /* TestResult for %s (%d) */\n" name i;
    let n = List.length seq in
    List.iteri (
      fun i cmd ->
        let ret = if i = n-1 then "ret" else sprintf "ret%d" (n-i-1) in
        generate_test_command_call ~ret test_name cmd
    ) seq;
    pr "  if (! (%s)) {\n" expr;
    pr "    fprintf (stderr, \"%%s: test failed: expression false: %%s\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name (c_quote expr);
    pr "    if (!guestfs_get_trace (g))\n";
    pr "      fprintf (stderr, \"Set LIBGUESTFS_TRACE=1 to see values returned from API calls.\\n\");\n";
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultString (seq, expected) ->
    pr "  /* TestResultString for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (! STREQ (ret, \"%s\")) {\n" (c_quote expected);
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return \\\"%%s\\\" but it returned \\\"%%s\\\"\\n\",\n";
    pr "             \"%s\", \"%s\", \"%s\", ret);\n"
      test_name (List.hd last) (c_quote expected);
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultDevice (seq, expected) ->
    pr "  /* TestResultDevice for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (compare_devices (ret, \"%s\") != 0) {\n" (c_quote expected);
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return \\\"%%s\\\" but it returned \\\"%%s\\\"\\n\",\n";
    pr "             \"%s\", \"%s\", \"%s\", ret);\n"
      test_name (List.hd last) (c_quote expected);
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultTrue seq ->
    pr "  /* TestResultTrue for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (!ret) {\n";
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return 'true' but it returned 'false'\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name (List.hd last);
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultFalse seq ->
    pr "  /* TestResultFalse for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (ret) {\n";
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return 'false' but it returned 'true'\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name (List.hd last);
    pr "    return -1;\n";
    pr "  }\n"

  | TestLastFail seq ->
    pr "  /* TestLastFail for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~expect_error:true last

  | TestRunOrUnsupported seq ->
    pr "  /* TestRunOrUnsupported for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~expect_error:true ~do_return:false ~ret:"ret" last;
    pr "  if (ret == -1) {\n";
    pr "    if (guestfs_last_errno (g) == ENOTSUP) {\n";
    pr "      skipped (\"%s\", \"last command %%s returned ENOTSUP\", \"%s\");\n"
      test_name (List.hd last);
    pr "      return 0;\n";
    pr "    }\n";
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to pass or fail with ENOTSUP, but it failed with %%d: %%s\\n\",\n";
    pr "             \"%s\", \"%s\", guestfs_last_errno (g), guestfs_last_error (g));\n"
      test_name (List.hd last);
    pr "    return -1;\n";
    pr "  }\n"
  );

  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

and generate_test_cleanup test_name cleanup =
  pr "static int\n";
  pr "%s_cleanup (guestfs_h *g)\n" test_name;
  pr "{\n";
  List.iter (generate_test_command_call test_name) cleanup;
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

(* Generate the code to run a command, leaving the result in the C
 * variable named 'ret'.  If you expect to get an error then you should
 * set expect_error:true.
 *)
and generate_test_command_call ?(expect_error = false) ?(do_return = true) ?test ?ret test_name cmd=
  let ret = match ret with Some ret -> ret | None -> gensym "ret" in

  let name, args =
    match cmd with [] -> assert false | name :: args -> name, args in

  (* Look up the function. *)
  let f = Actions.find name in

  (* Look up the arguments and return type. *)
  let style_ret, style_args, style_optargs = f.style in

  (* Match up the arguments strings and argument types. *)
  let args, optargs =
    let rec loop argts args =
      match argts, args with
      | (t::ts), (s::ss) ->
        let args, rest = loop ts ss in
        ((t, s) :: args), rest
      | [], ss -> [], ss
      | ts, [] ->
        failwithf "%s: in test, too few args given to function %s"
          test_name name
    in
    let args, optargs = loop style_args args in
    let optargs, rest = loop style_optargs optargs in
    if rest <> [] then
      failwithf "%s: in test, too many args given to function %s"
        test_name name;
    args, optargs in

  (* Generate a new symbol for each arg, and one for optargs. *)
  let args = List.map (fun (arg, value) -> arg, value, gensym "arg") args in
  let optargs_sym = gensym "optargs" in

  List.iter (
    function
    | OptString _, "NULL", _ -> ()
    | String ((Pathname|Device|Mountable|Dev_or_Path|Mountable_or_Path
               |PlainString|Key|GUID|Filename), _), arg, sym
    | OptString _, arg, sym ->
      pr "  const char *%s = \"%s\";\n" sym (c_quote arg);
    | BufferIn _, arg, sym ->
      pr "  const char *%s = \"%s\";\n" sym (c_quote arg);
      pr "  size_t %s_size = %d;\n" sym (String.length arg)
    | Int _, _, _
    | Int64 _, _, _
    | Bool _, _, _ -> ()
    | String (FileIn, _), arg, sym ->
      pr "  CLEANUP_FREE char *%s = substitute_srcdir (\"%s\");\n"
        sym (c_quote arg)
    | String (FileOut, _), _, _ -> ()
    | StringList (_, _), "", sym ->
      pr "  const char *const %s[1] = { NULL };\n" sym
    | StringList (_, _), arg, sym ->
      let strs = String.nsplit " " arg in
      List.iteri (
        fun i str ->
          pr "  const char *%s_%d = \"%s\";\n" sym i (c_quote str);
      ) strs;
      pr "  const char *const %s[] = {\n" sym;
      List.iteri (
        fun i _ -> pr "    %s_%d,\n" sym i
      ) strs;
      pr "    NULL\n";
      pr "  };\n";
    | Pointer _, _, _ ->
      (* Difficult to make these pointers in order to run a test. *)
      assert false
  ) args;

  if optargs <> [] then (
    pr "  struct %s %s;\n" f.c_function optargs_sym;
    let _, bitmask = List.fold_left (
      fun (shift, bitmask) optarg ->
        let is_set =
          match optarg with
          | OBool n, "" -> false
          | OBool n, "true" ->
            pr "  %s.%s = 1;\n" optargs_sym n; true
          | OBool n, "false" ->
            pr "  %s.%s = 0;\n" optargs_sym n; true
          | OBool n, arg ->
            failwithf "boolean optional arg '%s' should be empty string or \"true\" or \"false\"" n
          | OInt n, "" -> false
          | OInt n, i ->
            let i =
              try int_of_string i
              with Failure _ -> failwithf "integer optional arg '%s' should be empty string or number" n in
            pr "  %s.%s = %d;\n" optargs_sym n i; true
          | OInt64 n, "" -> false
          | OInt64 n, i ->
            let i =
              try Int64.of_string i
              with Failure _ -> failwithf "int64 optional arg '%s' should be empty string or number" n in
            pr "  %s.%s = %Ld;\n" optargs_sym n i; true
          | OString n, "NOARG" -> false
          | OString n, arg ->
            pr "  %s.%s = \"%s\";\n" optargs_sym n (c_quote arg); true
          | OStringList n, "NOARG" -> false
          | OStringList n, "" ->
            pr "  const char *const %s[1] = { NULL };\n" n; true
          | OStringList n, arg ->
            let strs = String.nsplit " " arg in
            List.iteri (
              fun i str ->
                pr "  const char *%s_%d = \"%s\";\n" n i (c_quote str);
            ) strs;
            pr "  const char *const %s[] = {\n" n;
            List.iteri (
              fun i _ -> pr "    %s_%d,\n" n i
            ) strs;
            pr "    NULL\n";
            pr "  };\n"; true in
        let bit = if is_set then Int64.shift_left 1L shift else 0L in
        let bitmask = Int64.logor bitmask bit in
        let shift = shift + 1 in
        (shift, bitmask)
    ) (0, 0L) optargs in
    pr "  %s.bitmask = UINT64_C(0x%Lx);\n" optargs_sym bitmask;
  );

  (match style_ret with
  | RErr | RInt _ | RBool _ -> pr "  int %s;\n" ret
  | RInt64 _ -> pr "  int64_t %s;\n" ret
  | RConstString _ | RConstOptString _ ->
    pr "  const char *%s;\n" ret
  | RString _ ->
    pr "  CLEANUP_FREE char *%s;\n" ret
  | RStringList _ | RHashtable _ ->
    pr "  CLEANUP_FREE_STRING_LIST char **%s;\n" ret;
  | RStruct (_, typ) ->
    pr "  CLEANUP_FREE_%s struct guestfs_%s *%s;\n"
      (String.uppercase_ascii typ) typ ret
  | RStructList (_, typ) ->
    pr "  CLEANUP_FREE_%s_LIST struct guestfs_%s_list *%s;\n"
      (String.uppercase_ascii typ) typ ret
  | RBufferOut _ ->
    pr "  CLEANUP_FREE char *%s;\n" ret;
    pr "  size_t size;\n"
  );

  if expect_error then
    pr "  guestfs_push_error_handler (g, NULL, NULL);\n";
  pr "  %s = %s (g" ret f.c_function;

  (* Generate the parameters. *)
  List.iter (
    function
    | OptString _, "NULL", _ -> pr ", NULL"
    | String (FileOut, _), arg, _ -> pr ", \"%s\"" (c_quote arg)
    | String _, _, sym
    | OptString _, _, sym -> pr ", %s" sym
    | BufferIn _, _, sym -> pr ", %s, %s_size" sym sym
    | StringList _, _, sym ->
      pr ", (char **) %s" sym
    | Int _, arg, _ ->
      let i =
        try int_of_string arg
        with Failure _ ->
          failwithf "%s: expecting an int, but got '%s'" test_name arg in
      pr ", %d" i
    | Int64 _, arg, _ ->
      let i =
        try Int64.of_string arg
        with Failure _ ->
          failwithf "%s: expecting an int64, but got '%s'" test_name arg in
      pr ", %Ld" i
    | Bool _, arg, _ ->
      let b = bool_of_string arg in pr ", %d" (if b then 1 else 0)
    | Pointer _, _, _ -> assert false
  ) args;

  (match style_ret with
  | RBufferOut _ -> pr ", &size"
  | _ -> ()
  );

  if optargs <> [] then
    pr ", &%s" optargs_sym;

  pr ");\n";

  if expect_error then
    pr "  guestfs_pop_error_handler (g);\n";

  let ret_errcode =
    if do_return then errcode_of_ret style_ret
    else `CannotReturnError in

  (match ret_errcode, expect_error with
  | `CannotReturnError, _ -> ()
  | `ErrorIsMinusOne, false ->
    pr "  if (%s == -1)\n" ret;
    pr "    return -1;\n";
  | `ErrorIsMinusOne, true ->
    pr "  if (%s != -1)\n" ret;
    pr "    return -1;\n";
  | `ErrorIsNULL, false ->
    pr "  if (%s == NULL)\n" ret;
    pr "      return -1;\n";
  | `ErrorIsNULL, true ->
    pr "  if (%s != NULL)\n" ret;
    pr "    return -1;\n";
  );

  (* Insert the test code. *)
  (match test with
  | None -> ()
  | Some f -> f ret
  )

and gensym prefix =
  sprintf "%s%d" prefix (unique ())
