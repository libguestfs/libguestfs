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
open Prepopts
open C
open Events
open Fish_commands

let generate_header = generate_header ~inputs:["generator/fish.ml"]

type func =
  | Function of string           (* The description. *)
  | Alias of string              (* The function of which it is one the
                                  * aliases.
                                  *)

let func_compare (n1, _) (n2, _) = compare n1 n2

let fish_functions_and_commands_sorted =
  List.sort action_compare ((actions |> fish_functions |> sort) @ fish_commands)

let doc_opttype_of = function
  | OBool n -> "true|false"
  | OInt n
  | OInt64 n -> "N"
  | OString n
  | OStringList n -> ".."

let get_aliases { fish_alias; non_c_aliases } =
  let non_c_aliases =
    List.map (fun n -> String.replace_char n '_' '-') non_c_aliases in
  fish_alias @ non_c_aliases

let all_functions_commands_and_aliases_sorted =
  let all =
    List.fold_right (
      fun ({ name; shortdesc } as f) acc ->
        let aliases = get_aliases f in
        let aliases = List.filter (
          fun x ->
            Filename.check_suffix x "-opts" <> true
        ) aliases in
        let aliases = List.map (fun x -> x, Alias name) aliases in
        let foo = (name, Function shortdesc) :: aliases in
        foo @ acc
    ) ((actions |> fish_functions |> sort) @ fish_commands) [] in
  List.sort func_compare all

let c_quoted_indented ~indent str =
  let str = c_quote str in
  let str = String.replace str "\\n" ("\\n\"\n" ^ indent ^ "\"") in
  str

