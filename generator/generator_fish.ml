(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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
open Generator_prepopts
open Generator_c
open Generator_events

let doc_opttype_of = function
  | OBool n -> "true|false"
  | OInt n
  | OInt64 n -> "N"
  | OString n -> ".."

(* Generate a lot of different functions for guestfish. *)
let generate_fish_cmds () =
  generate_header CStyle GPLv2plus;

  let all_functions =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions in
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  let all_functions_and_fish_commands_sorted =
    List.sort action_compare (all_functions_sorted @ fish_commands) in

  pr "#include <config.h>\n";
  pr "\n";
  pr "/* It is safe to call deprecated functions from this file. */\n";
  pr "#undef GUESTFS_WARN_DEPRECATED\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <libintl.h>\n";
  pr "\n";
  pr "#include \"c-ctype.h\"\n";
  pr "#include \"full-write.h\"\n";
  pr "#include \"xstrtol.h\"\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "#include \"fish.h\"\n";
  pr "#include \"fish-cmds.h\"\n";
  pr "#include \"options.h\"\n";
  pr "#include \"cmds-gperf.h\"\n";
  pr "\n";
  pr "/* Valid suffixes allowed for numbers.  See Gnulib xstrtol function. */\n";
  pr "static const char *xstrtol_suffixes = \"0kKMGTPEZY\";\n";
  pr "\n";

  List.iter (
    fun (name, _, _, _, _, _, _) ->
      pr "static int run_%s (const char *cmd, size_t argc, char *argv[]);\n"
        name
  ) all_functions;

  pr "\n";

  (* List of command_entry structs. *)
  List.iter (
    fun (name, _, _, flags, _, shortdesc, longdesc) ->
      let name2 = replace_char name '_' '-' in
      let aliases =
        filter_map (function FishAlias n -> Some n | _ -> None) flags in
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
      pr "  .help = \"%s\",\n" (c_quote text);
      pr "  .run = run_%s\n" name;
      pr "};\n";
      pr "\n";
  ) fish_commands;

  List.iter (
    fun (name, (_, args, optargs), _, flags, _, shortdesc, longdesc) ->
      let name2 = replace_char name '_' '-' in
      let aliases =
        filter_map (function FishAlias n -> Some n | _ -> None) flags in

      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
      let synopsis =
        match args with
        | [] -> name2
        | args ->
            let args = List.filter (function Key _ -> false | _ -> true) args in
            sprintf "%s%s%s"
              name2
              (String.concat ""
                 (List.map (fun arg -> " " ^ name_of_argt arg) args))
              (String.concat ""
                 (List.map (fun arg ->
                   sprintf " [%s:%s]" (name_of_optargt arg) (doc_opttype_of arg)
                  ) optargs)) in

      let warnings =
        if List.exists (function Key _ -> true | _ -> false) args then
          "\n\nThis command has one or more key or passphrase parameters.
Guestfish will prompt for these separately."
        else "" in

      let warnings =
        warnings ^
          if List.mem ProtocolLimitWarning flags then
            ("\n\n" ^ protocol_limit_warning)
          else "" in

      let warnings =
        warnings ^
          match deprecation_notice ~replace_underscores:true flags with
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
      pr "  .help = \"%s\",\n" (c_quote text);
      pr "  .run = run_%s\n" name;
      pr "};\n";
      pr "\n";
  ) all_functions;

  (* list_commands function, which implements guestfish -h *)
  pr "void\n";
  pr "list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", _(\"Command\"), _(\"Description\"));\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, flags, _, shortdesc, _) ->
      let name = replace_char name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", _(\"%s\"));\n"
        name shortdesc
  ) all_functions_and_fish_commands_sorted;
  pr "  printf (\"    %%s\\n\",";
  pr "          _(\"Use -h <cmd> / help <cmd> to show detailed help for a command.\"));\n";
  pr "}\n";
  pr "\n";

  (* display_command function, which implements guestfish -h cmd *)
  pr "int\n";
  pr "display_command (const char *cmd)\n";
  pr "{\n";
  pr "  const struct command_table *ct;\n";
  pr "\n";
  pr "  ct = lookup_fish_command (cmd, strlen (cmd));\n";
  pr "  if (ct) {\n";
  pr "    fputs (ct->entry->help, stdout);\n";
  pr "    return 0;\n";
  pr "  }\n";
  pr "  else\n";
  pr "    return display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  let emit_print_list_function typ =
    pr "static void\n";
    pr "print_%s_list (struct guestfs_%s_list *%ss)\n"
      typ typ typ;
    pr "{\n";
    pr "  unsigned int i;\n";
    pr "\n";
    pr "  for (i = 0; i < %ss->len; ++i) {\n" typ;
    pr "    printf (\"[%%d] = {\\n\", i);\n";
    pr "    print_%s_indent (&%ss->val[i], \"  \");\n" typ typ;
    pr "    printf (\"}\\n\");\n";
    pr "  }\n";
    pr "}\n";
    pr "\n";
  in

  (* print_* functions *)
  List.iter (
    fun (typ, cols) ->
      let needs_i =
        List.exists (function (_, (FUUID|FBuffer)) -> true | _ -> false) cols in

      pr "static void\n";
      pr "print_%s_indent (struct guestfs_%s *%s, const char *indent)\n" typ typ typ;
      pr "{\n";
      if needs_i then (
        pr "  unsigned int i;\n";
        pr "\n"
      );
      List.iter (
        function
        | name, FString ->
            pr "  printf (\"%%s%s: %%s\\n\", indent, %s->%s);\n" name typ name
        | name, FUUID ->
            pr "  printf (\"%%s%s: \", indent);\n" name;
            pr "  for (i = 0; i < 32; ++i)\n";
            pr "    printf (\"%%c\", %s->%s[i]);\n" typ name;
            pr "  printf (\"\\n\");\n"
        | name, FBuffer ->
            pr "  printf (\"%%s%s: \", indent);\n" name;
            pr "  for (i = 0; i < %s->%s_len; ++i)\n" typ name;
            pr "    if (c_isprint (%s->%s[i]))\n" typ name;
            pr "      printf (\"%%c\", %s->%s[i]);\n" typ name;
            pr "    else\n";
            pr "      printf (\"\\\\x%%02x\", %s->%s[i]);\n" typ name;
            pr "  printf (\"\\n\");\n"
        | name, (FUInt64|FBytes) ->
            pr "  printf (\"%%s%s: %%\" PRIu64 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FInt64 ->
            pr "  printf (\"%%s%s: %%\" PRIi64 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FUInt32 ->
            pr "  printf (\"%%s%s: %%\" PRIu32 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FInt32 ->
            pr "  printf (\"%%s%s: %%\" PRIi32 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FChar ->
            pr "  printf (\"%%s%s: %%c\\n\", indent, %s->%s);\n"
              name typ name
        | name, FOptPercent ->
            pr "  if (%s->%s >= 0)\n" typ name;
            pr "    printf (\"%%s%s: %%g %%%%\\n\", indent, (double) %s->%s);\n"
              name typ name;
            pr "  else\n";
            pr "    printf (\"%%s%s: \\n\", indent);\n" name
      ) cols;
      pr "}\n";
      pr "\n";
  ) structs;

  (* Emit a print_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_print_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* Emit a print_TYPE function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructOnly | RStructAndList) ->
        pr "static void\n";
        pr "print_%s (struct guestfs_%s *%s)\n" typ typ typ;
        pr "{\n";
        pr "  print_%s_indent (%s, \"\");\n" typ typ;
        pr "}\n";
        pr "\n";
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* run_<action> actions *)
  List.iter (
    fun (name, (ret, args, optargs as style), _, flags, _, _, _) ->
      pr "static int\n";
      pr "run_%s (const char *cmd, size_t argc, char *argv[])\n" name;
      pr "{\n";
      pr "  int ret = -1;\n";
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
        | Device n
        | String n
        | OptString n -> pr "  const char *%s;\n" n
        | Pathname n
        | Dev_or_Path n
        | FileIn n
        | FileOut n
        | Key n -> pr "  char *%s;\n" n
        | BufferIn n ->
            pr "  const char *%s;\n" n;
            pr "  size_t %s_size;\n" n
        | StringList n | DeviceList n -> pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  int64_t %s;\n" n
        | Pointer _ -> assert false
      ) args;

      if optargs <> [] then (
        pr "  struct guestfs_%s_argv optargs_s = { .bitmask = 0 };\n" name;
        pr "  struct guestfs_%s_argv *optargs = &optargs_s;\n" name
      );

      if args <> [] || optargs <> [] then
        pr "  size_t i = 0;\n";

      pr "\n";

      (* Check and convert parameters. *)
      let argc_minimum, argc_maximum =
        let args_no_keys =
          List.filter (function Key _ -> false | _ -> true) args in
        let argc_minimum = List.length args_no_keys in
        let argc_maximum = argc_minimum + List.length optargs in
        argc_minimum, argc_maximum in

      if argc_minimum = argc_maximum then (
        pr "  if (argc != %d) {\n" argc_minimum;
        pr "    fprintf (stderr, _(\"%%s should have %%d parameter(s)\\n\"), cmd, %d);\n"
          argc_minimum;
      ) else if argc_minimum = 0 then (
        pr "  if (argc > %d) {\n" argc_maximum;
        pr "    fprintf (stderr, _(\"%%s should have %%d-%%d parameter(s)\\n\"), cmd, %d, %d);\n"
          argc_minimum argc_maximum;
      ) else (
        pr "  if (argc < %d || argc > %d) {\n" argc_minimum argc_maximum;
        pr "    fprintf (stderr, _(\"%%s should have %%d-%%d parameter(s)\\n\"), cmd, %d, %d);\n"
          argc_minimum argc_maximum;
      );
      pr "    fprintf (stderr, _(\"type 'help %%s' for help on %%s\\n\"), cmd, cmd);\n";
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
        pr "%s             _(\"%%s: %%s: invalid integer parameter (%%s returned %%d)\\n\"),\n" indent;
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
        | Device name
        | String name ->
            pr "  %s = argv[i++];\n" name
        | Pathname name
        | Dev_or_Path name ->
            pr "  %s = win_prefix (argv[i++]); /* process \"win:\" prefix */\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | OptString name ->
            pr "  %s = STRNEQ (argv[i], \"\") ? argv[i] : NULL;\n" name;
            pr "  i++;\n"
        | BufferIn name ->
            pr "  %s = argv[i];\n" name;
            pr "  %s_size = strlen (argv[i]);\n" name;
            pr "  i++;\n"
        | FileIn name ->
            pr "  %s = file_in (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | FileOut name ->
            pr "  %s = file_out (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | StringList name | DeviceList name ->
            pr "  %s = parse_string_list (argv[i++]);\n" name;
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | Key name ->
            pr "  %s = read_key (\"%s\");\n" name name;
            pr "  if (keys_from_stdin)\n";
            pr "    input_lineno++;\n";
            pr "  if (%s == NULL) goto out_%s;\n" name name
        | Bool name ->
            pr "  %s = is_true (argv[i++]) ? 1 : 0;\n" name
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
        let uc_name = String.uppercase name in
        pr "\n";
        pr "  for (; i < argc; ++i) {\n";
        pr "    uint64_t this_mask;\n";
        pr "    const char *this_arg;\n";
        pr "\n";
        pr "    ";
        List.iter (
          fun argt ->
            let n = name_of_optargt argt in
            let uc_n = String.uppercase n in
            let len = String.length n in
            pr "if (STRPREFIX (argv[i], \"%s:\")) {\n" n;
            (match argt with
             | OBool n ->
                 pr "      optargs_s.%s = is_true (&argv[i][%d]) ? 1 : 0;\n"
                   n (len+1);
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
            );
            pr "      this_mask = GUESTFS_%s_%s_BITMASK;\n" uc_name uc_n;
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
        pr "      fprintf (stderr, _(\"%%s: optional argument \\\"%%s\\\" given twice\\n\"),\n";
        pr "               cmd, this_arg);\n";
        pr "      goto out;\n";
        pr "    }\n";
        pr "    optargs_s.bitmask |= this_mask;\n";
        pr "  }\n";
        pr "\n";
      );

      (* Call C API function. *)
      if optargs = [] then
        pr "  r = guestfs_%s " name
      else
        pr "  r = guestfs_%s_argv " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Any output flags? *)
      let fish_output =
        let flags = filter_map (
          function FishOutput flag -> Some flag | _ -> None
        ) flags in
        match flags with
        | [] -> None
        | [f] -> Some f
        | _ ->
            failwithf "%s: more than one FishOutput flag is not allowed" name in

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
                pr "  printf (\"%%s%%o\\n\", r != 0 ? \"0\" : \"\", r);\n";
            | Some FishOutputHexadecimal ->
                pr "  printf (\"%%s%%x\\n\", r != 0 ? \"0x\" : \"\", r);\n"
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
                pr "  printf (\"%%s%%\" PRIx64 \"\\n\", r != 0 ? \"0x\" : \"\", r);\n"
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
           pr "  free_strings (r);\n"
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
           pr "  free_strings (r);\n"
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
        | Device _ | String _
        | OptString _ | Bool _
        | BufferIn _ -> ()
        | Int name | Int64 name ->
            pr " out_%s:\n" name
        | Pathname name | Dev_or_Path name | FileOut name
        | Key name ->
            pr "  free (%s);\n" name;
            pr " out_%s:\n" name
        | FileIn name ->
            pr "  free_file_in (%s);\n" name;
            pr " out_%s:\n" name
        | StringList name | DeviceList name ->
            pr "  free_strings (%s);\n" name;
            pr " out_%s:\n" name
        | Pointer _ -> assert false
      ) (List.rev args);

      (* Return. *)
      pr " out_noargs:\n";
      pr "  return ret;\n";
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* run_action function *)
  pr "int\n";
  pr "run_action (const char *cmd, size_t argc, char *argv[])\n";
  pr "{\n";
  pr "  const struct command_table *ct;\n";
  pr "\n";
  pr "  ct = lookup_fish_command (cmd, strlen (cmd));\n";
  pr "  if (ct)\n";
  pr "    return ct->entry->run (cmd, argc, argv);\n";
  pr "  else {\n";
  pr "    fprintf (stderr, _(\"%%s: unknown command\\n\"), cmd);\n";
  pr "    if (command_num == 1)\n";
  pr "      extended_help_message ();\n";
  pr "    return -1;\n";
  pr "  }\n";
  pr "}\n"

