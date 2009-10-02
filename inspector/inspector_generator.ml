#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
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

(* This program generates language bindings for virt-inspector, so
 * you can use it from programs (other than Perl programs).
 *
 * At compile time, the bindings are generated from the file
 * [virt-inspector.rng], which is the RELAX NG schema that describes
 * the output of the [virt-inspector --xml] command.
 *
 * At run time, code using these bindings runs the external
 * [virt-inspector --xml] command, and parses the XML that this
 * generates into language-specific structures.
 *)

(* Unlike src/generator.ml, we allow ourselves to go wild here and use
 * a reasonable number of OCaml libraries.  NOTE TO DEVELOPERS: You
 * still have to detect the libraries in configure.ac and add them to
 * inspector/Makefile.am.
 *)
#load "unix.cma";;
#directory "+xml-light";;
#load "xml-light.cma";;

open Printf

module StringMap = Map.Make (String)

let failwithf fs = ksprintf failwith fs
let unique = let i = ref 0 in fun () -> incr i; !i

(* Check we're running from the right directory. *)
let () =
  if not (Sys.file_exists "HACKING") then (
    eprintf "You are probably running this from the wrong directory.\n";
    exit 1
  )

let input = "inspector/virt-inspector.rng"

(* Read the input file and parse it into internal structures.  This is
 * by no means a complete RELAX NG parser, but is just enough to be
 * able to parse the specific input file.
 *)
type rng =
  | Element of string * rng list	(* <element name=name/> *)
  | Attribute of string * rng list	(* <attribute name=name/> *)
  | Interleave of rng list		(* <interleave/> *)
  | ZeroOrMore of rng			(* <zeroOrMore/> *)
  | OneOrMore of rng			(* <oneOrMore/> *)
  | Optional of rng			(* <optional/> *)
  | Choice of string list		(* <choice><value/>*</choice> *)
  | Value of string			(* <value>str</value> *)
  | Text				(* <text/> *)

let rec string_of_rng = function
  | Element (name, xs) ->
      "Element (\"" ^ name ^ "\", (" ^ string_of_rng_list xs ^ "))"
  | Attribute (name, xs) ->
      "Attribute (\"" ^ name ^ "\", (" ^ string_of_rng_list xs ^ "))"
  | Interleave xs -> "Interleave (" ^ string_of_rng_list xs ^ ")"
  | ZeroOrMore rng -> "ZeroOrMore (" ^ string_of_rng rng ^ ")"
  | OneOrMore rng -> "OneOrMore (" ^ string_of_rng rng ^ ")"
  | Optional rng -> "Optional (" ^ string_of_rng rng ^ ")"
  | Choice values -> "Choice [" ^ String.concat ", " values ^ "]"
  | Value value -> "Value \"" ^ value ^ "\""
  | Text -> "Text"

and string_of_rng_list xs =
  String.concat ", " (List.map string_of_rng xs)

let rec parse_rng ?defines context = function
  | [] -> []
  | Xml.Element ("element", ["name", name], children) :: rest ->
      Element (name, parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("attribute", ["name", name], children) :: rest ->
      Attribute (name, parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("interleave", [], children) :: rest ->
      Interleave (parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("zeroOrMore", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> ZeroOrMore child :: parse_rng ?defines context rest
       | _ ->
	   failwithf "%s: <zeroOrMore> contains more than one child element"
	     context
      )
  | Xml.Element ("oneOrMore", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> OneOrMore child :: parse_rng ?defines context rest
       | _ ->
	   failwithf "%s: <oneOrMore> contains more than one child element"
	     context
      )
  | Xml.Element ("optional", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> Optional child :: parse_rng ?defines context rest
       | _ ->
	   failwithf "%s: <optional> contains more than one child element"
	     context
      )
  | Xml.Element ("choice", [], children) :: rest ->
      let values = List.map (
	function Xml.Element ("value", [], [Xml.PCData value]) -> value
	| _ ->
	    failwithf "%s: can't handle anything except <value> in <choice>"
	      context
      ) children in
      Choice values
      :: parse_rng ?defines context rest
  | Xml.Element ("value", [], [Xml.PCData value]) :: rest ->
      Value value :: parse_rng ?defines context rest
  | Xml.Element ("text", [], []) :: rest ->
      Text :: parse_rng ?defines context rest
  | Xml.Element ("ref", ["name", name], []) :: rest ->
      (* Look up the reference.  Because of limitations in this parser,
       * we can't handle arbitrarily nested <ref> yet.  You can only
       * use <ref> from inside <start>.
       *)
      (match defines with
       | None ->
	   failwithf "%s: contains <ref>, but no refs are defined yet" context
       | Some map ->
	   let rng = StringMap.find name map in
	   rng @ parse_rng ?defines context rest
      )
  | x :: _ ->
      failwithf "%s: can't handle '%s' in schema" context (Xml.to_string x)

let grammar =
  let xml = Xml.parse_file input in
  match xml with
  | Xml.Element ("grammar", _,
		 Xml.Element ("start", _, gram) :: defines) ->
      (* The <define/> elements are referenced in the <start> section,
       * so build a map of those first.
       *)
      let defines = List.fold_left (
	fun map ->
	  function Xml.Element ("define", ["name", name], defn) ->
	    StringMap.add name defn map
	  | _ ->
	      failwithf "%s: expected <define name=name/>" input
      ) StringMap.empty defines in
      let defines = StringMap.mapi parse_rng defines in

      (* Parse the <start> clause, passing the defines. *)
      parse_rng ~defines "<start>" gram
  | _ ->
      failwithf "%s: input is not <grammar><start/><define>*</grammar>" input

(* 'pr' prints to the current output file. *)
let chan = ref stdout
let pr fs = ksprintf (output_string !chan) fs

(* Generate a header block in a number of standard styles. *)
type comment_style = CStyle | HashStyle | OCamlStyle | HaskellStyle
type license = GPLv2 | LGPLv2

let generate_header comment license =
  let c = match comment with
    | CStyle ->     pr "/* "; " *"
    | HashStyle ->  pr "# ";  "#"
    | OCamlStyle -> pr "(* "; " *"
    | HaskellStyle -> pr "{- "; "  " in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED BY 'inspector/inspector_generator.ml'\n" c;
  pr "%s FROM THE RELAX NG SCHEMA AT '%s'.\n" c input;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) 2009 Red Hat Inc.\n" c;
  pr "%s\n" c;
  (match license with
   | GPLv2 ->
       pr "%s This program is free software; you can redistribute it and/or modify\n" c;
       pr "%s it under the terms of the GNU General Public License as published by\n" c;
       pr "%s the Free Software Foundation; either version 2 of the License, or\n" c;
       pr "%s (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This program is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n" c;
       pr "%s GNU General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU General Public License along\n" c;
       pr "%s with this program; if not, write to the Free Software Foundation, Inc.,\n" c;
       pr "%s 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.\n" c;

   | LGPLv2 ->
       pr "%s This library is free software; you can redistribute it and/or\n" c;
       pr "%s modify it under the terms of the GNU Lesser General Public\n" c;
       pr "%s License as published by the Free Software Foundation; either\n" c;
       pr "%s version 2 of the License, or (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This library is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU\n" c;
       pr "%s Lesser General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU Lesser General Public\n" c;
       pr "%s License along with this library; if not, write to the Free Software\n" c;
       pr "%s Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA\n" c;
  );
  (match comment with
   | CStyle -> pr " */\n"
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
   | HaskellStyle -> pr "-}\n"
  );
  pr "\n"

let name_of_field = function
  | Element (name, _) | Attribute (name, _)
  | ZeroOrMore (Element (name, _))
  | OneOrMore (Element (name, _))
  | Optional (Element (name, _)) -> name
  | Optional (Attribute (name, _)) -> name
  | Text -> (* an unnamed field in an element *)
      "data"
  | rng ->
      failwithf "name_of_field failed at: %s" (string_of_rng rng)

(* At the moment this function only generates OCaml types.  However we
 * should parameterize it later so it can generate types/structs in a
 * variety of languages.
 *)
let generate_types xs =
  (* A simple type is one that can be printed out directly, eg.
   * "string option".  A complex type is one which has a name and has
   * to be defined via another toplevel definition, eg. a struct.
   *
   * generate_type generates code for either simple or complex types.
   * In the simple case, it returns the string ("string option").  In
   * the complex case, it returns the name ("mountpoint").  In the
   * complex case it has to print out the definition before returning,
   * so it should only be called when we are at the beginning of a
   * new line (BOL context).
   *)
  let rec generate_type = function
    | Text ->				(* string *)
	"string", true
    | Choice values ->			(* [`val1|`val2|...] *)
	"[" ^ String.concat "|" (List.map ((^)"`") values) ^ "]", true
    | ZeroOrMore rng ->			(* <rng> list *)
	let t, is_simple = generate_type rng in
	t ^ " list (* 0 or more *)", is_simple
    | OneOrMore rng ->			(* <rng> list *)
	let t, is_simple = generate_type rng in
	t ^ " list (* 1 or more *)", is_simple
	                                (* virt-inspector hack: bool *)
    | Optional (Attribute (name, [Value "1"])) ->
	"bool", true
    | Optional rng ->			(* <rng> list *)
	let t, is_simple = generate_type rng in
	t ^ " option", is_simple
                                        (* type name = { fields ... } *)
    | Element (name, fields) when is_attrs_interleave fields ->
	generate_type_struct name (get_attrs_interleave fields)
    | Element (name, [field])		(* type name = field *)
    | Attribute (name, [field]) ->
	let t, is_simple = generate_type field in
	if is_simple then (t, true)
	else (
	  pr "type %s = %s\n" name t;
	  name, false
	)
    | Element (name, fields) ->	      (* type name = { fields ... } *)
	generate_type_struct name fields
    | rng ->
	failwithf "generate_type failed at: %s" (string_of_rng rng)

  and is_attrs_interleave = function
    | [Interleave _] -> true
    | Attribute _ :: fields -> is_attrs_interleave fields
    | Optional (Attribute _) :: fields -> is_attrs_interleave fields
    | _ -> false

  and get_attrs_interleave = function
    | [Interleave fields] -> fields
    | ((Attribute _) as field) :: fields
    | ((Optional (Attribute _)) as field) :: fields ->
	field :: get_attrs_interleave fields
    | _ -> assert false

  and generate_types xs =
    List.iter (fun x -> ignore (generate_type x)) xs

  and generate_type_struct name fields =
    (* Calculate the types of the fields first.  We have to do this
     * before printing anything so we are still in BOL context.
     *)
    let types = List.map fst (List.map generate_type fields) in

    (* Special case of a struct containing just a string and another
     * field.  Turn it into an assoc list.
     *)
    match types with
    | ["string"; other] ->
	let fname1, fname2 =
	  match fields with
	  | [f1; f2] -> name_of_field f1, name_of_field f2
	  | _ -> assert false in
	pr "type %s = string * %s (* %s -> %s *)\n" name other fname1 fname2;
	name, false

    | types ->
	pr "type %s = {\n" name;
	List.iter (
	  fun (field, ftype) ->
	    let fname = name_of_field field in
	    pr "  %s_%s : %s;\n" name fname ftype
	) (List.combine fields types);
	pr "}\n";
	(* Return the name of this type, and
	 * false because it's not a simple type.
	 *)
	name, false
  in

  generate_types xs

let generate_parsers xs =
  (* As for generate_type above, generate_parser makes a parser for
   * some type, and returns the name of the parser it has generated.
   * Because it (may) need to print something, it should always be
   * called in BOL context.
   *)
  let rec generate_parser = function
    | Text ->				(* string *)
	"string_child_or_empty"
    | Choice values ->			(* [`val1|`val2|...] *)
	sprintf "(fun x -> match Xml.pcdata (first_child x) with %s | str -> failwith (\"unexpected field value: \" ^ str))"
	  (String.concat "|"
	     (List.map (fun v -> sprintf "%S -> `%s" v v) values))
    | ZeroOrMore rng ->			(* <rng> list *)
	let pa = generate_parser rng in
	sprintf "(fun x -> List.map %s (Xml.children x))" pa
    | OneOrMore rng ->			(* <rng> list *)
	let pa = generate_parser rng in
	sprintf "(fun x -> List.map %s (Xml.children x))" pa
	                                (* virt-inspector hack: bool *)
    | Optional (Attribute (name, [Value "1"])) ->
	sprintf "(fun x -> try ignore (Xml.attrib x %S); true with Xml.No_attribute _ -> false)" name
    | Optional rng ->			(* <rng> list *)
	let pa = generate_parser rng in
	sprintf "(function None -> None | Some x -> Some (%s x))" pa
                                        (* type name = { fields ... } *)
    | Element (name, fields) when is_attrs_interleave fields ->
	generate_parser_struct name (get_attrs_interleave fields)
    | Element (name, [field]) ->	(* type name = field *)
	let pa = generate_parser field in
	let parser_name = sprintf "parse_%s_%d" name (unique ()) in
	pr "let %s =\n" parser_name;
	pr "  %s\n" pa;
	pr "let parse_%s = %s\n" name parser_name;
	parser_name
    | Attribute (name, [field]) ->
	let pa = generate_parser field in
	let parser_name = sprintf "parse_%s_%d" name (unique ()) in
	pr "let %s =\n" parser_name;
	pr "  %s\n" pa;
	pr "let parse_%s = %s\n" name parser_name;
	parser_name
    | Element (name, fields) ->	      (* type name = { fields ... } *)
	generate_parser_struct name ([], fields)
    | rng ->
	failwithf "generate_parser failed at: %s" (string_of_rng rng)

  and is_attrs_interleave = function
    | [Interleave _] -> true
    | Attribute _ :: fields -> is_attrs_interleave fields
    | Optional (Attribute _) :: fields -> is_attrs_interleave fields
    | _ -> false

  and get_attrs_interleave = function
    | [Interleave fields] -> [], fields
    | ((Attribute _) as field) :: fields
    | ((Optional (Attribute _)) as field) :: fields ->
	let attrs, interleaves = get_attrs_interleave fields in
	(field :: attrs), interleaves
    | _ -> assert false

  and generate_parsers xs =
    List.iter (fun x -> ignore (generate_parser x)) xs

  and generate_parser_struct name (attrs, interleaves) =
    (* Generate parsers for the fields first.  We have to do this
     * before printing anything so we are still in BOL context.
     *)
    let fields = attrs @ interleaves in
    let pas = List.map generate_parser fields in

    (* Generate an intermediate tuple from all the fields first.
     * If the type is just a string + another field, then we will
     * return this directly, otherwise it is turned into a record.
     *
     * RELAX NG note: This code treats <interleave> and plain lists of
     * fields the same.  In other words, it doesn't bother enforcing
     * any ordering of fields in the XML.
     *)
    pr "let parse_%s x =\n" name;
    pr "  let t = (\n    ";
    let comma = ref false in
    List.iter (
      fun x ->
	if !comma then pr ",\n    ";
	comma := true;
	match x with
	| Optional (Attribute (fname, [field])), pa ->
	    pr "%s x" pa
	| Optional (Element (fname, [field])), pa ->
	    pr "%s (optional_child %S x)" pa fname
	| Attribute (fname, [Text]), _ ->
	    pr "attribute %S x" fname
	| (ZeroOrMore _ | OneOrMore _), pa ->
	    pr "%s x" pa
	| Text, pa ->
	    pr "%s x" pa
	| (field, pa) ->
	    let fname = name_of_field field in
	    pr "%s (child %S x)" pa fname
    ) (List.combine fields pas);
    pr "\n  ) in\n";

    (match fields with
     | [Element (_, [Text]) | Attribute (_, [Text]); _] ->
	 pr "  t\n"

     | _ ->
	 pr "  (Obj.magic t : %s)\n" name
(*
	 List.iter (
	   function
	   | (Optional (Attribute (fname, [field])), pa) ->
	       pr "  %s_%s =\n" name fname;
	       pr "    %s x;\n" pa
	   | (Optional (Element (fname, [field])), pa) ->
	       pr "  %s_%s =\n" name fname;
	       pr "    (let x = optional_child %S x in\n" fname;
	       pr "     %s x);\n" pa
	   | (field, pa) ->
	       let fname = name_of_field field in
	       pr "  %s_%s =\n" name fname;
	       pr "    (let x = child %S x in\n" fname;
	       pr "     %s x);\n" pa
	 ) (List.combine fields pas);
	 pr "}\n"
*)
    );
    sprintf "parse_%s" name
  in

  generate_parsers xs

(* Generate ocaml/guestfs_inspector.mli. *)
let generate_ocaml_mli () =
  generate_header OCamlStyle LGPLv2;

  pr "\
(** This is an OCaml language binding to the external [virt-inspector]
    program.

    For more information, please read the man page [virt-inspector(1)].
*)

";

  generate_types grammar;
  pr "(** The nested information returned from the {!inspect} function. *)\n";
  pr "\n";

  pr "\
val inspect : ?connect:string -> ?xml:string -> string list -> operatingsystems
(** To inspect a libvirt domain called [name], pass a singleton
    list: [inspect [name]].  When using libvirt only, you may
    optionally pass a libvirt URI using [inspect ~connect:uri ...].

    To inspect a disk image or images, pass a list of the filenames
    of the disk images: [inspect filenames]

    This function inspects the given guest or disk images and
    returns a list of operating system(s) found and a large amount
    of information about them.  In the vast majority of cases,
    a virtual machine only contains a single operating system.

    If the optional [~xml] parameter is given, then this function
    skips running the external virt-inspector program and just
    parses the given XML directly (which is expected to be XML
    produced from a previous run of virt-inspector).  The list of
    names and connect URI are ignored in this case.

    This function can throw a wide variety of exceptions, for example
    if the external virt-inspector program cannot be found, or if
    it doesn't generate valid XML.
*)
"

(* Generate ocaml/guestfs_inspector.ml. *)
let generate_ocaml_ml () =
  generate_header OCamlStyle LGPLv2;

  pr "open Unix\n";
  pr "\n";

  generate_types grammar;
  pr "\n";

  pr "\
(* Misc functions which are used by the parser code below. *)
let first_child = function
  | Xml.Element (_, _, c::_) -> c
  | Xml.Element (name, _, []) ->
      failwith (\"expected <\" ^ name ^ \"/> to have a child node\")
  | Xml.PCData str ->
      failwith (\"expected XML tag, but read PCDATA '\" ^ str ^ \"' instead\")

let string_child_or_empty = function
  | Xml.Element (_, _, [Xml.PCData s]) -> s
  | Xml.Element (_, _, []) -> \"\"
  | Xml.Element (x, _, _) ->
      failwith (\"expected XML tag with a single PCDATA child, but got \" ^
                x ^ \" instead\")
  | Xml.PCData str ->
      failwith (\"expected XML tag, but read PCDATA '\" ^ str ^ \"' instead\")

let optional_child name xml =
  let children = Xml.children xml in
  try
    Some (List.find (function
                     | Xml.Element (n, _, _) when n = name -> true
                     | _ -> false) children)
  with
    Not_found -> None

let child name xml =
  match optional_child name xml with
  | Some c -> c
  | None ->
      failwith (\"mandatory field <\" ^ name ^ \"/> missing in XML output\")

let attribute name xml =
  try Xml.attrib xml name
  with Xml.No_attribute _ ->
    failwith (\"mandatory attribute \" ^ name ^ \" missing in XML output\")

";

  generate_parsers grammar;
  pr "\n";

  pr "\
(* Run external virt-inspector, then use parser to parse the XML. *)
let inspect ?connect ?xml names =
  let xml =
    match xml with
    | None ->
        if names = [] then invalid_arg \"inspect: no names given\";
        let cmd = [ \"virt-inspector\"; \"--xml\" ] @
          (match connect with None -> [] | Some uri -> [ \"--connect\"; uri ]) @
          names in
        let cmd = List.map Filename.quote cmd in
        let cmd = String.concat \" \" cmd in
        let chan = open_process_in cmd in
        let xml = Xml.parse_in chan in
        (match close_process_in chan with
         | WEXITED 0 -> ()
         | WEXITED _ -> failwith \"external virt-inspector command failed\"
         | WSIGNALED i | WSTOPPED i ->
             failwith (\"external virt-inspector command died or stopped on sig \" ^
                       string_of_int i)
        );
        xml
    | Some doc ->
        Xml.parse_string doc in
  parse_operatingsystems xml
"

let files_equal n1 n2 =
  let cmd = sprintf "cmp -s %s %s" (Filename.quote n1) (Filename.quote n2) in
  match Sys.command cmd with
  | 0 -> true
  | 1 -> false
  | i -> failwithf "%s: failed with error code %d" cmd i

let output_to filename =
  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  let close () =
    close_out !chan;
    chan := stdout;

    (* Is the new file different from the current file? *)
    if Sys.file_exists filename && files_equal filename filename_new then
      Unix.unlink filename_new		(* same, so skip it *)
    else (
      (* different, overwrite old one *)
      (try Unix.chmod filename 0o644 with Unix.Unix_error _ -> ());
      Unix.rename filename_new filename;
      Unix.chmod filename 0o444;
      printf "written %s\n%!" filename;
    )
  in
  close

(* Output. *)
let () =
  let close = output_to "ocaml/guestfs_inspector.mli" in
  generate_ocaml_mli ();
  close ();

  let close = output_to "ocaml/guestfs_inspector.ml" in
  generate_ocaml_ml ();
  close ()