(* Generate run_* functions and header for libguestfs API functions. *)
let generate_fish_run_cmds actions () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "/* It is safe to call deprecated functions from this file. */\n";
  pr "#define GUESTFS_NO_WARN_DEPRECATED\n";
  pr "#undef GUESTFS_NO_DEPRECATED\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <libintl.h>\n";
  pr "#include <errno.h>\n";
  pr "\n";
  pr "#include \"full-write.h\"\n";
  pr "#include \"xstrtol.h\"\n";
  pr "#include \"getprogname.h\"\n";
  pr "\n";
  pr "#include \"guestfs.h\"\n";
  pr "#include \"guestfs-utils.h\"\n";
  pr "#include \"structs-print.h\"\n";
  pr "\n";
  pr "#include \"fish.h\"\n";
  pr "#include \"options.h\"\n";
  pr "#include \"fish-cmds.h\"\n";
  pr "#include \"run.h\"\n";
  pr "\n";
  pr "/* Valid suffixes allowed for numbers.  See Gnulib xstrtol function. */\n";
  pr "static const char xstrtol_suffixes[] = \"0kKMGTPEZY\";\n";
  pr "\n";

  let emit_print_list_function typ =
    pr "\n";
    pr "static void\n";
    pr "print_%s_list (struct guestfs_%s_list *%ss)\n"
      typ typ typ;
    pr "{\n";
    pr "  size_t i;\n";
    pr "\n";
    pr "  for (i = 0; i < %ss->len; ++i) {\n" typ;
    pr "    printf (\"[%%zu] = {\\n\", i);\n";
    pr "    guestfs_int_print_%s_indent (&%ss->val[i], stdout, \"\\n\", \"  \");\n"
      typ typ;
    pr "    printf (\"}\\n\");\n";
    pr "  }\n";
    pr "}\n";
  in

  (* Emit a print_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_print_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> fish_functions));

  (* Emit a print_TYPE function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructOnly | RStructAndList) ->
        pr "\n";
        pr "static void\n";
        pr "print_%s (struct guestfs_%s *%s)\n" typ typ typ;
        pr "{\n";
        pr "  guestfs_int_print_%s_indent (%s, stdout, \"\\n\", \"\");\n"
          typ typ;
        pr "}\n";
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by (actions |> fish_functions));

  List.iter (
    fun { name; style = (ret, args, optargs as style);
          fish_output; c_function; c_optarg_prefix } ->
      pr "\n";
      pr "int\n";
      pr "run_%s (const char *cmd, size_t argc, char *argv[])\n" name;
      pr "{\n";
      pr "  int ret = RUN_ERROR;\n";
      (match ret with
       | RErr
       | RInt _
       | RBool _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ | RConstOptString _ -> pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) -> pr "  struct guestfs_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  char *r;\n";
           pr "  size_t size;\n";
      );
      List.iter (
        function
        | OptString n
        | String ((PlainString|Device|Mountable|GUID|Filename), n) ->
           pr "  const char *%s;\n" n
        | String ((Pathname|Dev_or_Path|Mountable_or_Path
                   |FileIn|FileOut|Key), n) ->
           pr "  char *%s;\n" n
        | BufferIn n ->
            pr "  const char *%s;\n" n;
            pr "  size_t %s_size;\n" n
        | StringList (_, n) ->
            pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  int64_t %s;\n" n
        | Pointer _ -> assert false
      ) args;

      if optargs <> [] then (
        pr "  struct %s optargs_s = { .bitmask = 0 };\n" c_function;
        pr "  struct %s *optargs = &optargs_s;\n" c_function
      );

      if args <> [] || optargs <> [] then
        pr "  size_t i = 0;\n";

      pr "\n";

      (* Check and convert parameters. *)
      let argc_minimum, argc_maximum =
        let args_no_keys =
          List.filter (function String (Key, _) -> false | _ -> true) args in
        let argc_minimum = List.length args_no_keys in
        let argc_maximum = argc_minimum + List.length optargs in
        argc_minimum, argc_maximum in

      if argc_minimum = argc_maximum then (
        pr "  if (argc != %d) {\n" argc_minimum;
          pr "    ret = RUN_WRONG_ARGS;\n";
      ) else if argc_minimum = 0 then (
        pr "  if (argc > %d) {\n" argc_maximum;
        pr "    ret = RUN_WRONG_ARGS;\n";
      ) else (
        pr "  if (argc < %d || argc > %d) {\n" argc_minimum argc_maximum;
        pr "    ret = RUN_WRONG_ARGS;\n";
      );
      pr "    goto out_noargs;\n";
      pr "  }\n";

      let parse_integer ?(indent = "  ") expr fn fntyp rtyp range name out =
        pr "%s{\n" indent;
        pr "%s  strtol_error xerr;\n" indent;
        pr "%s  %s r;\n" indent fntyp;
        pr "\n";
        pr "%s  xerr = %s (%s, NULL, 0, &r, xstrtol_suffixes);\n"
          indent fn expr;
        pr "%s  if (xerr != LONGINT_OK) {\n" indent;
        pr "%s    fprintf (stderr,\n" indent;
        pr "%s             _(\"%%s: %%s: invalid integer parameter (%%s returned %%u)\\n\"),\n" indent;
        pr "%s             cmd, \"%s\", \"%s\", xerr);\n" indent name fn;
        pr "%s    goto %s;\n" indent out;
        pr "%s  }\n" indent;
        (match range with
         | None -> ()
         | Some (min, max, comment) ->
             pr "%s  /* %s */\n" indent comment;
             pr "%s  if (r < %s || r > %s) {\n" indent min max;
             pr "%s    fprintf (stderr, _(\"%%s: %%s: integer out of range\\n\"), cmd, \"%s\");\n"
               indent name;
             pr "%s    goto %s;\n" indent out;
             pr "%s  }\n" indent;
             pr "%s  /* The check above should ensure this assignment does not overflow. */\n" indent;
        );
        pr "%s  %s = r;\n" indent name;
        pr "%s}\n" indent;
      in

      List.iter (
        function
        | String ((Device|Mountable|PlainString|GUID|Filename), name) ->
            pr "  %s = argv[i++];\n" name
        | String ((Pathname|Dev_or_Path|Mountable_or_Path), name) ->
            pr "  %s = win_prefix (argv[i++]); /* process \"win:\" prefix */\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | OptString name ->
            pr "  %s = STRNEQ (argv[i], \"\") ? argv[i] : NULL;\n" name;
            pr "  i++;\n"
        | BufferIn name ->
            pr "  %s = argv[i];\n" name;
            pr "  %s_size = strlen (argv[i]);\n" name;
            pr "  i++;\n"
        | String (FileIn, name) ->
            pr "  %s = file_in (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | String (FileOut, name) ->
            pr "  %s = file_out (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | StringList (_, name) ->
            pr "  %s = parse_string_list (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | String (Key, name) ->
            pr "  %s = read_key (\"%s\");\n" name name;
            pr "  if (keys_from_stdin)\n";
            pr "    input_lineno++;\n";
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | Bool name ->
            pr "  switch (guestfs_int_is_true (argv[i++])) {\n";
            pr "    case -1:\n";
            pr "      fprintf (stderr,\n";
            pr "               _(\"%%s: '%%s': invalid boolean value, use 'true' or 'false'\\n\"),\n";
            pr "               getprogname (), argv[i-1]);\n";
            pr "      goto out_%s;\n" name;
            pr "    case 0:  %s = 0; break;\n" name;
            pr "    default: %s = 1;\n" name;
            pr "  }\n"
        | Int name ->
            let range =
              let min = "(-(2LL<<30))"
              and max = "((2LL<<30)-1)"
              and comment =
                "The Int type in the generator is a signed 31 bit int." in
              Some (min, max, comment) in
            parse_integer "argv[i++]" "xstrtoll" "long long" "int" range
              name (sprintf "out_%s" name)
        | Int64 name ->
            parse_integer "argv[i++]" "xstrtoll" "long long" "int64_t" None
              name (sprintf "out_%s" name)
        | Pointer _ -> assert false
      ) args;

      (* Optional arguments are prefixed with <argname>:<value> and
       * may be missing, so we need to parse those until the end of
       * the argument list.
       *)
      if optargs <> [] then (
        pr "\n";
        pr "  for (; i < argc; ++i) {\n";
        pr "    uint64_t this_mask;\n";
        pr "    const char *this_arg;\n";
        pr "\n";
        pr "    ";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase_ascii n in
            let len = String.length n in
            pr "if (STRPREFIX (argv[i], \"%s:\")) {\n" n;
            (match argt with
             | OBool n ->
                 pr "      switch (guestfs_int_is_true (&argv[i][%d])) {\n" (len+1);
                 pr "        case -1:\n";
                 pr "          fprintf (stderr,\n";
                 pr "                   _(\"%%s: '%%s': invalid boolean value, use 'true' or 'false'\\n\"),\n";
                 pr "                   getprogname (), &argv[i][%d]);\n" (len+1);
                 pr "          goto out;\n";
                 pr "        case 0:  optargs_s.%s = 0; break;\n" n;
                 pr "        default: optargs_s.%s = 1;\n" n;
                 pr "      }\n"
             | OInt n ->
                 let range =
                   let min = "(-(2LL<<30))"
                   and max = "((2LL<<30)-1)"
                   and comment =
                     "The Int type in the generator is a signed 31 bit int." in
                   Some (min, max, comment) in
                 let expr = sprintf "&argv[i][%d]" (len+1) in
                 parse_integer ~indent:"      "
                   expr "xstrtoll" "long long" "int" range
                   (sprintf "optargs_s.%s" n) "out"
             | OInt64 n ->
                 let expr = sprintf "&argv[i][%d]" (len+1) in
                 parse_integer ~indent:"      "
                   expr "xstrtoll" "long long" "int64_t" None
                   (sprintf "optargs_s.%s" n) "out"
             | OString n ->
                 pr "      optargs_s.%s = &argv[i][%d];\n" n (len+1);
             | OStringList name ->
               pr "      optargs_s.%s = parse_string_list (&argv[i][%d]);\n" name (len+1);
               pr "      if (optargs_s.%s == NULL) goto out;\n" name
            );
            pr "      this_mask = %s_%s_BITMASK;\n" c_optarg_prefix uc_n;
            pr "      this_arg = \"%s\";\n" n;
            pr "    }\n";
            pr "    else ";
        ) optargs;

        pr "{\n";
        pr "      fprintf (stderr, _(\"%%s: unknown optional argument \\\"%%s\\\"\\n\"),\n";
        pr "               cmd, argv[i]);\n";
        pr "      goto out;\n";
        pr "    }\n";
        pr "\n";
        pr "    if (optargs_s.bitmask & this_mask) {\n";
        pr "      fprintf (stderr, _(\"%%s: optional argument \\\"%%s\\\" given more than once\\n\"),\n";
        pr "               cmd, this_arg);\n";
        pr "      goto out;\n";
        pr "    }\n";
        pr "    optargs_s.bitmask |= this_mask;\n";
        pr "  }\n";
        pr "\n";
      );

      (* Call C API function. *)
      pr "  r = %s " c_function;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Check return value for errors and display command results. *)
      (match ret with
       | RErr ->
           pr "  if (r == -1) goto out;\n";
           pr "  ret = 0;\n"
       | RInt _ ->
           pr "  if (r == -1) goto out;\n";
           pr "  ret = 0;\n";
           (match fish_output with
            | None ->
                pr "  printf (\"%%d\\n\", r);\n";
            | Some FishOutputOctal ->
                pr "  printf (\"%%s%%o\\n\", r != 0 ? \"0\" : \"\", (unsigned) r);\n";
            | Some FishOutputHexadecimal ->
                pr "  printf (\"%%s%%x\\n\", r != 0 ? \"0x\" : \"\", (unsigned) r);\n"
           )
       | RInt64 _ ->
           pr "  if (r == -1) goto out;\n";
           pr "  ret = 0;\n";
           (match fish_output with
            | None ->
                pr "  printf (\"%%\" PRIi64 \"\\n\", r);\n";
            | Some FishOutputOctal ->
                pr "  printf (\"%%s%%\" PRIo64 \"\\n\", r != 0 ? \"0\" : \"\", r);\n";
            | Some FishOutputHexadecimal ->
                pr "  printf (\"%%s%%\" PRIx64 \"\\n\", r != 0 ? \"0x\" : \"\", (uint64_t) r);\n"
           )
       | RBool _ ->
           pr "  if (r == -1) goto out;\n";
           pr "  ret = 0;\n";
           pr "  if (r) printf (\"true\\n\"); else printf (\"false\\n\");\n"
       | RConstString _ ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  printf (\"%%s\\n\", r);\n"
       | RConstOptString _ ->
           pr "  ret = 0;\n";
           pr "  printf (\"%%s\\n\", r ? : \"(null)\");\n"
       | RString _ ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  printf (\"%%s\\n\", r);\n";
           pr "  free (r);\n"
       | RStringList _ ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  print_strings (r);\n";
           pr "  guestfs_int_free_string_list (r);\n"
       | RStruct (_, typ) ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  print_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ
       | RStructList (_, typ) ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  print_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ
       | RHashtable _ ->
           pr "  if (r == NULL) goto out;\n";
           pr "  ret = 0;\n";
           pr "  print_table (r);\n";
           pr "  guestfs_int_free_string_list (r);\n"
       | RBufferOut _ ->
           pr "  if (r == NULL) goto out;\n";
           pr "  if (full_write (1, r, size) != size) {\n";
           pr "    perror (\"write\");\n";
           pr "    free (r);\n";
           pr "    goto out;\n";
           pr "  }\n";
           pr "  ret = 0;\n";
           pr "  free (r);\n"
      );

      (* Free arguments in reverse order. *)
      (match ret with
      | RConstOptString _ -> ()
      | _ -> pr " out:\n");
      List.iter (
        function
        | OStringList n ->
          let uc_n = String.uppercase_ascii n in
          pr "  if ((optargs_s.bitmask & %s_%s_BITMASK) &&\n"
            c_optarg_prefix uc_n;
          pr "      optargs_s.%s != NULL)\n" n;
          pr "    guestfs_int_free_string_list ((char **) optargs_s.%s);\n" n
        | OBool _ | OInt _ | OInt64 _ | OString _ -> ()
      ) (List.rev optargs);
      List.iter (
        function
        | String ((Device|Mountable|PlainString|GUID|Filename), _)
        | OptString _
        | BufferIn _ -> ()
        | Bool name
        | Int name | Int64 name ->
            pr " out_%s:\n" name
        | String ((Pathname|Dev_or_Path|Mountable_or_Path|FileOut|Key), name) ->
            pr "  free (%s);\n" name;
            pr " out_%s:\n" name
        | String (FileIn, name) ->
            pr "  free_file_in (%s);\n" name;
            pr " out_%s:\n" name
        | StringList (_, name) ->
            pr "  guestfs_int_free_string_list (%s);\n" name;
            pr " out_%s:\n" name
        | Pointer _ -> assert false
      ) (List.rev args);

      (* Return. *)
      pr " out_noargs:\n";
      pr "  return ret;\n";
      pr "}\n";
  ) (actions |> fish_functions |> sort)

let generate_fish_run_header () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef FISH_RUN_H\n";
  pr "#define FISH_RUN_H\n";
  pr "\n";

  pr "/* Return these errors from run_* functions. */\n";
  pr "#define RUN_ERROR -1\n";
  pr "#define RUN_WRONG_ARGS -2\n";
  pr "\n";

  List.iter (
    fun { name } ->
      pr "extern int run_%s (const char *cmd, size_t argc, char *argv[]);\n"
        name
  ) (actions |> fish_functions |> sort);

  pr "\n";
  pr "#endif /* FISH_RUN_H */\n"

let generate_fish_cmd_entries actions () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "\n";
  pr "#include \"cmds-gperf.h\"\n";
  pr "#include \"run.h\"\n";
  pr "\n";

  List.iter (
    fun ({ name; style = _, args, optargs; shortdesc; longdesc } as f) ->
      let aliases = get_aliases f in

      let name2 = String.replace_char name '_' '-' in

      let longdesc = String.replace longdesc "C<guestfs_" "C<" in
      let synopsis =
        match args with
        | [] -> name2
        | args ->
            let args =
              List.filter (function String (Key, _) -> false
                                  | _ -> true) args in
            sprintf "%s%s%s"
              name2
              (String.concat ""
                 (List.map (fun arg -> " " ^ name_of_argt arg) args))
              (String.concat ""
                 (List.map (fun arg ->
                   sprintf " [%s:%s]" (name_of_optargt arg) (doc_opttype_of arg)
                  ) optargs)) in

      let warnings =
        if List.exists (function String (Key, _) -> true | _ -> false) args then
          "\n\nThis command has one or more key or passphrase parameters.
Guestfish will prompt for these separately."
        else "" in

      let warnings =
        warnings ^
          if f.protocol_limit_warning then
            "\n\n" ^ protocol_limit_warning
          else "" in

      let warnings =
        warnings ^
          match deprecation_notice ~replace_underscores:true f with
          | None -> ""
          | Some txt -> "\n\n" ^ txt in

      let describe_alias =
        if aliases <> [] then
          sprintf "\n\nYou can use %s as an alias for this command."
            (String.concat " or " (List.map (fun s -> "'" ^ s ^ "'") aliases))
        else "" in

      let pod =
        sprintf "%s - %s\n\n=head1 SYNOPSIS\n\n %s\n\n=head1 DESCRIPTION\n\n%s%s%s"
          name2 shortdesc synopsis longdesc warnings describe_alias in
      let text =
        String.concat "\n" (pod2text ~trim:false ~discard:false "NAME" pod)
        ^ "\n" in

      pr "struct command_entry %s_cmd_entry = {\n" name;
      pr "  .name = \"%s\",\n" name2;
      pr "  .help = \"%s\",\n" (c_quoted_indented ~indent:"          " text);
      pr "  .synopsis = \"%s\",\n" (c_quote synopsis);
      pr "  .run = run_%s\n" name;
      pr "};\n";
      pr "\n";
  ) (actions |> fish_functions |> sort)

(* Generate a lot of different functions for guestfish. *)
let generate_fish_cmds () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <libintl.h>\n";
  pr "#include <errno.h>\n";
  pr "\n";
  pr "#include \"guestfs.h\"\n";
  pr "#include \"guestfs-utils.h\"\n";
  pr "#include \"structs-print.h\"\n";
  pr "\n";
  pr "#include \"fish.h\"\n";
  pr "#include \"fish-cmds.h\"\n";
  pr "#include \"options.h\"\n";
  pr "#include \"cmds-gperf.h\"\n";
  pr "#include \"run.h\"\n";
  pr "\n";

  (* List of command_entry structs for pure guestfish commands. *)
  List.iter (
    fun ({ name; shortdesc; longdesc } as f) ->
      let aliases = get_aliases f in

      let name2 = String.replace_char name '_' '-' in
      let describe_alias =
        if aliases <> [] then
          sprintf "\n\nYou can use %s as an alias for this command."
            (String.concat " or " (List.map (fun s -> "'" ^ s ^ "'") aliases))
        else "" in

      let pod =
        sprintf "%s - %s\n\n=head1 DESCRIPTION\n\n%s\n\n%s"
          name2 shortdesc longdesc describe_alias in
      let text =
        String.concat "\n" (pod2text ~trim:false ~discard:false "NAME" pod)
        ^ "\n" in

      pr "struct command_entry %s_cmd_entry = {\n" name;
      pr "  .name = \"%s\",\n" name2;
      pr "  .help = \"%s\",\n" (c_quoted_indented ~indent:"          " text);
      pr "  .synopsis = NULL,\n";
      pr "  .run = run_%s\n" name;
      pr "};\n";
      pr "\n";
  ) fish_commands;

  (* list_commands function, which implements guestfish -h *)
  pr "void\n";
  pr "list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", _(\"Command\"), _(\"Description\"));\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, f) ->
      let name = String.replace_char name '_' '-' in
      match f with
      | Function shortdesc ->
        pr "  printf (\"%%-20s %%s\\n\", \"%s\", _(\"%s\"));\n"
          name shortdesc
      | Alias f ->
        let f = String.replace_char f '_' '-' in
        pr "  printf (\"%%-20s \", \"%s\");\n" name;
        pr "  printf (_(\"alias for '%%s'\"), \"%s\");\n" f;
        pr "  putchar ('\\n');\n"
  ) all_functions_commands_and_aliases_sorted;
  pr "  printf (\"    %%s\\n\",";
  pr "          _(\"Use -h <cmd> / help <cmd> to show detailed help for a command.\"));\n";
  pr "}\n";
  pr "\n"

and generate_fish_cmds_h () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef FISH_CMDS_H\n";
  pr "#define FISH_CMDS_H\n";
  pr "\n";

  List.iter (
    fun { name } ->
      pr "extern int run_%s (const char *cmd, size_t argc, char *argv[]);\n"
        name
  ) fish_commands;

  pr "\n";
  pr "#endif /* FISH_CMDS_H */\n"

(* gperf code to do fast lookups of commands. *)
and generate_fish_cmds_gperf () =
  generate_header CStyle GPLv2plus;

  pr "\
%%language=ANSI-C
%%define lookup-function-name lookup_fish_command
%%ignore-case
%%readonly-tables
%%null-strings

%%{

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>

#include \"fish.h\"
#include \"run.h\"
#include \"cmds-gperf.h\"

";

  List.iter (
    fun { name } ->
      pr "extern struct command_entry %s_cmd_entry;\n" name
  ) fish_functions_and_commands_sorted;

  pr "\
%%}

struct command_table;

%%%%
";

  List.iter (
    fun ({ name } as f) ->
      let aliases = get_aliases f in
      let name2 = String.replace_char name '_' '-' in

      (* The basic command. *)
      pr "%s, &%s_cmd_entry\n" name name;

      (* Command with dashes instead of underscores. *)
      if name <> name2 then
        pr "%s, &%s_cmd_entry\n" name2 name;

      (* Aliases for the command. *)
      List.iter (
        fun alias ->
          pr "%s, &%s_cmd_entry\n" alias name;
      ) aliases;
  ) fish_functions_and_commands_sorted;

  pr "\
%%%%

int
display_command (const char *cmd)
{
  const struct command_table *ct;

  ct = lookup_fish_command (cmd, strlen (cmd));
  if (ct) {
    fputs (ct->entry->help, stdout);
    return 0;
  }
  else
    return display_builtin_command (cmd);
}

int
run_action (const char *cmd, size_t argc, char *argv[])
{
  const struct command_table *ct;
  int ret = -1;

  ct = lookup_fish_command (cmd, strlen (cmd));
  if (ct) {
    ret = ct->entry->run (cmd, argc, argv);
    /* run function may return magic value -2 (RUN_WRONG_ARGS) to indicate
     * that this function should print the command synopsis.
     */
    if (ret == RUN_WRONG_ARGS) {
      fprintf (stderr, _(\"error: incorrect number of arguments\\n\"));
      if (ct->entry->synopsis)
        fprintf (stderr, _(\"usage: %%s\\n\"), ct->entry->synopsis);
      fprintf (stderr, _(\"type 'help %%s' for more help on %%s\\n\"), cmd, cmd);
      ret = -1;
    }
  }
  else {
    fprintf (stderr, _(\"%%s: unknown command\\n\"), cmd);
    if (command_num == 1)
      extended_help_message ();
  }
  return ret;
}
"

(* Readline completion for guestfish. *)
and generate_fish_completion () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#endif

#include \"fish.h\"

#ifdef HAVE_LIBREADLINE

static const char *const commands[] = {
  BUILTIN_COMMANDS_FOR_COMPLETION,
";

  (* Get the commands, including the aliases.  They don't need to be
   * sorted - the generator() function just does a dumb linear search.
   *)
  let commands =
    List.map (
      fun ({ name } as f) ->
        let aliases = get_aliases f in
        let name2 = String.replace_char name '_' '-' in
        name2 :: aliases
    ) (fish_functions_and_commands_sorted) in
  let commands = List.flatten commands in

  List.iter (pr "  \"%s\",\n") commands;

  pr "  NULL
};

static char *
generator (const char *text, int state)
{
  static size_t index, len;
  const char *name;

  if (!state) {
    index = 0;
    len = strlen (text);
  }

  rl_attempted_completion_over = 1;

  while ((name = commands[index]) != NULL) {
    index++;
    if (STRCASEEQLEN (name, text, len))
      return strdup (name);
  }

  return NULL;
}

#endif /* HAVE_LIBREADLINE */

#ifdef HAVE_RL_COMPLETION_MATCHES
#define RL_COMPLETION_MATCHES rl_completion_matches
#else
#ifdef HAVE_COMPLETION_MATCHES
#define RL_COMPLETION_MATCHES completion_matches
#endif
#endif /* else just fail if we don't have either symbol */

char **
do_completion (const char *text, int start, int end)
{
  char **matches = NULL;

#ifdef HAVE_LIBREADLINE
  rl_completion_append_character = ' ';

  if (start == 0)
    matches = RL_COMPLETION_MATCHES (text, generator);
  else if (complete_dest_paths)
    matches = RL_COMPLETION_MATCHES (text, complete_dest_paths_generator);
#endif

  return matches;
}
";

(* Generate the POD documentation for guestfish. *)
and generate_fish_actions_pod () =
  generate_header PODStyle GPLv2plus;

  let rex = Str.regexp "C<guestfs_\\([^>]+\\)>" in

  List.iter (
    fun ({ name; style = _, args, optargs; longdesc } as f) ->
      let aliases = get_aliases f in

      let longdesc =
        Str.global_substitute rex (
          fun s ->
            let sub =
              try Str.matched_group 1 s
              with Not_found ->
                failwithf "error substituting C<guestfs_...> in longdesc of function %s" name in
            "L</" ^ String.replace_char sub '_' '-' ^ ">"
        ) longdesc in
      let name = String.replace_char name '_' '-' in

      List.iter (
        fun name ->
          pr "=head2 %s\n\n" name
      ) (name :: aliases);
      pr " %s" name;
      List.iter (
        function
        | String ((Pathname|Device|Mountable|Dev_or_Path|Mountable_or_Path
                   |PlainString|GUID|Filename), n) ->
            pr " %s" n
        | OptString n -> pr " %s" n
        | StringList (_, n) ->
            pr " '%s ...'" n
        | Bool _ -> pr " true|false"
        | Int n -> pr " %s" n
        | Int64 n -> pr " %s" n
        | String ((FileIn|FileOut), n) -> pr " (%s|-)" n
        | BufferIn n -> pr " %s" n
        | String (Key, _) -> () (* keys are entered at a prompt *)
        | Pointer _ -> assert false
      ) args;
      List.iter (
        fun arg -> pr " [%s:%s]" (name_of_optargt arg) (doc_opttype_of arg)
      ) optargs;
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc;

      if List.exists (function String ((FileIn|FileOut), _) -> true
                      | _ -> false) args then
        pr "Use C<-> instead of a filename to read/write from stdin/stdout.\n\n";

      if List.exists (function String (Key, _) -> true | _ -> false) args then
        pr "This command has one or more key or passphrase parameters.
Guestfish will prompt for these separately.\n\n";

      if optargs <> [] then
        pr "This command has one or more optional arguments.  See L</OPTIONAL ARGUMENTS>.\n\n";

      if f.protocol_limit_warning then
        pr "%s\n\n" protocol_limit_warning;

      (match deprecation_notice ~replace_underscores:true f with
      | None -> ()
      | Some txt -> pr "%s\n\n" txt
      );

      (match f.optional with
      | None -> ()
      | Some opt ->
        pr "This command depends on the feature C<%s>.   See also
L</feature-available>.\n\n" opt
      );
  ) (actions |> fish_functions |> documented_functions |> sort)

(* Generate documentation for guestfish-only commands. *)
and generate_fish_commands_pod () =
  generate_header PODStyle GPLv2plus;

  List.iter (
    fun ({ name; longdesc } as f) ->
      let aliases = get_aliases f in
      let name = String.replace_char name '_' '-' in

      List.iter (
        fun name ->
          pr "=head2 %s\n\n" name
      ) (name :: aliases);
      pr "%s\n\n" longdesc;
  ) fish_commands

and generate_fish_prep_options_h () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef PREPOPTS_H\n";
  pr "\n";

  pr "\
struct prep {
  const char *name;             /* eg. \"fs\" */

  size_t nr_params;             /* optional parameters */
  struct prep_param *params;

  const char *shortdesc;        /* short description */
  const char *longdesc;         /* long description */

                                /* functions to implement it */
  void (*prelaunch) (const char *filename, prep_data *);
  void (*postlaunch) (const char *filename, prep_data *, const char *device);
};

struct prep_param {
  const char *pname;            /* parameter name */
  const char *pdefault;         /* parameter default */
  const char *pdesc;            /* parameter description */
};

extern const struct prep preps[];
#define NR_PREPS %d

" (List.length prepopts);

  List.iter (
    fun (name, _, _, _) ->
      pr "\
extern void prep_prelaunch_%s (const char *filename, prep_data *data);
extern void prep_postlaunch_%s (const char *filename, prep_data *data, const char *device);

" name name;
  ) prepopts;

  pr "#endif /* PREPOPTS_H */\n"

and generate_fish_prep_options_c () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>

#include \"fish.h\"
#include \"prepopts.h\"

";

  List.iter (
    fun (name, _, args, _) ->
      pr "static struct prep_param %s_args[] = {\n" name;
      List.iter (
        fun (n, default, desc) ->
          pr "  { \"%s\", \"%s\", \"%s\" },\n" n default desc
      ) args;
      pr "};\n";
      pr "\n";
  ) prepopts;

  pr "const struct prep preps[] = {\n";
  List.iter (
    fun (name, shortdesc, args, longdesc) ->
      let longdesc = pod2text ~discard:true ~trim:true "NAME" longdesc in
      let rec loop = function
        | [] -> []
        | [""] -> []
        | x :: xs -> x :: loop xs
      in
      let longdesc = loop longdesc in
      let rec loop = function
        | [] -> []
        | [x] -> ["  " ^ x]
        | "" :: xs -> "\n" :: loop xs
        | x :: xs -> ("  " ^ x ^ "\n") :: loop xs
      in
      let longdesc = loop longdesc in
      let longdesc = String.concat "" longdesc in

      pr "  { \"%s\", %d, %s_args,
    \"%s\",
    \"%s\",
    prep_prelaunch_%s, prep_postlaunch_%s },
"
        name (List.length args) name
        (c_quote shortdesc) (c_quote longdesc)
        name name;
  ) prepopts;
  pr "};\n"

and generate_fish_prep_options_pod () =
  generate_header PODStyle GPLv2plus;

  List.iter (
    fun (name, shortdesc, args, longdesc) ->
      pr "=head2 B<-N %s> - %s\n" name shortdesc;
      pr "\n";
      pr "C<guestfish -N [I<filename>=]%s" name;
      let rec loop = function
        | [] -> ()
        | (n,_,_) :: args -> pr "[:I<%s>" n; loop args; pr "]";
      in
      loop args;
      pr ">\n";
      pr "\n";
      pr "%s\n\n" longdesc;
      if args <> [] then (
        pr "The optional parameters are:\n\n";
        pr " %-13s %s\n" "Name" "Default value";
        List.iter (
          fun (n, default, desc) ->
            pr " %-13s %-13s %s\n" n default desc
        ) args;
        pr "\n"
      )
  ) prepopts

and generate_fish_event_names () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>

#include \"fish.h\"

int
event_bitmask_of_event_set (const char *arg, uint64_t *eventset_r)
{
  size_t n;

  if (STREQ (arg, \"*\")) {
    *eventset_r = GUESTFS_EVENT_ALL;
    return 0;
  }

  *eventset_r = 0;

  while (*arg) {
    n = strcspn (arg, \",\");

    ";

  List.iter (
    fun (name, _) ->
      pr "if (STREQLEN (arg, \"%s\", n))\n" name;
      pr "      *eventset_r |= GUESTFS_EVENT_%s;\n"
         (String.uppercase_ascii name);
      pr "    else ";
  ) events;

  pr "\
{
      fprintf (stderr, _(\"unknown event name: %%s\\n\"), arg);
      return -1;
    }

    arg += n;
    if (*arg == ',')
      arg++;
  }

  return 0;
}
"

and generate_fish_test_prep_sh () =
  pr "#!/bin/bash -\n";
  generate_header HashStyle GPLv2plus;

  let all_disks = sprintf "prep{1..%d}.img" (List.length prepopts) in

  pr "\
set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f %s

$VG guestfish \\
" all_disks;

  let vg_count = ref 0 in

  List.iteri (
    fun i (name, _, _, _) ->
      let params = [name] in
      let params =
        if String.find name "lv" <> -1 then (
          incr vg_count;
          sprintf "/dev/VG%d/LV" !vg_count :: params
        ) else params in
      let params = List.rev params in
      pr "    -N prep%d.img=%s \\\n" (i + 1) (String.concat ":" params)
  ) prepopts;

  pr "    exit

rm %s
" all_disks