and generate_fish_cmds_h () =
  generate_header CStyle GPLv2plus;

  pr "#ifndef FISH_CMDS_H\n";
  pr "#define FISH_CMDS_H\n";
  pr "\n";

  List.iter (
    fun (shortname, _, _, _, _, _, _) ->
      pr "extern int run_%s (const char *cmd, size_t argc, char *argv[]);\n"
        shortname
  ) fish_commands;

  pr "\n";
  pr "#endif /* FISH_CMDS_H */\n"

(* gperf code to do fast lookups of commands. *)
and generate_fish_cmds_gperf () =
  generate_header CStyle GPLv2plus;

  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  let all_functions_and_fish_commands_sorted =
    List.sort action_compare (all_functions_sorted @ fish_commands) in

  pr "\
%%language=ANSI-C
%%define lookup-function-name lookup_fish_command
%%ignore-case
%%readonly-tables
%%null-strings

%%{

#include <config.h>

#include <stdlib.h>
#include <string.h>

#include \"cmds-gperf.h\"

";

  List.iter (
    fun (name, _, _, _, _, _, _) ->
      pr "extern struct command_entry %s_cmd_entry;\n" name
  ) all_functions_and_fish_commands_sorted;

  pr "\
%%}

struct command_table;

%%%%
";

  List.iter (
    fun (name, _, _, flags, _, _, _) ->
      let name2 = replace_char name '_' '-' in
      let aliases =
        filter_map (function FishAlias n -> Some n | _ -> None) flags in

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
  ) all_functions_and_fish_commands_sorted

(* Readline completion for guestfish. *)
and generate_fish_completion () =
  generate_header CStyle GPLv2plus;

  let all_functions =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions in

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
      fun (name, _, _, flags, _, _, _) ->
        let name2 = replace_char name '_' '-' in
        let aliases =
          filter_map (function FishAlias n -> Some n | _ -> None) flags in
        name2 :: aliases
    ) (all_functions @ fish_commands) in
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
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) ->
        not (List.mem NotInFish flags || List.mem NotInDocs flags)
    ) all_functions_sorted in

  let rex = Str.regexp "C<guestfs_\\([^>]+\\)>" in

  List.iter (
    fun (name, (_, args, optargs), _, flags, _, _, longdesc) ->
      let longdesc =
        Str.global_substitute rex (
          fun s ->
            let sub =
              try Str.matched_group 1 s
              with Not_found ->
                failwithf "error substituting C<guestfs_...> in longdesc of function %s" name in
            "L</" ^ replace_char sub '_' '-' ^ ">"
        ) longdesc in
      let name = replace_char name '_' '-' in
      let aliases =
        filter_map (function FishAlias n -> Some n | _ -> None) flags in

      List.iter (
        fun name ->
          pr "=head2 %s\n\n" name
      ) (name :: aliases);
      pr " %s" name;
      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n ->
            pr " %s" n
        | OptString n -> pr " %s" n
        | StringList n | DeviceList n -> pr " '%s ...'" n
        | Bool _ -> pr " true|false"
        | Int n -> pr " %s" n
        | Int64 n -> pr " %s" n
        | FileIn n | FileOut n -> pr " (%s|-)" n
        | BufferIn n -> pr " %s" n
        | Key _ -> () (* keys are entered at a prompt *)
        | Pointer _ -> assert false
      ) args;
      List.iter (
        function
        | (OBool n | OInt n | OInt64 n | OString n) as arg ->
          pr " [%s:%s]" n (doc_opttype_of arg)
      ) optargs;
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc;

      if List.exists (function FileIn _ | FileOut _ -> true
                      | _ -> false) args then
        pr "Use C<-> instead of a filename to read/write from stdin/stdout.\n\n";

      if List.exists (function Key _ -> true | _ -> false) args then
        pr "This command has one or more key or passphrase parameters.
