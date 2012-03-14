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
open Generator_c

let rec generate_bindtests () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"

static void
print_strings (char *const *argv)
{
  size_t argc;

  printf (\"[\");
  for (argc = 0; argv[argc] != NULL; ++argc) {
    if (argc > 0) printf (\", \");
    printf (\"\\\"%%s\\\"\", argv[argc]);
  }
  printf (\"]\\n\");
}

/* The test0 function prints its parameters to stdout. */
";

  let test0, tests =
    match test_functions with
    | [] -> assert false
    | test0 :: tests -> test0, tests in

  let () =
    let (name, (ret, args, optargs as style), _, _, _, _, _) = test0 in
    generate_prototype ~extern:false ~semicolon:false ~newline:true
      ~handle:"g" ~prefix:"guestfs__" ~optarg_proto:Argv name style;
    pr "{\n";
    List.iter (
      function
      | Pathname n
      | Device n | Dev_or_Path n
      | String n
      | FileIn n
      | FileOut n
      | Key n -> pr "  printf (\"%%s\\n\", %s);\n" n
      | BufferIn n ->
          pr "  {\n";
          pr "    size_t i;\n";
          pr "    for (i = 0; i < %s_size; ++i)\n" n;
          pr "      printf (\"<%%02x>\", %s[i]);\n" n;
          pr "    printf (\"\\n\");\n";
          pr "  }\n";
      | OptString n -> pr "  printf (\"%%s\\n\", %s ? %s : \"null\");\n" n n
      | StringList n | DeviceList n -> pr "  print_strings (%s);\n" n
      | Bool n -> pr "  printf (\"%%s\\n\", %s ? \"true\" : \"false\");\n" n
      | Int n -> pr "  printf (\"%%d\\n\", %s);\n" n
      | Int64 n -> pr "  printf (\"%%\" PRIi64 \"\\n\", %s);\n" n
      | Pointer _ -> assert false
    ) args;
    let check_optarg n printf_args =
      pr "  printf (\"%s: \");\n" n;
      pr "  if (optargs->bitmask & GUESTFS_TEST0_%s_BITMASK) {\n"
        (String.uppercase n);
      pr "    printf(%s);\n" printf_args;
      pr "  } else {\n";
      pr "    printf (\"unset\\n\");\n";
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
    ) optargs;
    pr "  /* Java changes stdout line buffering so we need this: */\n";
    pr "  fflush (stdout);\n";
    pr "  return 0;\n";
    pr "}\n";
    pr "\n" in

  List.iter (
    fun (name, (ret, args, _ as style), _, _, _, _, _) ->
      if String.sub name (String.length name - 3) 3 <> "err" then (
        pr "/* Test normal return. */\n";
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs__" name style;
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
             pr "    strs[i] = safe_malloc (g, 16);\n";
             pr "    snprintf (strs[i], 16, \"%%zu\", i);\n";
             pr "  }\n";
             pr "  strs[n] = NULL;\n";
             pr "  return strs;\n"
         | RStruct (_, typ) ->
             pr "  struct guestfs_%s *r;\n" typ;
             pr "  r = safe_calloc (g, sizeof *r, 1);\n";
             pr "  return r;\n"
         | RStructList (_, typ) ->
             pr "  struct guestfs_%s_list *r;\n" typ;
             pr "  uint32_t len;\n";
             pr "  if (sscanf (val, \"%%\" SCNu32, &len) != 1) {\n";
             pr "    error (g, \"%%s: expecting uint32 argument\", \"%s\");\n" name;
             pr "    return NULL;\n";
             pr "  }\n";
             pr "  r = safe_calloc (g, sizeof *r, 1);\n";
             pr "  r->len = len;\n";
             pr "  r->val = safe_calloc (g, r->len, sizeof *r->val);\n";
             pr "  for (size_t i = 0; i < r->len; i++) {\n";
             pr "    r->val[i].pv_size = i;\n";
             pr "  }\n";
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
             pr "    strs[i*2] = safe_malloc (g, 16);\n";
             pr "    strs[i*2+1] = safe_malloc (g, 16);\n";
             pr "    snprintf (strs[i*2], 16, \"%%zu\", i);\n";
             pr "    snprintf (strs[i*2+1], 16, \"%%zu\", i);\n";
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
          ~handle:"g" ~prefix:"guestfs__" name style;
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
  ) tests

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
        | CallOInt (n, v)     -> "~" ^ n ^ ":" ^ string_of_int v
        | CallOInt64 (n, v)   -> "~" ^ n ^ ":" ^ Int64.to_string v ^ "L"
        | CallOString (n, v)  -> "~" ^ n ^ ":\"" ^ v ^ "\""
      ) optargs
    )
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "  Guestfs.%s g %s;\n" f (mkargs args optargs)
  );

  pr "print_endline \"EOF\"\n"

and generate_perl_bindtests () =
  pr "#!/usr/bin/perl -w\n";
  generate_header HashStyle GPLv2plus;

  pr "\
use strict;

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
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> if b then "1" else "0"
        | CallBuffer s -> "\"" ^ c_quote s ^ "\""
      ) args
      @
      List.map (
        function
        | CallOBool (n, v)    -> "'" ^ n ^ "' => " ^ if v then "1" else "0"
        | CallOInt (n, v)     -> "'" ^ n ^ "' => " ^ string_of_int v
        | CallOInt64 (n, v)   -> "'" ^ n ^ "' => " ^ Int64.to_string v
        | CallOString (n, v)  -> "'" ^ n ^ "' => '" ^ v ^ "'"
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

g = guestfs.GuestFS ()
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
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
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
      ) optargs
    )
  in

  generate_lang_bindtests (
    fun f args optargs -> pr "g.%s (%s)\n" f (mkargs args optargs)
  );

  pr "print (\"EOF\")\n"

