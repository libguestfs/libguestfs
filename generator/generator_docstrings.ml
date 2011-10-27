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

open Unix
open Printf

open Generator_types
open Generator_utils
open Generator_pr

(* Handling for function flags. *)
let progress_message =
  "This long-running command can generate progress notification messages
so that the caller can display a progress bar or indicator.
To receive these messages, the caller must register a progress
event callback.  See L<guestfs(3)/GUESTFS_EVENT_PROGRESS>."

let protocol_limit_warning =
  "Because of the message protocol, there is a transfer limit
of somewhere between 2MB and 4MB.  See L<guestfs(3)/PROTOCOL LIMITS>."

let deprecation_notice ?(prefix = "") flags =
  try
    let alt =
      find_map (function DeprecatedBy str -> Some str | _ -> None) flags in
    let txt =
      sprintf "I<This function is deprecated.>
In new code, use the L</%s%s> call instead.

Deprecated functions will not be removed from the API, but the
fact that they are deprecated indicates that there are problems
with correct use of these functions." prefix alt in
    Some txt
  with
    Not_found -> None

let copyright_years =
  let this_year = 1900 + (localtime (time ())).tm_year in
  if this_year > 2009 then sprintf "2009-%04d" this_year else "2009"

(* Generate a header block in a number of standard styles. *)
type comment_style =
    CStyle | CPlusPlusStyle | HashStyle | OCamlStyle | HaskellStyle
  | ErlangStyle
type license = GPLv2plus | LGPLv2plus

let generate_header ?(extra_inputs = []) comment license =
  let inputs = "generator/generator_*.ml" :: extra_inputs in
  let c = match comment with
    | CStyle ->         pr "/* "; " *"
    | CPlusPlusStyle -> pr "// "; "//"
    | HashStyle ->      pr "# ";  "#"
    | OCamlStyle ->     pr "(* "; " *"
    | HaskellStyle ->   pr "{- "; "  "
    | ErlangStyle ->    pr "%% "; "% " in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED FROM:\n" c;
  List.iter (pr "%s   %s\n" c) inputs;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) %s Red Hat Inc.\n" c copyright_years;
  pr "%s\n" c;
  (match license with
   | GPLv2plus ->
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

   | LGPLv2plus ->
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
   | CPlusPlusStyle
   | ErlangStyle
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
   | HaskellStyle -> pr "-}\n"
  );
  pr "\n"