Guestfish will prompt for these separately.\n\n";

      if optargs <> [] then
        pr "This command has one or more optional arguments.  See L</OPTIONAL ARGUMENTS>.\n\n";

      if List.mem ProtocolLimitWarning flags then
        pr "%s\n\n" protocol_limit_warning;

      match deprecation_notice ~replace_underscores:true flags with
      | None -> ()
      | Some txt -> pr "%s\n\n" txt
  ) all_functions_sorted

(* Generate documentation for guestfish-only commands. *)
and generate_fish_commands_pod () =
  List.iter (
    fun (name, _, _, flags, _, _, longdesc) ->
      let name = replace_char name '_' '-' in
      let aliases =
        filter_map (function FishAlias n -> Some n | _ -> None) flags in

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
    fun (name, shortdesc, args, longdesc) ->
      pr "\
extern void prep_prelaunch_%s (const char *filename, prep_data *data);
extern void prep_postlaunch_%s (const char *filename, prep_data *data, const char *device);

" name name;
  ) prepopts;

  pr "\n";
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
    fun (name, shortdesc, args, longdesc) ->
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

and generate_fish_event_names () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>

#include \"fish.h\"

const char *
event_name_of_event_bitmask (uint64_t ev)
{
  switch (ev) {
";

  List.iter (
    fun (name, _) ->
      pr "  case GUESTFS_EVENT_%s:\n" (String.uppercase name);
      pr "    return \"%s\";\n" name
  ) events;

  pr "  default:
    abort (); /* should not happen */
  }
}

void
print_event_set (uint64_t event_bitmask, FILE *fp)
{
  int comma = 0;

  if (event_bitmask == GUESTFS_EVENT_ALL) {
    fputs (\"*\", fp);
    return;
  }

";

  iteri (
    fun i (name, _) ->
      pr "  if (event_bitmask & GUESTFS_EVENT_%s) {\n" (String.uppercase name);
      if i > 0 then
        pr "    if (comma) fputc (',', fp);\n";
      pr "    comma = 1;\n";
      pr "    fputs (\"%s\", fp);\n" name;
      pr "  }\n"
  ) events;

  pr "\
}

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
      pr "      *eventset_r |= GUESTFS_EVENT_%s;\n" (String.uppercase name);
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