and generate_ruby_bindtests () =
  generate_header HashStyle GPLv2plus;

  pr "\
require 'guestfs'

g = Guestfs::create()
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
          "  put(\"" ^ n ^ "\", " ^ Int64.to_string v ^ "l);"
        | CallOString (n, v)  ->
          "  put(\"" ^ n ^ "\", \"" ^ v ^ "\");"
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
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> string_of_bool b
        | CallBuffer s ->
            "new byte[] { " ^ String.concat "," (
              map_chars (fun c -> string_of_int (Char.code c)) s
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
      "o = new Guestfs.Test0({" ^
      (
        String.concat ", " (
          List.map (
            function
            | CallOBool (n, v)    -> n ^ ": " ^ (if v then "true" else "false")
            | CallOInt (n, v)     -> n ^ ": " ^ (string_of_int v)
            | CallOInt64 (n, v)   -> n ^ ": " ^ Int64.to_string v
            | CallOString (n, v)  -> n ^ ": \"" ^ v ^ "\""
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

(* Language-independent bindings tests - we do it this way to
 * ensure there is parity in testing bindings across all languages.
 *)
and generate_lang_bindtests call =
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"]
               (Some [CallOBool ("obool", true); CallOInt ("oint", 1)]);
  call "test0" [CallString "abc"; CallOptString None;
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"]
               (Some [CallOInt64 ("oint64", 1L);
                      CallOString ("ostring", "string")]);
  call "test0" [CallString ""; CallOptString (Some "def");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"]
               (Some [CallOBool ("obool", false)]);
  call "test0" [CallString ""; CallOptString (Some "");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"]
                (Some []);
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"; "2"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool true;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt (-1); CallInt64 (-1L); CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt (-2); CallInt64 (-2L); CallString "123";CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 1; CallInt64 1L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 2; CallInt64 2L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 4095; CallInt64 4095L; CallString "123"; CallString "456";
                CallBuffer "abc\000abc"] None;
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString ""; CallString "";
                CallBuffer "abc\000abc"] None;

(* XXX Add here tests of the return and error functions. *)
