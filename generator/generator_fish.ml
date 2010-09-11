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
open Generator_prepopts
open Generator_c

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

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "#include \"c-ctype.h\"\n";
  pr "#include \"full-write.h\"\n";
  pr "#include \"xstrtol.h\"\n";
  pr "#include \"fish.h\"\n";
  pr "\n";
  pr "/* Valid suffixes allowed for numbers.  See Gnulib xstrtol function. */\n";
  pr "static const char *xstrtol_suffixes = \"0kKMGTPEZY\";\n";
  pr "\n";

  (* list_commands function, which implements guestfish -h *)
  pr "void list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", _(\"Command\"), _(\"Description\"));\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, flags, _, shortdesc, _) ->
      let name = replace_char name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", _(\"%s\"));\n"
        name shortdesc
  ) all_functions_sorted;
  pr "  printf (\"    %%s\\n\",";
  pr "          _(\"Use -h <cmd> / help <cmd> to show detailed help for a command.\"));\n";
  pr "}\n";
  pr "\n";

  (* display_command function, which implements guestfish -h cmd *)
  pr "int display_command (const char *cmd)\n";
  pr "{\n";
  List.iter (
    fun (name, style, _, flags, _, shortdesc, longdesc) ->
      let name2 = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in
      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
      let synopsis =
        match snd style with
        | [] -> name2
        | args ->
            let args = List.filter (function Key _ -> false | _ -> true) args in
            sprintf "%s %s"
              name2 (String.concat " " (List.map name_of_argt args)) in

      let warnings =
        if List.exists (function Key _ -> true | _ -> false) (snd style) then
          "\n\nThis command has one or more key or passphrase parameters.
Guestfish will prompt for these separately."
        else "" in

      let warnings =
        warnings ^
          if List.mem ProtocolLimitWarning flags then
            ("\n\n" ^ protocol_limit_warning)
          else "" in

      (* For DangerWillRobinson commands, we should probably have
       * guestfish prompt before allowing you to use them (especially
       * in interactive mode). XXX
       *)
      let warnings =
        warnings ^
          if List.mem DangerWillRobinson flags then
            ("\n\n" ^ danger_will_robinson)
          else "" in

      let warnings =
        warnings ^
          match deprecation_notice flags with
          | None -> ""
          | Some txt -> "\n\n" ^ txt in

      let describe_alias =
        if name <> alias then
          sprintf "\n\nYou can use '%s' as an alias for this command." alias
        else "" in

      pr "  if (";
      pr "STRCASEEQ (cmd, \"%s\")" name;
      if name <> name2 then
        pr " || STRCASEEQ (cmd, \"%s\")" name2;
      if name <> alias then
        pr " || STRCASEEQ (cmd, \"%s\")" alias;
      pr ") {\n";
      pr "    pod2text (\"%s\", _(\"%s\"), %S);\n"
        name2 shortdesc
        ("=head1 SYNOPSIS\n\n " ^ synopsis ^ "\n\n" ^
         "=head1 DESCRIPTION\n\n" ^
         longdesc ^ warnings ^ describe_alias);
      pr "    return 0;\n";
      pr "  }\n";
      pr "  else\n"
  ) all_functions;
  pr "    return display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  let emit_print_list_function typ =
    pr "static void print_%s_list (struct guestfs_%s_list *%ss)\n"
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

      pr "static void print_%s_indent (struct guestfs_%s *%s, const char *indent)\n" typ typ typ;
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
            pr "  if (%s->%s >= 0) printf (\"%%s%s: %%g %%%%\\n\", indent, %s->%s);\n"
              typ name name typ name;
            pr "  else printf (\"%%s%s: \\n\", indent);\n" name
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
        pr "static void print_%s (struct guestfs_%s *%s)\n" typ typ typ;
        pr "{\n";
        pr "  print_%s_indent (%s, \"\");\n" typ typ;
        pr "}\n";
        pr "\n";
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* run_<action> actions *)
  List.iter (
    fun (name, style, _, flags, _, _, _) ->
      pr "static int run_%s (const char *cmd, int argc, char *argv[])\n" name;
      pr "{\n";
      (match fst style with
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
      ) (snd style);

      (* Check and convert parameters. *)
      let argc_expected =
        let args_no_keys =
          List.filter (function Key _ -> false | _ -> true) (snd style) in
        List.length args_no_keys in
      pr "  if (argc != %d) {\n" argc_expected;
      pr "    fprintf (stderr, _(\"%%s should have %%d parameter(s)\\n\"), cmd, %d);\n"
        argc_expected;
      pr "    fprintf (stderr, _(\"type 'help %%s' for help on %%s\\n\"), cmd, cmd);\n";
      pr "    return -1;\n";
      pr "  }\n";

      let parse_integer fn fntyp rtyp range name =
        pr "  {\n";
        pr "    strtol_error xerr;\n";
        pr "    %s r;\n" fntyp;
        pr "\n";
        pr "    xerr = %s (argv[i++], NULL, 0, &r, xstrtol_suffixes);\n" fn;
        pr "    if (xerr != LONGINT_OK) {\n";
        pr "      fprintf (stderr,\n";
        pr "               _(\"%%s: %%s: invalid integer parameter (%%s returned %%d)\\n\"),\n";
        pr "               cmd, \"%s\", \"%s\", xerr);\n" name fn;
        pr "      return -1;\n";
        pr "    }\n";
        (match range with
         | None -> ()
         | Some (min, max, comment) ->
             pr "    /* %s */\n" comment;
             pr "    if (r < %s || r > %s) {\n" min max;
             pr "      fprintf (stderr, _(\"%%s: %%s: integer out of range\\n\"), cmd, \"%s\");\n"
               name;
             pr "      return -1;\n";
             pr "    }\n";
             pr "    /* The check above should ensure this assignment does not overflow. */\n";
        );
        pr "    %s = r;\n" name;
        pr "  }\n";
      in

      if snd style <> [] then
        pr "  size_t i = 0;\n";

      List.iter (
        function
        | Device name
        | String name ->
            pr "  %s = argv[i++];\n" name
        | Pathname name
        | Dev_or_Path name ->
            pr "  %s = resolve_win_path (argv[i++]);\n" name;
            pr "  if (%s == NULL) return -1;\n" name
        | OptString name ->
            pr "  %s = STRNEQ (argv[i], \"\") ? argv[i] : NULL;\n" name;
            pr "  i++;\n"
        | BufferIn name ->
            pr "  %s = argv[i];\n" name;
            pr "  %s_size = strlen (argv[i]);\n" name;
            pr "  i++;\n"
        | FileIn name ->
            pr "  %s = file_in (argv[i++]);\n" name;
            pr "  if (%s == NULL) return -1;\n" name
        | FileOut name ->
            pr "  %s = file_out (argv[i++]);\n" name;
            pr "  if (%s == NULL) return -1;\n" name
        | StringList name | DeviceList name ->
            pr "  %s = parse_string_list (argv[i++]);\n" name;
            pr "  if (%s == NULL) return -1;\n" name
        | Key name ->
            pr "  %s = read_key (\"%s\");\n" name name;
            pr "  if (%s == NULL) return -1;\n" name
        | Bool name ->
            pr "  %s = is_true (argv[i++]) ? 1 : 0;\n" name
        | Int name ->
            let range =
              let min = "(-(2LL<<30))"
              and max = "((2LL<<30)-1)"
              and comment =
                "The Int type in the generator is a signed 31 bit int." in
              Some (min, max, comment) in
            parse_integer "xstrtoll" "long long" "int" range name
        | Int64 name ->
            parse_integer "xstrtoll" "long long" "int64_t" None name
      ) (snd style);

      (* Call C API function. *)
      pr "  r = guestfs_%s " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Device _ | String _
        | OptString _ | Bool _
        | Int _ | Int64 _
        | BufferIn _ -> ()
        | Pathname name | Dev_or_Path name | FileOut name
        | Key name ->
            pr "  free (%s);\n" name
        | FileIn name ->
            pr "  free_file_in (%s);\n" name
        | StringList name | DeviceList name ->
            pr "  free_strings (%s);\n" name
      ) (snd style);

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
      (match fst style with
       | RErr -> pr "  return r;\n"
       | RInt _ ->
           pr "  if (r == -1) return -1;\n";
           (match fish_output with
            | None ->
                pr "  printf (\"%%d\\n\", r);\n";
            | Some FishOutputOctal ->
                pr "  printf (\"%%s%%o\\n\", r != 0 ? \"0\" : \"\", r);\n";
            | Some FishOutputHexadecimal ->
                pr "  printf (\"%%s%%x\\n\", r != 0 ? \"0x\" : \"\", r);\n");
           pr "  return 0;\n"
       | RInt64 _ ->
           pr "  if (r == -1) return -1;\n";
           (match fish_output with
            | None ->
                pr "  printf (\"%%\" PRIi64 \"\\n\", r);\n";
            | Some FishOutputOctal ->
                pr "  printf (\"%%s%%\" PRIo64 \"\\n\", r != 0 ? \"0\" : \"\", r);\n";
            | Some FishOutputHexadecimal ->
                pr "  printf (\"%%s%%\" PRIx64 \"\\n\", r != 0 ? \"0x\" : \"\", r);\n");
           pr "  return 0;\n"
       | RBool _ ->
           pr "  if (r == -1) return -1;\n";
           pr "  if (r) printf (\"true\\n\"); else printf (\"false\\n\");\n";
           pr "  return 0;\n"
       | RConstString _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  printf (\"%%s\\n\", r);\n";
           pr "  return 0;\n"
       | RConstOptString _ ->
           pr "  printf (\"%%s\\n\", r ? : \"(null)\");\n";
           pr "  return 0;\n"
       | RString _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  printf (\"%%s\\n\", r);\n";
           pr "  free (r);\n";
           pr "  return 0;\n"
       | RStringList _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_strings (r);\n";
           pr "  free_strings (r);\n";
           pr "  return 0;\n"
       | RStruct (_, typ) ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ;
           pr "  return 0;\n"
       | RStructList (_, typ) ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ;
           pr "  return 0;\n"
       | RHashtable _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_table (r);\n";
           pr "  free_strings (r);\n";
           pr "  return 0;\n"
       | RBufferOut _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  if (full_write (1, r, size) != size) {\n";
           pr "    perror (\"write\");\n";
           pr "    free (r);\n";
           pr "    return -1;\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return 0;\n"
      );
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* run_action function *)
  pr "int run_action (const char *cmd, int argc, char *argv[])\n";
  pr "{\n";
  List.iter (
    fun (name, _, _, flags, _, _, _) ->
      let name2 = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in
      pr "  if (";
      pr "STRCASEEQ (cmd, \"%s\")" name;
      if name <> name2 then
        pr " || STRCASEEQ (cmd, \"%s\")" name2;
      if name <> alias then
        pr " || STRCASEEQ (cmd, \"%s\")" alias;
      pr ")\n";
      pr "    return run_%s (cmd, argc, argv);\n" name;
      pr "  else\n";
  ) all_functions;
  pr "    {\n";
  pr "      fprintf (stderr, _(\"%%s: unknown command\\n\"), cmd);\n";
  pr "      if (command_num == 1)\n";
  pr "        extended_help_message ();\n";
  pr "      return -1;\n";
  pr "    }\n";
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

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
        let alias =
          try find_map (function FishAlias n -> Some n | _ -> None) flags
          with Not_found -> name in

        if name <> alias then [name2; alias] else [name2]
    ) all_functions in
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
    fun (name, style, _, flags, _, _, longdesc) ->
      let longdesc =
        Str.global_substitute rex (
          fun s ->
            let sub =
              try Str.matched_group 1 s
              with Not_found ->
                failwithf "error substituting C<guestfs_...> in longdesc of function %s" name in
            "C<" ^ replace_char sub '_' '-' ^ ">"
        ) longdesc in
      let name = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in

      pr "=head2 %s" name;
      if name <> alias then
        pr " | %s" alias;
      pr "\n";
      pr "\n";
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
      ) (snd style);
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc;

      if List.exists (function FileIn _ | FileOut _ -> true
                      | _ -> false) (snd style) then
        pr "Use C<-> instead of a filename to read/write from stdin/stdout.\n\n";

      if List.exists (function Key _ -> true | _ -> false) (snd style) then
        pr "This command has one or more key or passphrase parameters.
Guestfish will prompt for these separately.\n\n";

      if List.mem ProtocolLimitWarning flags then
        pr "%s\n\n" protocol_limit_warning;

      if List.mem DangerWillRobinson flags then
        pr "%s\n\n" danger_will_robinson;

      match deprecation_notice flags with
      | None -> ()
      | Some txt -> pr "%s\n\n" txt
  ) all_functions_sorted

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
