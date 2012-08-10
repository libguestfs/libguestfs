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

open Generator_types
open Generator_utils
open Generator_actions

(* Check function names etc. for consistency. *)
let () =
  let contains_uppercase str =
    let len = String.length str in
    let rec loop i =
      if i >= len then false
      else (
        let c = str.[i] in
        if c >= 'A' && c <= 'Z' then true
        else loop (i+1)
      )
    in
    loop 0
  in

  (* Check function names. *)
  List.iter (
    fun (name, _, _, _, _, _, _) ->
      if String.length name >= 7 && String.sub name 0 7 = "guestfs" then
        failwithf "function name %s does not need 'guestfs' prefix" name;
      if name = "" then
        failwithf "function name is empty";
      if name.[0] < 'a' || name.[0] > 'z' then
        failwithf "function name %s must start with lowercase a-z" name;
      if String.contains name '-' then
        failwithf "function name %s should not contain '-', use '_' instead."
          name
  ) (all_functions @ fish_commands);

  (* Check function parameter/return names. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      let check_arg_ret_name n =
        if contains_uppercase n then
          failwithf "%s param/ret %s should not contain uppercase chars"
            name n;
        if String.contains n '-' || String.contains n '_' then
          failwithf "%s param/ret %s should not contain '-' or '_'"
            name n;
        if n = "value" then
          failwithf "%s has a param/ret called 'value', which causes conflicts in the OCaml bindings, use something like 'val' or a more descriptive name" name;
        if n = "int" || n = "char" || n = "short" || n = "long" then
          failwithf "%s has a param/ret which conflicts with a C type (eg. 'int', 'char' etc.)" name;
        if n = "i" || n = "n" then
          failwithf "%s has a param/ret called 'i' or 'n', which will cause some conflicts in the generated code" name;
        if n = "argv" || n = "args" then
          failwithf "%s has a param/ret called 'argv' or 'args', which will cause some conflicts in the generated code" name;

        (* List Haskell, OCaml, C++ and C keywords here.
         * http://www.haskell.org/haskellwiki/Keywords
         * http://caml.inria.fr/pub/docs/manual-ocaml/lex.html#operator-char
         * http://en.wikipedia.org/wiki/C_syntax#Reserved_keywords
         * Formatted via: cat c haskell ocaml|sort -u|grep -vE '_|^val$' \
         *   |perl -pe 's/(.+)/"$1";/'|fmt -70
         * Omitting _-containing words, since they're handled above.
         * Omitting the OCaml reserved word, "val", is ok,
         * and saves us from renaming several parameters.
         *)
        let reserved = [
          "and"; "as"; "asr"; "assert"; "auto"; "begin"; "break"; "case";
          "char"; "class"; "const"; "constraint"; "continue"; "data";
          "default"; "delete"; "deriving"; "do"; "done"; "double"; "downto";
          "else"; "end"; "enum"; "exception"; "extern"; "external"; "false";
          "float"; "for"; "forall"; "foreign"; "fun"; "function"; "functor";
          "goto"; "hiding"; "if"; "import"; "in"; "include"; "infix"; "infixl";
          "infixr"; "inherit"; "initializer"; "inline"; "instance"; "int";
          "interface";
          "land"; "lazy"; "let"; "long"; "lor"; "lsl"; "lsr"; "lxor";
          "match"; "mdo"; "method"; "mod"; "module"; "mutable"; "new";
          "newtype"; "object"; "of"; "open"; "or"; "private"; "qualified";
          "rec"; "register"; "restrict"; "return"; "short"; "sig"; "signed";
          "sizeof"; "static"; "struct"; "switch"; "then"; "to"; "true"; "try";
          "template"; "type"; "typedef"; "union"; "unsigned"; "virtual"; "void";
          "volatile"; "when"; "where"; "while";
          ] in
        if List.mem n reserved then
          failwithf "%s has param/ret using reserved word %s" name n;
      in

      let ret, args, optargs = style in

      (match ret with
       | RErr -> ()
       | RInt n | RInt64 n | RBool n
       | RConstString n | RConstOptString n | RString n
       | RStringList n | RStruct (n, _) | RStructList (n, _)
       | RHashtable n | RBufferOut n ->
           check_arg_ret_name n
      );
      List.iter (fun arg -> check_arg_ret_name (name_of_argt arg)) args;
      List.iter (fun arg -> check_arg_ret_name (name_of_optargt arg)) optargs;
  ) all_functions;

  (* Maximum of 63 optargs permitted. *)
  List.iter (
    fun (name, (_, _, optargs), _, _, _, _, _) ->
      if List.length optargs > 63 then
        failwithf "maximum of 63 optional args allowed for %s" name;
  ) all_functions;

  (* Some parameter types not supported for daemon functions. *)
  List.iter (
    fun (name, (_, args, _), _, _, _, _, _) ->
      let check_arg_type = function
        | Pointer _ ->
            failwithf "Pointer is not supported for daemon function %s."
              name
        | _ -> ()
      in
      List.iter check_arg_type args;
  ) daemon_functions;

  (* Check short descriptions. *)
  List.iter (
    fun (name, _, _, _, _, shortdesc, _) ->
      if shortdesc.[0] <> Char.lowercase shortdesc.[0] then
        failwithf "short description of %s should begin with lowercase." name;
      let c = shortdesc.[String.length shortdesc-1] in
      if c = '\n' || c = '.' then
        failwithf "short description of %s should not end with . or \\n." name
  ) (all_functions @ fish_commands);

  (* Check long descriptions. *)
  List.iter (
    fun (name, _, _, _, _, _, longdesc) ->
      if longdesc.[String.length longdesc-1] = '\n' then
        failwithf "long description of %s should not end with \\n." name
  ) (all_functions @ fish_commands);

  (* Check proc_nrs. *)
  List.iter (
    fun (name, _, proc_nr, _, _, _, _) ->
      if proc_nr <= 0 then
        failwithf "daemon function %s should have proc_nr > 0" name
  ) daemon_functions;

  List.iter (
    fun (name, _, proc_nr, _, _, _, _) ->
      if proc_nr <> -1 then
        failwithf "non-daemon function %s should have proc_nr -1" name
  ) non_daemon_functions;

  let proc_nrs =
    List.map (fun (name, _, proc_nr, _, _, _, _) -> name, proc_nr)
      daemon_functions in
  let proc_nrs =
    List.sort (fun (_,nr1) (_,nr2) -> compare nr1 nr2) proc_nrs in
  let rec loop = function
    | [] -> ()
    | [_] -> ()
    | (name1,nr1) :: ((name2,nr2) :: _ as rest) when nr1 < nr2 ->
        loop rest
    | (name1,nr1) :: (name2,nr2) :: _ ->
        failwithf "%s and %s have conflicting procedure numbers (%d, %d)"
          name1 name2 nr1 nr2
  in
  loop proc_nrs;

  (* Check flags. *)
  List.iter (
    fun (name, (ret, _, _), _, flags, _, _, _) ->
      List.iter (
        function
        | ProtocolLimitWarning
        | FishOutput _
        | NotInFish
        | NotInDocs
        | ConfigOnly
        | Progress -> ()
        | FishAlias n ->
            if contains_uppercase n then
              failwithf "%s: guestfish alias %s should not contain uppercase chars" name n;
            if String.contains n '_' then
              failwithf "%s: guestfish alias %s should not contain '_'" name n
        | DeprecatedBy n ->
            (* 'n' must be a cross-ref to the name of another action. *)
            if not (List.exists (
                      function
                      | (n', _, _, _, _, _, _) when n = n' -> true
                      | _ -> false
                    ) all_functions) then
              failwithf "%s: DeprecatedBy flag must be cross-reference to another action" name
        | Optional n ->
            if contains_uppercase n then
              failwithf "%s: Optional group name %s should not contain uppercase chars" name n;
            if String.contains n '-' || String.contains n '_' then
              failwithf "%s: Optional group name %s should not contain '-' or '_'" name n
        | CamelName n ->
            if not (contains_uppercase n) then
              failwithf "%s: camel case name must contains uppercase characters" name n;
            if String.contains n '_' then
              failwithf "%s: camel case name must not contain '_'" name n;
        | Cancellable ->
          (match ret with
          | RConstOptString n ->
            failwithf "%s: Cancellable function cannot return RConstOptString"
                      name
          | _ -> ())
      ) flags
  ) (all_functions @ fish_commands);

  (* ConfigOnly should only be specified on non_daemon_functions. *)
  List.iter (
    fun (name, (_, _, _), _, flags, _, _, _) ->
      if List.mem ConfigOnly flags then
        failwithf "%s cannot have ConfigOnly flag" name
  ) (daemon_functions @ fish_commands);

  (* Check tests. *)
  List.iter (
    function
      (* Ignore functions that have no tests.  We generate a
       * warning when the user does 'make check' instead.
       *)
    | name, _, _, _, [], _, _ -> ()
    | name, _, _, _, tests, _, _ ->
        let funcs =
          List.map (
            fun (_, _, test) ->
              match seq_of_test test with
              | [] ->
                  failwithf "%s has a test containing an empty sequence" name
              | cmds -> List.map List.hd cmds
          ) tests in
        let funcs = List.flatten funcs in

        let tested = List.mem name funcs in

        if not tested then
          failwithf "function %s has tests but does not test itself" name
  ) all_functions
