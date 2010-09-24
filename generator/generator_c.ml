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

(* Generate C API. *)

(* Generate a C function prototype. *)
let rec generate_prototype ?(extern = true) ?(static = false)
    ?(semicolon = true)
    ?(single_line = false) ?(newline = false) ?(in_daemon = false)
    ?(prefix = "")
    ?handle name style =
  if extern then pr "extern ";
  if static then pr "static ";
  (match fst style with
   | RErr -> pr "int "
   | RInt _ -> pr "int "
   | RInt64 _ -> pr "int64_t "
   | RBool _ -> pr "int "
   | RConstString _ | RConstOptString _ -> pr "const char *"
   | RString _ | RBufferOut _ -> pr "char *"
   | RStringList _ | RHashtable _ -> pr "char **"
   | RStruct (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s *" typ
       else pr "guestfs_int_%s *" typ
   | RStructList (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s_list *" typ
       else pr "guestfs_int_%s_list *" typ
  );
  let is_RBufferOut = match fst style with RBufferOut _ -> true | _ -> false in
  pr "%s%s (" prefix name;
  if handle = None && List.length (snd style) = 0 && not is_RBufferOut then
    pr "void"
  else (
    let comma = ref false in
    (match handle with
     | None -> ()
     | Some handle -> pr "guestfs_h *%s" handle; comma := true
    );
    let next () =
      if !comma then (
        if single_line then pr ", " else pr ",\n\t\t"
      );
      comma := true
    in
    List.iter (
      function
      | Pathname n
      | Device n | Dev_or_Path n
      | String n
      | OptString n
      | Key n ->
          next ();
          pr "const char *%s" n
      | StringList n | DeviceList n ->
          next ();
          pr "char *const *%s" n
      | Bool n -> next (); pr "int %s" n
      | Int n -> next (); pr "int %s" n
      | Int64 n -> next (); pr "int64_t %s" n
      | FileIn n
      | FileOut n ->
          if not in_daemon then (next (); pr "const char *%s" n)
      | BufferIn n ->
          next ();
          pr "const char *%s" n;
          next ();
          pr "size_t %s_size" n
    ) (snd style);
    if is_RBufferOut then (next (); pr "size_t *size_r");
  );
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_c_call_args ?handle ?(decl = false) style =
  pr "(";
  let comma = ref false in
  let next () =
    if !comma then pr ", ";
    comma := true
  in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  List.iter (
    function
    | BufferIn n ->
        next ();
        pr "%s, %s_size" n n
    | arg ->
        next ();
        pr "%s" (name_of_argt arg)
  ) (snd style);
  (* For RBufferOut calls, add implicit &size parameter. *)
  if not decl then (
    match fst style with
    | RBufferOut _ ->
        next ();
        pr "&size"
    | _ -> ()
  );
  pr ")"

(* Generate the pod documentation for the C API. *)
and generate_actions_pod () =
  List.iter (
    fun (shortname, style, _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let name = "guestfs_" ^ shortname in
        pr "=head2 %s\n\n" name;
        pr " ";
        generate_prototype ~extern:false ~handle:"g" name style;
        pr "\n\n";
        pr "%s\n\n" longdesc;
        (match fst style with
         | RErr ->
             pr "This function returns 0 on success or -1 on error.\n\n"
         | RInt _ ->
             pr "On error this function returns -1.\n\n"
         | RInt64 _ ->
             pr "On error this function returns -1.\n\n"
         | RBool _ ->
             pr "This function returns a C truth value on success or -1 on error.\n\n"
         | RConstString _ ->
             pr "This function returns a string, or NULL on error.
The string is owned by the guest handle and must I<not> be freed.\n\n"
         | RConstOptString _ ->
             pr "This function returns a string which may be NULL.
There is no way to return an error from this function.
The string is owned by the guest handle and must I<not> be freed.\n\n"
         | RString _ ->
             pr "This function returns a string, or NULL on error.
I<The caller must free the returned string after use>.\n\n"
         | RStringList _ ->
             pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
         | RStruct (_, typ) ->
             pr "This function returns a C<struct guestfs_%s *>,
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s> after use>.\n\n" typ typ
         | RStructList (_, typ) ->
             pr "This function returns a C<struct guestfs_%s_list *>
(see E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s_list> after use>.\n\n" typ typ
         | RHashtable _ ->
             pr "This function returns a NULL-terminated array of
strings, or NULL if there was an error.
The array of strings will always have length C<2n+1>, where
C<n> keys and values alternate, followed by the trailing NULL entry.
I<The caller must free the strings and the array after use>.\n\n"
         | RBufferOut _ ->
             pr "This function returns a buffer, or NULL on error.
The size of the returned buffer is written to C<*size_r>.
I<The caller must free the returned buffer after use>.\n\n"
        );
        if List.mem Progress flags then
          pr "%s\n\n" progress_message;
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        if List.mem DangerWillRobinson flags then
          pr "%s\n\n" danger_will_robinson;
        if List.exists (function Key _ -> true | _ -> false) (snd style) then
          pr "This function takes a key or passphrase parameter which
could contain sensitive material.  Read the section
L</KEYS AND PASSPHRASES> for more information.\n\n";
        match deprecation_notice flags with
        | None -> ()
        | Some txt -> pr "%s\n\n" txt
      )
  ) all_functions_sorted

and generate_structs_pod () =
  (* Structs documentation. *)
  List.iter (
    fun (typ, cols) ->
      pr "=head2 guestfs_%s\n" typ;
      pr "\n";
      pr " struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "   char %s;\n" name
        | name, FUInt32 -> pr "   uint32_t %s;\n" name
        | name, FInt32 -> pr "   int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "   uint64_t %s;\n" name
        | name, FInt64 -> pr "   int64_t %s;\n" name
        | name, FString -> pr "   char *%s;\n" name
        | name, FBuffer ->
            pr "   /* The next two fields describe a byte array. */\n";
            pr "   uint32_t %s_len;\n" name;
            pr "   char *%s;\n" name
        | name, FUUID ->
            pr "   /* The next field is NOT nul-terminated, be careful when printing it: */\n";
            pr "   char %s[32];\n" name
        | name, FOptPercent ->
            pr "   /* The next field is [0..100] or -1 meaning 'not present': */\n";
            pr "   float %s;\n" name
      ) cols;
      pr " };\n";
      pr " \n";
      pr " struct guestfs_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr " \n";
      pr " void guestfs_free_%s (struct guestfs_free_%s *);\n" typ typ;
      pr " void guestfs_free_%s_list (struct guestfs_free_%s_list *);\n"
        typ typ;
      pr "\n"
  ) structs

and generate_availability_pod () =
  (* Availability documentation. *)
  pr "=over 4\n";
  pr "\n";
  List.iter (
    fun (group, functions) ->
      pr "=item B<%s>\n" group;
      pr "\n";
      pr "The following functions:\n";
      List.iter (pr "L</guestfs_%s>\n") functions;
      pr "\n"
  ) optgroups;
  pr "=back\n";
  pr "\n"

(* Generate the guestfs-structs.h file. *)
and generate_structs_h () =
  generate_header CStyle LGPLv2plus;

  (* This is a public exported header file containing various
   * structures.  The structures are carefully written to have
   * exactly the same in-memory format as the XDR structures that
   * we use on the wire to the daemon.  The reason for creating
   * copies of these structures here is just so we don't have to
   * export the whole of guestfs_protocol.h (which includes much
   * unrelated and XDR-dependent stuff that we don't want to be
   * public, or required by clients).
   *
   * To reiterate, we will pass these structures to and from the
   * client with a simple assignment or memcpy, so the format
   * must be identical to what rpcgen / the RFC defines.
   *)

  (* Public structures. *)
  List.iter (
    fun (typ, cols) ->
      pr "struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "  char %s;\n" name
        | name, FString -> pr "  char *%s;\n" name
        | name, FBuffer ->
            pr "  uint32_t %s_len;\n" name;
            pr "  char *%s;\n" name
        | name, FUUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
        | name, FUInt32 -> pr "  uint32_t %s;\n" name
        | name, FInt32 -> pr "  int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "  uint64_t %s;\n" name
        | name, FInt64 -> pr "  int64_t %s;\n" name
        | name, FOptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
      ) cols;
      pr "};\n";
      pr "\n";
      pr "struct guestfs_%s_list {\n" typ;
      pr "  uint32_t len;\n";
      pr "  struct guestfs_%s *val;\n" typ;
      pr "};\n";
      pr "\n";
      pr "extern void guestfs_free_%s (struct guestfs_%s *);\n" typ typ;
      pr "extern void guestfs_free_%s_list (struct guestfs_%s_list *);\n" typ typ;
      pr "\n"
  ) structs

(* Generate the guestfs-actions.h file. *)
and generate_actions_h () =
  generate_header CStyle LGPLv2plus;
  List.iter (
    fun (shortname, style, _, flags, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      let deprecated =
        List.exists (function DeprecatedBy _ -> true | _ -> false) flags in
      let test0 =
        String.length shortname >= 5 && String.sub shortname 0 5 = "test0" in
      let debug =
        String.length shortname >= 5 && String.sub shortname 0 5 = "debug" in
      if not deprecated && not test0 && not debug then
        pr "#define LIBGUESTFS_HAVE_%s 1\n" (String.uppercase shortname);

      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        name style
  ) all_functions_sorted

(* Generate the guestfs-internal-actions.h file. *)
and generate_internal_actions_h () =
  generate_header CStyle LGPLv2plus;
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs__" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"g"
        name style
  ) non_daemon_functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"

/* Check the return message from a call for validity. */
static int
check_reply_header (guestfs_h *g,
                    const struct guestfs_message_header *hdr,
                    unsigned int proc_nr, unsigned int serial)
{
  if (hdr->prog != GUESTFS_PROGRAM) {
    error (g, \"wrong program (%%d/%%d)\", hdr->prog, GUESTFS_PROGRAM);
    return -1;
  }
  if (hdr->vers != GUESTFS_PROTOCOL_VERSION) {
    error (g, \"wrong protocol version (%%d/%%d)\",
           hdr->vers, GUESTFS_PROTOCOL_VERSION);
    return -1;
  }
  if (hdr->direction != GUESTFS_DIRECTION_REPLY) {
    error (g, \"unexpected message direction (%%d/%%d)\",
           hdr->direction, GUESTFS_DIRECTION_REPLY);
    return -1;
  }
  if (hdr->proc != proc_nr) {
    error (g, \"unexpected procedure number (%%d/%%d)\", hdr->proc, proc_nr);
    return -1;
  }
  if (hdr->serial != serial) {
    error (g, \"unexpected serial (%%d/%%d)\", hdr->serial, serial);
    return -1;
  }

  return 0;
}

/* Check we are in the right state to run a high-level action. */
static int
check_state (guestfs_h *g, const char *caller)
{
  if (!guestfs__is_ready (g)) {
    if (guestfs__is_config (g) || guestfs__is_launching (g))
      error (g, \"%%s: call launch before using this function\\n(in guestfish, don't forget to use the 'run' command)\",
        caller);
    else
      error (g, \"%%s called from the wrong state, %%d != READY\",
        caller, guestfs__get_state (g));
    return -1;
  }
  return 0;
}

";

  let error_code_of = function
    | RErr | RInt _ | RInt64 _ | RBool _ -> "-1"
    | RConstString _ | RConstOptString _
    | RString _ | RStringList _
    | RStruct _ | RStructList _
    | RHashtable _ | RBufferOut _ -> "NULL"
  in

  (* Generate code to check String-like parameters are not passed in
   * as NULL (returning an error if they are).
   *)
  let check_null_strings shortname style =
    let pr_newline = ref false in
    List.iter (
      function
      (* parameters which should not be NULL *)
      | String n
      | Device n
      | Pathname n
      | Dev_or_Path n
      | FileIn n
      | FileOut n
      | BufferIn n
      | StringList n
      | DeviceList n
      | Key n ->
          pr "  if (%s == NULL) {\n" n;
          pr "    error (g, \"%%s: %%s: parameter cannot be NULL\",\n";
          pr "           \"%s\", \"%s\");\n" shortname n;
          pr "    return %s;\n" (error_code_of (fst style));
          pr "  }\n";
          pr_newline := true

      (* can be NULL *)
      | OptString _

      (* not applicable *)
      | Bool _
      | Int _
      | Int64 _ -> ()
    ) (snd style);

    if !pr_newline then pr "\n";
  in

  (* Generate code to generate guestfish call traces. *)
  let trace_call shortname style =
    pr "  if (guestfs__get_trace (g)) {\n";

    let needs_i =
      List.exists (function
                   | StringList _ | DeviceList _ -> true
                   | _ -> false) (snd style) in
    if needs_i then (
      pr "    size_t i;\n";
      pr "\n"
    );

    pr "    fprintf (stderr, \"%s\");\n" shortname;
    List.iter (
      function
      | String n			(* strings *)
      | Device n
      | Pathname n
      | Dev_or_Path n
      | FileIn n
      | FileOut n
      | BufferIn n
      | Key n ->
          (* guestfish doesn't support string escaping, so neither do we *)
          pr "    fprintf (stderr, \" \\\"%%s\\\"\", %s);\n" n
      | OptString n ->			(* string option *)
          pr "    if (%s) fprintf (stderr, \" \\\"%%s\\\"\", %s);\n" n n;
          pr "    else fprintf (stderr, \" null\");\n"
      | StringList n
      | DeviceList n ->			(* string list *)
          pr "    fputc (' ', stderr);\n";
          pr "    fputc ('\"', stderr);\n";
          pr "    for (i = 0; %s[i]; ++i) {\n" n;
          pr "      if (i > 0) fputc (' ', stderr);\n";
          pr "      fputs (%s[i], stderr);\n" n;
          pr "    }\n";
          pr "    fputc ('\"', stderr);\n";
      | Bool n ->			(* boolean *)
          pr "    fputs (%s ? \" true\" : \" false\", stderr);\n" n
      | Int n ->			(* int *)
          pr "    fprintf (stderr, \" %%d\", %s);\n" n
      | Int64 n ->
          pr "    fprintf (stderr, \" %%\" PRIi64, %s);\n" n
    ) (snd style);
    pr "    fputc ('\\n', stderr);\n";
    pr "  }\n";
    pr "\n";
  in

  (* For non-daemon functions, generate a wrapper around each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" name style;
      pr "{\n";
      check_null_strings shortname style;
      trace_call shortname style;
      pr "  return guestfs__%s " shortname;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      pr "}\n";
      pr "\n"
  ) non_daemon_functions;

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      let error_code = error_code_of (fst style) in

      (* Generate the action stub. *)
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" name style;

      pr "{\n";

      (match snd style with
       | [] -> ()
       | _ -> pr "  struct %s_args args;\n" name
      );

      pr "  guestfs_message_header hdr;\n";
      pr "  guestfs_message_error err;\n";
      let has_ret =
        match fst style with
        | RErr -> false
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RInt _ | RInt64 _
        | RBool _ | RString _ | RStringList _
        | RStruct _ | RStructList _
        | RHashtable _ | RBufferOut _ ->
            pr "  struct %s_ret ret;\n" name;
            true in

      pr "  int serial;\n";
      pr "  int r;\n";
      pr "\n";
      check_null_strings shortname style;
      trace_call shortname style;
      pr "  if (check_state (g, \"%s\") == -1) return %s;\n"
        shortname error_code;
      pr "  guestfs___set_busy (g);\n";
      pr "\n";

      (* Send the main header and arguments. *)
      (match snd style with
       | [] ->
           pr "  serial = guestfs___send (g, GUESTFS_PROC_%s, NULL, NULL);\n"
             (String.uppercase shortname)
       | args ->
           List.iter (
             function
             | Pathname n | Device n | Dev_or_Path n | String n | Key n ->
                 pr "  args.%s = (char *) %s;\n" n n
             | OptString n ->
                 pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
             | StringList n | DeviceList n ->
                 pr "  args.%s.%s_val = (char **) %s;\n" n n n;
                 pr "  for (args.%s.%s_len = 0; %s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
             | Bool n ->
                 pr "  args.%s = %s;\n" n n
             | Int n ->
                 pr "  args.%s = %s;\n" n n
             | Int64 n ->
                 pr "  args.%s = %s;\n" n n
             | FileIn _ | FileOut _ -> ()
             | BufferIn n ->
                 pr "  /* Just catch grossly large sizes. XDR encoding will make this precise. */\n";
                 pr "  if (%s_size >= GUESTFS_MESSAGE_MAX) {\n" n;
                 pr "    error (g, \"%%s: size of input buffer too large\", \"%s\");\n"
                   shortname;
                 pr "    guestfs___end_busy (g);\n";
                 pr "    return %s;\n" error_code;
                 pr "  }\n";
                 pr "  args.%s.%s_val = (char *) %s;\n" n n n;
                 pr "  args.%s.%s_len = %s_size;\n" n n n
           ) args;
           pr "  serial = guestfs___send (g, GUESTFS_PROC_%s,\n"
             (String.uppercase shortname);
           pr "        (xdrproc_t) xdr_%s_args, (char *) &args);\n"
             name;
      );
      pr "  if (serial == -1) {\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Send any additional files (FileIn) requested. *)
      let need_read_reply_label = ref false in
      List.iter (
        function
        | FileIn n ->
            pr "  r = guestfs___send_file (g, %s);\n" n;
            pr "  if (r == -1) {\n";
            pr "    guestfs___end_busy (g);\n";
            pr "    return %s;\n" error_code;
            pr "  }\n";
            pr "  if (r == -2) /* daemon cancelled */\n";
            pr "    goto read_reply;\n";
            need_read_reply_label := true;
            pr "\n";
        | _ -> ()
      ) (snd style);

      (* Wait for the reply from the remote end. *)
      if !need_read_reply_label then pr " read_reply:\n";
      pr "  memset (&hdr, 0, sizeof hdr);\n";
      pr "  memset (&err, 0, sizeof err);\n";
      if has_ret then pr "  memset (&ret, 0, sizeof ret);\n";
      pr "\n";
      pr "  r = guestfs___recv (g, \"%s\", &hdr, &err,\n        " shortname;
      if not has_ret then
        pr "NULL, NULL"
      else
        pr "(xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret" shortname;
      pr ");\n";

      pr "  if (r == -1) {\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &hdr, GUESTFS_PROC_%s, serial) == -1) {\n"
        (String.uppercase shortname);
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    error (g, \"%%s: %%s\", \"%s\", err.error_message);\n" shortname;
      pr "    free (err.error_message);\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Expecting to receive further files (FileOut)? *)
      List.iter (
        function
        | FileOut n ->
            pr "  if (guestfs___recv_file (g, %s) == -1) {\n" n;
            pr "    guestfs___end_busy (g);\n";
            pr "    return %s;\n" error_code;
            pr "  }\n";
            pr "\n";
        | _ -> ()
      ) (snd style);

      pr "  guestfs___end_busy (g);\n";

      (match fst style with
       | RErr -> pr "  return 0;\n"
       | RInt n | RInt64 n | RBool n ->
           pr "  return ret.%s;\n" n
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString n ->
           pr "  return ret.%s; /* caller will free */\n" n
       | RStringList n | RHashtable n ->
           pr "  /* caller will free this, but we need to add a NULL entry */\n";
           pr "  ret.%s.%s_val =\n" n n;
           pr "    safe_realloc (g, ret.%s.%s_val,\n" n n;
           pr "                  sizeof (char *) * (ret.%s.%s_len + 1));\n"
             n n;
           pr "  ret.%s.%s_val[ret.%s.%s_len] = NULL;\n" n n n n;
           pr "  return ret.%s.%s_val;\n" n n
       | RStruct (n, _) ->
           pr "  /* caller will free this */\n";
           pr "  return safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
       | RStructList (n, _) ->
           pr "  /* caller will free this */\n";
           pr "  return safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
       | RBufferOut n ->
           pr "  /* RBufferOut is tricky: If the buffer is zero-length, then\n";
           pr "   * _val might be NULL here.  To make the API saner for\n";
           pr "   * callers, we turn this case into a unique pointer (using\n";
           pr "   * malloc(1)).\n";
           pr "   */\n";
           pr "  if (ret.%s.%s_len > 0) {\n" n n;
           pr "    *size_r = ret.%s.%s_len;\n" n n;
           pr "    return ret.%s.%s_val; /* caller will free */\n" n n;
           pr "  } else {\n";
           pr "    free (ret.%s.%s_val);\n" n n;
           pr "    char *p = safe_malloc (g, 1);\n";
           pr "    *size_r = ret.%s.%s_len;\n" n n;
           pr "    return p;\n";
           pr "  }\n";
      );

      pr "}\n\n"
  ) daemon_functions;

  (* Functions to free structures. *)
  pr "/* Structure-freeing functions.  These rely on the fact that the\n";
  pr " * structure format is identical to the XDR format.  See note in\n";
  pr " * generator.ml.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun (typ, _) ->
      pr "void\n";
      pr "guestfs_free_%s (struct guestfs_%s *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

      pr "void\n";
      pr "guestfs_free_%s_list (struct guestfs_%s_list *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s_list, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

  ) structs;

(* Generate the linker script which controls the visibility of
 * symbols in the public ABI and ensures no other symbols get
 * exported accidentally.
 *)
and generate_linker_script () =
  generate_header HashStyle GPLv2plus;

  let globals = [
    "guestfs_create";
    "guestfs_close";
    "guestfs_get_error_handler";
    "guestfs_get_out_of_memory_handler";
    "guestfs_get_private";
    "guestfs_last_error";
    "guestfs_set_close_callback";
    "guestfs_set_error_handler";
    "guestfs_set_launch_done_callback";
    "guestfs_set_log_message_callback";
    "guestfs_set_out_of_memory_handler";
    "guestfs_set_private";
    "guestfs_set_progress_callback";
    "guestfs_set_subprocess_quit_callback";

    (* Unofficial parts of the API: the bindings code use these
     * functions, so it is useful to export them.
     *)
    "guestfs_safe_calloc";
    "guestfs_safe_malloc";
    "guestfs_safe_strdup";
    "guestfs_safe_memdup";
    "guestfs_tmpdir";
  ] in
  let functions =
    List.map (fun (name, _, _, _, _, _, _) -> "guestfs_" ^ name)
      all_functions in
  let structs =
    List.concat (
      List.map (fun (typ, _) ->
                  ["guestfs_free_" ^ typ; "guestfs_free_" ^ typ ^ "_list"])
        structs
    ) in
  let globals = List.sort compare (globals @ functions @ structs) in

  pr "{\n";
  pr "    global:\n";
  List.iter (pr "        %s;\n") globals;
  pr "\n";

  pr "    local:\n";
  pr "        *;\n";
  pr "};\n"

and generate_max_proc_nr () =
  pr "%d\n" max_proc_nr
