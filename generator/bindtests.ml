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

let generate_header = generate_header ~inputs:["generator/bindtests.ml"]

let rec generate_bindtests () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"

int
guestfs_impl_internal_test_set_output (guestfs_h *g, const char *filename)
{
  FILE *fp;

  fp = fopen (filename, \"w\");
  if (fp == NULL) {
    perrorf (g, \"cannot open output file %%s\\n\", filename);
    return -1;
  }

  if (guestfs_internal_test_close_output (g) == -1) {
    fclose (fp);
    return -1;
  }

  g->test_fp = fp;

  return 0;
}

int
guestfs_impl_internal_test_close_output (guestfs_h *g)
{
  if (g->test_fp != NULL) {
    if (fclose (g->test_fp) == EOF) {
      perrorf (g, \"fclose\");
      g->test_fp = NULL;
      return -1;
    }
    g->test_fp = NULL;
  }

  return 0;
}

static inline FILE *
get_fp (guestfs_h *g)
{
  if (g->test_fp)
    return g->test_fp;
  else
    return stdout;
}

static void
print_strings (guestfs_h *g, char *const *argv)
{
  FILE *fp = get_fp (g);
  size_t argc;

  fprintf (fp, \"[\");
  for (argc = 0; argv[argc] != NULL; ++argc) {
    if (argc > 0) fprintf (fp, \", \");
    fprintf (fp, \"\\\"%%s\\\"\", argv[argc]);
  }
  fprintf (fp, \"]\\n\");
}

/* Fill an lvm_pv struct with known data.  Used by
 * guestfs_internal_test_rstruct & guestfs_internal_test_rstructlist.
 */
static void
fill_lvm_pv (guestfs_h *g, struct guestfs_lvm_pv *pv, size_t i)
{
  pv->pv_name = safe_asprintf (g, \"pv%%zu\", i);
  memcpy (pv->pv_uuid, \"12345678901234567890123456789012\", 32);
  pv->pv_fmt = safe_strdup (g, \"unknown\");
  pv->pv_size = i;
  pv->dev_size = i;
  pv->pv_free = i;
  pv->pv_used = i;
  pv->pv_attr = safe_asprintf (g, \"attr%%zu\", i);
  pv->pv_pe_count = i;
  pv->pv_pe_alloc_count = i;
  pv->pv_tags = safe_asprintf (g, \"tag%%zu\", i);
  pv->pe_start = i;
  pv->pv_mda_count = i;
  pv->pv_mda_free = i;
}

";

  let ptests, rtests =
    match test_functions with
    | t :: t1 :: t2 :: rtests -> [ t; t1; t2 ], rtests
    | _ -> assert false in

  List.iter (
    fun { name; style = (ret, args, optargs as style); c_optarg_prefix } ->
      pr "/* The %s function prints its parameters to stdout or the\n" name;
      pr " * file set by internal_test_set_output.\n";
      pr " */\n";

      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" ~prefix:"guestfs_impl_" ~optarg_proto:Argv name style;
      pr "{\n";
      pr "  FILE *fp = get_fp (g);\n";
      pr "\n";

      List.iter (
        function
        | String (_, n) -> pr "  fprintf (fp, \"%%s\\n\", %s);\n" n
        | BufferIn n ->
          pr "  {\n";
          pr "    size_t i;\n";
          pr "    for (i = 0; i < %s_size; ++i)\n" n;
          pr "      fprintf (fp, \"<%%02x>\", (unsigned) %s[i]);\n" n;
          pr "    fprintf (fp, \"\\n\");\n";
          pr "  }\n";
        | OptString n ->
           pr "  fprintf (fp, \"%%s\\n\", %s ? %s : \"null\");\n" n n
        | StringList (_, n) ->
          pr "  print_strings (g, %s);\n" n
        | Bool n ->
           pr "  fprintf (fp, \"%%s\\n\", %s ? \"true\" : \"false\");\n" n
        | Int n -> pr "  fprintf (fp, \"%%d\\n\", %s);\n" n
        | Int64 n -> pr "  fprintf (fp, \"%%\" PRIi64 \"\\n\", %s);\n" n
        | Pointer _ -> assert false
      ) args;

      let check_optarg n printf_args =
        pr "  fprintf (fp, \"%s: \");\n" n;
        pr "  if (optargs->bitmask & %s_%s_BITMASK) {\n" c_optarg_prefix
          (String.uppercase_ascii n);
        pr "    fprintf (fp, %s);\n" printf_args;
        pr "  } else {\n";
        pr "    fprintf (fp, \"unset\\n\");\n";
        pr "  }\n";
      in
      List.iter (
        function
        | OBool n ->
          let printf_args =
            sprintf "\"%%s\\n\", optargs->%s ? \"true\" : \"false\"" n in
          check_optarg n printf_args;
        | OInt n ->
          let printf_args = sprintf "\"%%i\\n\", optargs->%s" n in
          check_optarg n printf_args;
        | OInt64 n ->
          let printf_args = sprintf "\"%%\" PRIi64 \"\\n\", optargs->%s" n in
          check_optarg n printf_args;
        | OString n ->
          let printf_args = sprintf "\"%%s\\n\", optargs->%s" n in
          check_optarg n printf_args;
        | OStringList n ->
          pr "  fprintf (fp, \"%s: \");\n" n;
          pr "  if (optargs->bitmask & %s_%s_BITMASK) {\n" c_optarg_prefix
            (String.uppercase_ascii n);
          pr "    print_strings (g, optargs->%s);\n" n;
          pr "  } else {\n";
          pr "    fprintf (fp, \"unset\\n\");\n";
          pr "  }\n";
      ) optargs;
      pr "  /* Java changes stdout line buffering so we need this: */\n";
      pr "  fflush (fp);\n";
      pr "  return 0;\n";
      pr "}\n";
      pr "\n"
  ) ptests;

  List.iter (
    fun { name; style = (ret, args, _ as style) } ->
      if String.sub name (String.length name - 3) 3 <> "err" then (
        pr "/* Test normal return. */\n";
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_impl_" name style;
        pr "{\n";
        (match ret with
         | RErr ->
             pr "  return 0;\n"
         | RInt _ ->
             pr "  int r;\n";
             pr "  if (sscanf (val, \"%%d\", &r) != 1) {\n";
             pr "    error (g, \"%%s: expecting int argument\", \"%s\");\n" name;
             pr "    return -1;\n";
             pr "  }\n";
             pr "  return r;\n"
         | RInt64 _ ->
             pr "  int64_t r;\n";
             pr "  if (sscanf (val, \"%%\" SCNi64, &r) != 1) {\n";
             pr "    error (g, \"%%s: expecting int64 argument\", \"%s\");\n" name;
             pr "    return -1;\n";
             pr "  }\n";
             pr "  return r;\n"
         | RBool _ ->
             pr "  return STREQ (val, \"true\");\n"
         | RConstString _
         | RConstOptString _ ->
             (* Can't return the input string here.  Return a static
              * string so we ensure we get a segfault if the caller
              * tries to free it.
              *)
             pr "  return \"static string\";\n"
         | RString _ ->
             pr "  return strdup (val);\n"
         | RStringList _ ->
             pr "  char **strs;\n";
             pr "  size_t n, i;\n";
             pr "  if (sscanf (val, \"%%zu\", &n) != 1) {\n";
             pr "    error (g, \"%%s: expecting int argument\", \"%s\");\n" name;
             pr "    return NULL;\n";
             pr "  }\n";
             pr "  strs = safe_malloc (g, (n+1) * sizeof (char *));\n";
             pr "  for (i = 0; i < n; ++i) {\n";
             pr "    strs[i] = safe_malloc (g, 32);\n";
             pr "    snprintf (strs[i], 32, \"%%zu\", i);\n";
             pr "  }\n";
             pr "  strs[n] = NULL;\n";
             pr "  return strs;\n"
         | RStruct (_, typ) ->
             pr "  struct guestfs_%s *r;\n" typ;
             pr "  r = safe_malloc (g, sizeof *r);\n";
             pr "  fill_lvm_pv (g, r, 0);\n";
             pr "  return r;\n"
         | RStructList (_, typ) ->
             pr "  struct guestfs_%s_list *r;\n" typ;
             pr "  uint32_t len;\n";
             pr "  if (sscanf (val, \"%%\" SCNu32, &len) != 1) {\n";
             pr "    error (g, \"%%s: expecting uint32 argument\", \"%s\");\n" name;
             pr "    return NULL;\n";
             pr "  }\n";
             pr "  r = safe_malloc (g, sizeof *r);\n";
             pr "  r->len = len;\n";
             pr "  r->val = safe_malloc (g, r->len * sizeof (*r->val));\n";
             pr "  for (size_t i = 0; i < r->len; i++)\n";
             pr "    fill_lvm_pv (g, &r->val[i], i);\n";
             pr "  return r;\n"
         | RHashtable _ ->
             pr "  char **strs;\n";
             pr "  size_t n, i;\n";
             pr "  if (sscanf (val, \"%%zu\", &n) != 1) {\n";
             pr "    error (g, \"%%s: expecting int argument\", \"%s\");\n" name;
             pr "    return NULL;\n";
             pr "  }\n";
             pr "  strs = safe_malloc (g, (n*2+1) * sizeof (*strs));\n";
             pr "  for (i = 0; i < n; ++i) {\n";
             pr "    strs[i*2] = safe_malloc (g, 32);\n";
             pr "    strs[i*2+1] = safe_malloc (g, 32);\n";
             pr "    snprintf (strs[i*2], 32, \"%%zu\", i);\n";
             pr "    snprintf (strs[i*2+1], 32, \"%%zu\", i);\n";
             pr "  }\n";
             pr "  strs[n*2] = NULL;\n";
             pr "  return strs;\n"
         | RBufferOut _ ->
             pr "  *size_r = strlen (val);\n";
             pr "  return strdup (val);\n"
        );
        pr "}\n";
        pr "\n"
      ) else (
        pr "/* Test error return. */\n";
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs_impl_" name style;
        pr "{\n";
        pr "  error (g, \"error\");\n";
        (match ret with
         | RErr | RInt _ | RInt64 _ | RBool _ ->
             pr "  return -1;\n"
         | RConstString _ | RConstOptString _
         | RString _ | RStringList _ | RStruct _
         | RStructList _
         | RHashtable _
         | RBufferOut _ ->
             pr "  return NULL;\n"
        );
        pr "}\n";
        pr "\n"
      )
  ) rtests

and generate_ocaml_bindtests () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
let () =
  let g = Guestfs.create () in
";

  let mkargs args optargs =
    let optargs =
      match optargs with
      | Some n -> n
      | None -> []
    in
    String.concat " " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "None"
        | CallOptString (Some s) -> sprintf "(Some \"%s\")" s
        | CallStringList xs ->
            "[|" ^ String.concat ";" (List.map (sprintf "\"%s\"") xs) ^ "|]"
        | CallInt i when i >= 0 -> string_of_int i
        | CallInt i (* when i < 0 *) -> "(" ^ string_of_int i ^ ")"
        | CallInt64 i when i >= 0L -> Int64.to_string i ^ "L"
        | CallInt64 i (* when i < 0L *) -> "(" ^ Int64.to_string i ^ "L)"
        | CallBool b -> string_of_bool b
        | CallBuffer s -> sprintf "%S" s
      ) args
      @
      List.map (
        function
        | CallOBool (n, v)    -> "~" ^ n ^ ":" ^ string_of_bool v
        | CallOInt (n, v)     -> "~" ^ n ^ ":(" ^ string_of_int v ^ ")"
        | CallOInt64 (n, v)   -> "~" ^ n ^ ":(" ^ Int64.to_string v ^ "L)"
        | CallOString (n, v)  -> "~" ^ n ^ ":\"" ^ v ^ "\""
        | CallOStringList (n, xs) ->
          "~" ^ n ^ ":" ^
            "[|" ^ String.concat ";" (List.map (sprintf "\"%s\"") xs) ^ "|]"
      ) optargs
    )
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "  Guestfs.%s g %s;\n" f (mkargs args optargs)
  );

  pr "print_endline \"EOF\"\n"

and generate_perl_bindtests () =
  pr "#!/usr/bin/env perl\n";
  generate_header HashStyle GPLv2plus;

  pr "\
use strict;
use warnings;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
";

  let mkargs args optargs =
    let optargs =
      match optargs with
      | Some n -> n
      | None -> []
    in
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "undef"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> "\"" ^ Int64.to_string i ^ "\""
        | CallBool b -> if b then "1" else "0"
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
      @
      List.map (
        function
        | CallOBool (n, v)    -> "'" ^ n ^ "' => " ^ if v then "1" else "0"
        | CallOInt (n, v)     -> "'" ^ n ^ "' => " ^ string_of_int v
        | CallOInt64 (n, v)   -> "'" ^ n ^ "' => \"" ^ Int64.to_string v ^ "\""
        | CallOString (n, v)  -> "'" ^ n ^ "' => '" ^ v ^ "'"
        | CallOStringList (n, xs) ->
          "'" ^ n ^ "' => " ^
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
      ) optargs
    )
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "$g->%s (%s);\n" f (mkargs args optargs)
  );

  pr "print \"EOF\\n\"\n"

and generate_python_bindtests () =
  generate_header HashStyle GPLv2plus;

  pr "\
import guestfs

g = guestfs.GuestFS()
";

  let mkargs args optargs =
    let optargs =
      match optargs with
      | Some n -> n
      | None -> []
    in
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "None"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat ", " (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> if b then "1" else "0"
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
      @
      List.map (
        function
        | CallOBool (n, v)    -> n ^ "=" ^ if v then "True" else "False"
        | CallOInt (n, v)     -> n ^ "=" ^ string_of_int v
        | CallOInt64 (n, v)   -> n ^ "=" ^ Int64.to_string v
        | CallOString (n, v)  -> n ^ "=\"" ^ v ^ "\""
        | CallOStringList (n, xs) ->
          n ^ "=" ^
            "[" ^ String.concat ", " (List.map (sprintf "\"%s\"") xs) ^ "]"
      ) optargs
    )
  in

  generate_lang_bindtests (
    fun f args optargs ->
      pr "g.%s(%s)\n" f
        (Python.indent_python (mkargs args optargs) (3 + String.length f) 78)
  );

  pr "print(\"EOF\")\n"

and generate_ruby_bindtests () =
  generate_header HashStyle GPLv2plus;

  pr "\
require 'guestfs'

g = Guestfs::Guestfs.new()
";

  let mkargs args optargs =
    let optargs =
      match optargs with
      | Some n -> n
      | None -> []
    in
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "nil"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> string_of_bool b
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
    ) ^
    ", {" ^
    String.concat ", " (
      List.map (
        function
        | CallOBool (n, v)    -> ":" ^ n ^ " => " ^ string_of_bool v
        | CallOInt (n, v)     -> ":" ^ n ^ " => " ^ string_of_int v
        | CallOInt64 (n, v)   -> ":" ^ n ^ " => " ^ Int64.to_string v
        | CallOString (n, v)  -> ":" ^ n ^ " => \"" ^ v ^ "\""
        | CallOStringList (n, xs) ->
          ":" ^ n ^ " => " ^
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
      ) optargs
    ) ^
    "}"
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "g.%s(%s)\n" f (mkargs args optargs)
  );

  pr "print \"EOF\\n\"\n"

and generate_java_bindtests () =
  generate_header CStyle GPLv2plus;

  pr "\
import java.util.Map;
import java.util.HashMap;
import com.redhat.et.libguestfs.*;

@SuppressWarnings(\"serial\")
public class Bindtests {
    public static void main (String[] argv)
    {
        try {
            GuestFS g = new GuestFS ();
            Map<String, Object> o;

";

  let mkoptargs =
    function
    | Some optargs ->
      "o = new HashMap<String, Object>() {{" ::
      List.map (
        function
        | CallOBool (n, v)    ->
          "  put(\"" ^ n ^ "\", Boolean." ^ (if v then "TRUE" else "FALSE") ^ ");"
        | CallOInt (n, v)     ->
          "  put(\"" ^ n ^ "\", " ^ string_of_int v ^ ");"
        | CallOInt64 (n, v)   ->
          "  put(\"" ^ n ^ "\", " ^ Int64.to_string v ^ "L);"
        | CallOString (n, v)  ->
          "  put(\"" ^ n ^ "\", \"" ^ v ^ "\");"
        | CallOStringList (n, xs)  ->
          "  put(\"" ^ n ^ "\", " ^
            "new String[]{" ^
            String.concat "," (List.map (sprintf "\"%s\"") xs) ^
            "});"
      ) optargs @
      [ "}};\n" ]
    | None ->
      [ "o = null;" ]
  in

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "null"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "new String[]{" ^
              String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "}"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i ^ "L"
        | CallBool b -> string_of_bool b
        | CallBuffer s ->
            "new byte[] { " ^ String.concat "," (
              String.map_chars (fun c -> string_of_int (Char.code c)) s
            ) ^ " }"
      ) args
    )
  in

  let pr_indent indent strings =
    List.iter ( fun s -> pr "%s%s\n" indent s) strings
  in

  generate_lang_bindtests (
    fun f args optargs ->
      pr_indent "            " (mkoptargs optargs);
      pr "            g.%s (%s, o);\n" f (mkargs args)
  );

  pr "
            System.out.println (\"EOF\");
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
"

and generate_haskell_bindtests () =
  generate_header HaskellStyle GPLv2plus;

  pr "\
module Bindtests where
import qualified Guestfs

main = do
  g <- Guestfs.create
";

  let mkargs args =
    String.concat " " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "Nothing"
        | CallOptString (Some s) -> sprintf "(Just \"%s\")" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i when i < 0 -> "(" ^ string_of_int i ^ ")"
        | CallInt i -> string_of_int i
        | CallInt64 i when i < 0L -> "(" ^ Int64.to_string i ^ ")"
        | CallInt64 i -> Int64.to_string i
        | CallBool true -> "True"
        | CallBool false -> "False"
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "  Guestfs.%s g %s\n" f (mkargs args)
  );

  pr "  putStrLn \"EOF\"\n"

and generate_gobject_js_bindtests () =
  generate_header CPlusPlusStyle GPLv2plus;

  pr "\
const Guestfs = imports.gi.Guestfs;

var g = new Guestfs.Session();
var o;

";

    let mkoptargs = function
    | Some optargs ->
      "o = new Guestfs.InternalTest({" ^
      (
        String.concat ", " (
          List.map (
            function
            | CallOBool (n, v)    -> n ^ ": " ^ (if v then "true" else "false")
            | CallOInt (n, v)     -> n ^ ": " ^ (string_of_int v)
            | CallOInt64 (n, v)   -> n ^ ": " ^ Int64.to_string v
            | CallOString (n, v)  -> n ^ ": \"" ^ v ^ "\""
            | CallOStringList (n, xs) -> "" (* not implemented XXX *)
(*
            | CallOStringList (n, xs) ->
              n ^ ": " ^
                "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
*)
          ) optargs
        )
      ) ^
      "});"
    | None ->
      "o = null;"
    in

    let mkargs args =
      String.concat ", " (
        (List.map (
          function
          | CallString s -> "\"" ^ s ^ "\""
          | CallOptString None -> "null"
          | CallOptString (Some s) -> "\"" ^ s ^ "\""
          | CallStringList xs ->
              "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
          | CallInt i -> string_of_int i
          | CallInt64 i -> Int64.to_string i
          | CallBool true -> "true"
          | CallBool false -> "false"
          | CallBuffer s -> "\"" ^ c_quote s ^ "\""
        ) args)
        @ ["o"; "null"]
      )
    in
    generate_lang_bindtests (
      fun f args optargs ->
        pr "%s\ng.%s(%s);\n" (mkoptargs optargs) f (mkargs args)
    );

    pr "\nprint(\"EOF\");\n"

and generate_erlang_bindtests () =
  pr "#!/usr/bin/env escript\n";
  pr "%%! -smp enable -sname create_disk debug verbose\n";
  pr "\n";
  generate_header ErlangStyle GPLv2plus;

  pr "main(_) ->\n";
  pr "    {ok, G} = guestfs:create(),\n";
  pr "\n";
  pr "    %% We have to set the output file here because otherwise the\n";
  pr "    %% bindtests code would print its output on stdout, and that\n";
  pr "    %% channel is also being used by the erl-guestfs communications.\n";
  pr "    Filename = \"bindtests.tmp\",\n";
  pr "    ok = guestfs:internal_test_set_output(G, Filename),\n";
  pr "\n";

  generate_lang_bindtests (
    fun f args optargs ->
      pr "    ok = guestfs:%s(G" f;
      List.iter (function
      | CallString s -> pr ", \"%s\"" s
      | CallOptString None -> pr ", undefined"
      | CallOptString (Some s) -> pr ", \"%s\"" s
      | CallStringList xs ->
        pr ", [%s]" (String.concat "," (List.map (sprintf "\"%s\"") xs))
      | CallInt i -> pr ", %d" i
      | CallInt64 i -> pr ", %Ld" i
      | CallBool b -> pr ", %b" b
      | CallBuffer s -> pr ", \"%s\"" (c_quote s)
      ) args;
      (match optargs with
      | None -> ()
      | Some optargs ->
        pr ", [";
        let needs_comma = ref false in
        List.iter (
          fun optarg ->
            if !needs_comma then pr ", ";
            needs_comma := true;
            match optarg with
            | CallOBool (n, v) -> pr "{%s, %b}" n v
            | CallOInt (n, v) -> pr "{%s, %d}" n v
            | CallOInt64 (n, v) -> pr "{%s, %Ld}" n v
            | CallOString (n, v) -> pr "{%s, \"%s\"}" n v
            | CallOStringList (n, xs) ->
              pr "{%s, [%s]}" n
                (String.concat "," (List.map (sprintf "\"%s\"") xs))
        ) optargs;
        pr "]";
      );
      pr "),\n"
  );

  pr "\n";
  pr "    ok = guestfs:internal_test_close_output(G),\n";
  pr "    ok = guestfs:close(G),\n";
  pr "    {ok, File} = file:open(Filename, [append]),\n";
  pr "    ok = file:write(File, \"EOF\\n\"),\n";
  pr "    ok = file:close(File).\n"

and generate_lua_bindtests () =
  generate_header LuaStyle GPLv2plus;

  pr "local G = require \"guestfs\"\n";
  pr "\n";
  pr "local g = G.create ()\n";
  pr "\n";

  generate_lang_bindtests (
    fun f args optargs ->
      pr "g:%s (" f;
      let needs_comma = ref false in
      List.iter (
        fun arg ->
          if !needs_comma then pr ", ";
          needs_comma := true;

          match arg with
          | CallString s -> pr "\"%s\"" s
          | CallOptString None -> pr "nil"
          | CallOptString (Some s) -> pr "\"%s\"" s
          | CallStringList xs ->
            pr "{%s}" (String.concat "," (List.map (sprintf "\"%s\"") xs))
          | CallInt i -> pr "%d" i
          | CallInt64 i -> pr "\"%Ld\"" i
          | CallBool b -> pr "%b" b
          | CallBuffer s -> pr "\"%s\"" (c_quote s)
      ) args;
      (match optargs with
      | None -> ()
      | Some optargs ->
        if !needs_comma then pr ", ";

        pr "{";
        needs_comma := false;
        List.iter (
          fun optarg ->
            if !needs_comma then pr ", ";
            needs_comma := true;
            match optarg with
            | CallOBool (n, v) -> pr "%s = %b" n v
            | CallOInt (n, v) -> pr "%s = %d" n v
            | CallOInt64 (n, v) -> pr "%s = \"%Ld\"" n v
            | CallOString (n, v) -> pr "%s = \"%s\"" n v
            | CallOStringList (n, xs) ->
              pr "%s = {%s}" n
                (String.concat "," (List.map (sprintf "\"%s\"") xs))
        ) optargs;
        pr "}";
      );
      pr ")\n"
  );

  pr "\n";
  pr "print (\"EOF\")\n"

and generate_golang_bindtests () =
  generate_header CStyle GPLv2plus;

  pr "package main\n";
  pr "\n";
  pr "import (\n";
  pr "    \"fmt\"\n";
  pr "    \"libguestfs.org/guestfs\"\n";
  pr ")\n";
  pr "\n";
  pr "func main() {\n";
  pr "    g, errno := guestfs.Create ()\n";
  pr "    if errno != nil {\n";
  pr "        panic (fmt.Sprintf (\"could not create handle: %%s\", errno))\n";
  pr "    }\n";
  pr "    defer g.Close ()\n";
  pr "\n";

  generate_lang_bindtests (
    fun f args optargs ->

      pr "    if err := g.%s (" (String.capitalize_ascii f);

      let needs_comma = ref false in
      List.iter (
        fun arg ->
          if !needs_comma then pr ", ";
          needs_comma := true;

          match arg with
          | CallString s -> pr "\"%s\"" s
          | CallOptString None -> pr "nil"
          | CallOptString (Some s) -> pr "string_addr (\"%s\")" s
          | CallStringList xs ->
            pr "[]string{%s}"
              (String.concat ", " (List.map (sprintf "\"%s\"") xs))
          | CallInt i -> pr "%d" i
          | CallInt64 i -> pr "%Ld" i
          | CallBool b -> pr "%b" b
          | CallBuffer s ->
            let quote_char = function
              | '\000' -> "'\\000'"
              | c -> sprintf "'%c'" c
            in
            pr "[]byte{%s}"
              (String.concat ", " (List.map quote_char (String.explode s)))
      ) args;
      if !needs_comma then pr ", ";
      (match optargs with
      | None -> pr "nil"
      | Some optargs ->
        pr "&guestfs.Optargs%s{" (String.capitalize_ascii f);
        needs_comma := false;
        List.iter (
          fun optarg ->
            if !needs_comma then pr ", ";
            needs_comma := true;
            match optarg with
            | CallOBool (n, v) ->
              let n = String.capitalize_ascii n in
              pr "%s_is_set: true, %s: %b" n n v
            | CallOInt (n, v) ->
              let n = String.capitalize_ascii n in
              pr "%s_is_set: true, %s: %d" n n v
            | CallOInt64 (n, v) ->
              let n = String.capitalize_ascii n in
              pr "%s_is_set: true, %s: %Ld" n n v
            | CallOString (n, v) ->
              let n = String.capitalize_ascii n in
              pr "%s_is_set: true, %s: \"%s\"" n n v
            | CallOStringList (n, xs) ->
              let n = String.capitalize_ascii n in
              pr "%s_is_set: true, %s: []string{%s}"
                n n (String.concat ", " (List.map (sprintf "\"%s\"") xs))
        ) optargs;
        pr "}";
      );
      pr "); err != nil {\n";
      pr "        panic (fmt.Sprintf (\"error: %%s\", err))\n";
      pr "    }\n";
  );

  pr "\n";
  pr "    fmt.Printf (\"EOF\\n\")\n";
  pr "}\n";
  pr "\n";
  pr "/* Work around golang lameness */\n";
  pr "func string_addr (s string) *string {\n";
  pr "    return &s;\n";
  pr "}\n"

and generate_php_bindtests () =
  (* No header for this, as it is a .phpt file. *)

  (* Unfortunately, due to the way optional arguments work in PHP,
   * we cannot test arbitrary arguments skipping the previous ones
   * in the function signatures.
   *
   * Hence, check only the non-optional arguments, and fix the
   * baseline output to expect always "unset" optional arguments.
   *)

  pr "--TEST--\n";
  pr "General PHP binding test.\n";
  pr "--SKIPIF--\n";
  pr "<?php\n";
  pr "if (PHP_INT_SIZE < 8)\n";
  pr "  print 'skip 32bit platforms due to limited int in PHP';\n";
  pr "?>\n";
  pr "--FILE--\n";
  pr "<?php\n";
  pr "$g = guestfs_create ();\n";

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "NULL"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
          sprintf "array(%s)"
            (String.concat "," (List.map (sprintf "\"%s\"") xs))
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> if b then "1" else "0"
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args optargs ->
      pr "if (guestfs_%s ($g, %s) == false) {\n" f (mkargs args);
      pr "  echo (\"Call failed: \" . guestfs_last_error ($g) . \"\\n\");\n";
      pr "  exit;\n";
      pr "}\n";
  );

  pr "echo (\"EOF\\n\");\n";
  pr "?>\n";
  pr "--EXPECT--\n";

  let dump filename =
    with_open_in filename (
      fun chan ->
        let rec loop () =
          let line = input_line chan in
          (match String.nsplit ":" line with
           | ("obool"|"oint"|"oint64"|"ostring"|"ostringlist") as x :: _ ->
              pr "%s: unset\n" x
           | _ -> pr "%s\n" line
          );
          loop ()
        in
        (try loop () with End_of_file -> ());
    )
  in

  dump "bindtests"

and generate_rust_bindtests () =
  let copyrights = ["Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>"] in
  generate_header ~copyrights CStyle GPLv2plus;

  pr "extern crate guestfs;\n";
  pr "use guestfs::*;\n";
  pr "use std::default::Default;\n";
  pr "\n";
  pr "fn main() {\n";
  pr "    let g = match Handle::create() {\n";
  pr "        Ok(g) => g,\n";
  pr "        Err(e) => panic!(\"could not create handle {:?}\", e),\n";
  pr "    };\n";
  generate_lang_bindtests (
    fun f args optargs ->
      pr "    g.%s(" f;
      let needs_comma = ref false in
      List.iter (
        fun arg ->
          if !needs_comma then pr ", ";
          needs_comma := true;
          match arg with
          | CallString s -> pr "\"%s\"" s
          | CallOptString None -> pr "None"
          | CallOptString (Some s) -> pr "Some(\"%s\")" s
          | CallStringList xs ->
            pr "&vec![%s]"
              (String.concat ", " (List.map (sprintf "\"%s\"") xs))
          | CallInt i -> pr "%d" i
          | CallInt64 i -> pr "%Ldi64" i
          | CallBool b -> pr "%b" b
          | CallBuffer s ->
            let f = fun x -> sprintf "%d" (Char.code x) in
            pr "&[%s]"
              (String.concat ", " (List.map f (String.explode s)))
      ) args;
      if !needs_comma then pr ", ";
      (match optargs with
       | None -> pr "Default::default()"
       | Some optargs ->
         pr "%sOptArgs{" (Rust.snake2caml f);
         needs_comma := false;
         List.iter (
           fun optarg ->
             if !needs_comma then pr ", ";
             needs_comma := true;
             match optarg with
             | CallOBool (n, v) ->
               pr "%s: Some(%b)" n v
             | CallOInt (n, v) ->
               pr "%s: Some(%d)" n v
             | CallOInt64 (n, v) ->
               pr "%s: Some(%Ldi64)" n v
             | CallOString (n, v) ->
               pr "%s: Some(\"%s\")" n v
             | CallOStringList (n, xs) ->
               pr "%s: Some(&[%s])"
                 n (String.concat ", " (List.map (sprintf "\"%s\"") xs))
         ) optargs;
         if !needs_comma then pr ", ";
         pr ".. Default::default()}";
      );
      pr ").expect(\"failed to run\");\n";
  );
  pr "    println!(\"EOF\");\n";
  pr "}\n";

(* Language-independent bindings tests - we do it this way to
 * ensure there is parity in testing bindings across all languages.
 *)
and generate_lang_bindtests call =
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOBool ("obool", true);
           CallOInt ("oint", 1);
           CallOInt64 ("oint64", Int64.max_int)]);
  call "internal_test"
    [CallString "abc"; CallOptString None;
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOInt64 ("oint64", 1L);
           CallOString ("ostring", "string")]);
  call "internal_test"
    [CallString ""; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOBool ("obool", false);
           CallOInt64 ("oint64", Int64.min_int)]);
  call "internal_test"
    [CallString ""; CallOptString (Some "");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some []);
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"; "2"]; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool true;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt (-1); CallInt64 (-1L); CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt (-2); CallInt64 (-2L); CallString "123";CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt 1; CallInt64 1L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt 2; CallInt64 2L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt 4095; CallInt64 Int64.max_int; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList ["1"]; CallBool false;
     CallInt 0; CallInt64 Int64.min_int; CallString ""; CallString "";
     CallBuffer "abc\000abc"] None;
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOStringList ("ostringlist", [])]);
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOStringList ("ostringlist", ["optelem1"])]);
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOStringList ("ostringlist", ["optelem1"; "optelem2"])]);
  call "internal_test"
    [CallString "abc"; CallOptString (Some "def");
     CallStringList []; CallBool false;
     CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
     CallBuffer "abc\000abc"]
    (Some [CallOStringList ("ostringlist", ["optelem1"; "optelem2"; "optelem3"])]);

(* XXX Add here tests of the return and error functions. *)
