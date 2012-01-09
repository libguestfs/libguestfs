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

(* Generate daemon/actions.h. *)
let generate_daemon_actions_h () =
  generate_header CStyle GPLv2plus;

  pr "#include \"guestfs_protocol.h\"\n";
  pr "\n";

  List.iter (
    function
    | shortname, (_, _, (_::_ as optargs)), _, _, _, _, _ ->
        iteri (
          fun i arg ->
            let uc_shortname = String.uppercase shortname in
            let n = name_of_optargt arg in
            let uc_n = String.uppercase n in
            pr "#define GUESTFS_%s_%s_BITMASK (UINT64_C(1)<<%d)\n"
              uc_shortname uc_n i
        ) optargs
    | _ -> ()
  ) daemon_functions;

  List.iter (
    fun (name, (ret, args, optargs), _, _, _, _, _) ->
      let style = ret, args @ args_of_optargs optargs, [] in
      generate_prototype
        ~single_line:true ~newline:true ~in_daemon:true ~prefix:"do_"
        name style;
  ) daemon_functions

(* Generate the server-side stubs. *)
and generate_daemon_actions () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <rpc/types.h>\n";
  pr "#include <rpc/xdr.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"c-ctype.h\"\n";
  pr "#include \"guestfs_protocol.h\"\n";
  pr "#include \"actions.h\"\n";
  pr "\n";

  List.iter (
    fun (name, (ret, args, optargs), _, _, _, _, _) ->
      (* Generate server-side stubs. *)
      pr "static void %s_stub (XDR *xdr_in)\n" name;
      pr "{\n";
      (match ret with
       | RErr | RInt _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RBool _ -> pr "  int r;\n"
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RStruct (_, typ) -> pr "  guestfs_int_%s *r;\n" typ
       | RStructList (_, typ) -> pr "  guestfs_int_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  size_t size = 1;\n";
           pr "  char *r;\n"
      );

      if args <> [] || optargs <> [] then (
        pr "  struct guestfs_%s_args args;\n" name;
        List.iter (
          function
          | Device n | Dev_or_Path n
          | Pathname n
          | String n
          | Key n -> ()
          | OptString n -> pr "  char *%s;\n" n
          | StringList n | DeviceList n -> pr "  char **%s;\n" n
          | Bool n -> pr "  int %s;\n" n
          | Int n -> pr "  int %s;\n" n
          | Int64 n -> pr "  int64_t %s;\n" n
          | FileIn _ | FileOut _ -> ()
          | BufferIn n ->
              pr "  const char *%s;\n" n;
              pr "  size_t %s_size;\n" n
          | Pointer _ -> assert false
        ) (args @ args_of_optargs optargs)
      );
      pr "\n";

      let is_filein =
        List.exists (function FileIn _ -> true | _ -> false) args in

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
        pr "    goto done;\n";
        pr "  }\n";
      ) else (
        pr "  if (optargs_bitmask != 0) {\n";
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_error (\"header optargs_bitmask field must be passed as 0 for calls that don't take optional arguments\");\n";
        pr "    goto done;\n";
        pr "  }\n";
      );
      pr "\n";

      (* Decode arguments. *)
      if args <> [] || optargs <> [] then (
        pr "  memset (&args, 0, sizeof args);\n";
        pr "\n";
        pr "  if (!xdr_guestfs_%s_args (xdr_in, &args)) {\n" name;
        if is_filein then
          pr "    cancel_receive ();\n";
        pr "    reply_with_error (\"daemon failed to decode procedure arguments\");\n";
        pr "    goto done;\n";
        pr "  }\n";
        let pr_args n =
          pr "  char *%s = args.%s;\n" n n
        in
        let pr_list_handling_code n =
          pr "  %s = realloc (args.%s.%s_val,\n" n n n;
          pr "                sizeof (char *) * (args.%s.%s_len+1));\n" n n;
          pr "  if (%s == NULL) {\n" n;
          if is_filein then
            pr "    cancel_receive ();\n";
          pr "    reply_with_perror (\"realloc\");\n";
          pr "    goto done;\n";
          pr "  }\n";
          pr "  %s[args.%s.%s_len] = NULL;\n" n n n;
          pr "  args.%s.%s_val = %s;\n" n n n;
        in
        List.iter (
          function
          | Pathname n ->
              pr_args n;
              pr "  ABS_PATH (%s, %s, goto done);\n"
                n (if is_filein then "cancel_receive ()" else "");
          | Device n ->
              pr_args n;
              pr "  RESOLVE_DEVICE (%s, %s, goto done);\n"
                n (if is_filein then "cancel_receive ()" else "");
          | Dev_or_Path n ->
              pr_args n;
              pr "  REQUIRE_ROOT_OR_RESOLVE_DEVICE (%s, %s, goto done);\n"
                n (if is_filein then "cancel_receive ()" else "");
          | String n | Key n -> pr_args n
          | OptString n -> pr "  %s = args.%s ? *args.%s : NULL;\n" n n n
          | StringList n ->
              pr_list_handling_code n;
          | DeviceList n ->
              pr_list_handling_code n;
              pr "  /* Ensure that each is a device,\n";
              pr "   * and perform device name translation.\n";
              pr "   */\n";
              pr "  {\n";
              pr "    size_t i;\n";
              pr "    for (i = 0; %s[i] != NULL; ++i)\n" n;
              pr "      RESOLVE_DEVICE (%s[i], %s, goto done);\n" n
                (if is_filein then "cancel_receive ()" else "");
              pr "  }\n";
          | Bool n -> pr "  %s = args.%s;\n" n n
          | Int n -> pr "  %s = args.%s;\n" n n
          | Int64 n -> pr "  %s = args.%s;\n" n n
          | FileIn _ | FileOut _ -> ()
          | BufferIn n ->
              pr "  %s = args.%s.%s_val;\n" n n n;
              pr "  %s_size = args.%s.%s_len;\n" n n n
          | Pointer _ -> assert false
        ) (args @ args_of_optargs optargs);
        pr "\n"
      );

      (* this is used at least for do_equal *)
      if List.exists (function Pathname _ -> true | _ -> false) args then (
        (* Emit NEED_ROOT just once, even when there are two or
           more Pathname args *)
        pr "  NEED_ROOT (%s, goto done);\n"
          (if is_filein then "cancel_receive ()" else "");
      );

      (* Don't want to call the impl with any FileIn or FileOut
       * parameters, since these go "outside" the RPC protocol.
       *)
      let () =
        let args' =
          List.filter
            (function FileIn _ | FileOut _ -> false | _ -> true) args in
        let style = ret, args' @ args_of_optargs optargs, [] in
        pr "  r = do_%s " name;
        generate_c_call_args style;
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
           pr "    goto done;\n";
           pr "\n"
       | RBufferOut _ ->
           pr "  /* size == 0 && r == NULL could be a non-error case (just\n";
           pr "   * an ordinary zero-length buffer), so be careful ...\n";
           pr "   */\n";
           pr "  if (size == 1 && r == NULL)\n";
           pr "    /* do_%s has already called reply_with_error */\n" name;
           pr "    goto done;\n";
           pr "\n"
      );

      (* If there are any FileOut parameters, then the impl must
       * send its own reply.
       *)
      let no_reply =
        List.exists (function FileOut _ -> true | _ -> false) args in
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
        | RString n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = r;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free (r);\n"
        | RStringList n | RHashtable n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_len = count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free_strings (r);\n"
        | RStruct (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  free (r);\n";
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStructList (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  free (r);\n";
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RBufferOut n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  ret.%s.%s_len = size;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free (r);\n"
      );

      (* Free the args. *)
      pr "done:\n";
      (match args with
       | [] -> ()
       | _ ->
           pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_args, (char *) &args);\n"
             name
      );
      pr "  return;\n";
      pr "}\n\n";
  ) daemon_functions;

  (* Dispatch function. *)
  pr "void dispatch_incoming_message (XDR *xdr_in)\n";
  pr "{\n";
  pr "  switch (proc_nr) {\n";

  List.iter (
    fun (name, _, _, _, _, _, _) ->
      pr "    case GUESTFS_PROC_%s:\n" (String.uppercase name);
      pr "      %s_stub (xdr_in);\n" name;
      pr "      break;\n"
  ) daemon_functions;

  pr "    default:\n";
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d, set LIBGUESTFS_PATH to point to the matching libguestfs appliance directory\", proc_nr);\n";
  pr "  }\n";
  pr "}\n";
  pr "\n";

  (* LVM columns and tokenization functions. *)
  (* XXX This generates crap code.  We should rethink how we
   * do this parsing.
   *)
  List.iter (
    function
    | typ, cols ->
        pr "static const char *lvm_%s_cols = \"%s\";\n"
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
            pr "  p = strchrnul (tok, ',');\n";
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
                 pr "  if (sscanf (tok, \"%%\"SCNu64, &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FInt64 ->
                 pr "  if (sscanf (tok, \"%%\"SCNi64, &r->%s) != 1) {\n" name;
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
        pr "	       \"--nosuffix\", \"--separator\", \",\", \"--units\", \"b\", NULL);\n";
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
and generate_daemon_names () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "\n";

  pr "/* This array is indexed by proc_nr.  See guestfs_protocol.x. */\n";
  pr "const char *function_names[] = {\n";
  List.iter (
    fun (name, _, proc_nr, _, _, _, _) -> pr "  [%d] = \"%s\",\n" proc_nr name
  ) daemon_functions;
  pr "};\n";

(* Generate the optional groups for the daemon to implement
 * guestfs_available.
 *)
and generate_daemon_optgroups_c () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"optgroups.h\"\n";
  pr "\n";

  pr "struct optgroup optgroups[] = {\n";
  List.iter (
    fun (group, _) ->
      pr "  { \"%s\", optgroup_%s_available },\n" group group
  ) optgroups;
  pr "  { NULL, NULL }\n";
  pr "};\n"

and generate_daemon_optgroups_h () =
  generate_header CStyle GPLv2plus;

  List.iter (
    fun (group, _) ->
      pr "extern int optgroup_%s_available (void);\n" group
  ) optgroups
