(* libguestfs OCaml tests
 * Copyright (C) 2026 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* Test string list passing through guestfs_int_ocaml_strings_val.
 * Exercises the C binding code that copies OCaml string arrays
 * to C char** arrays using strdup.
 *)

let () =
  let g = new Guestfs.guestfs () in

  (* Test with a simple ASCII string list. *)
  g#internal_test "str" (Some "optstr") [| "a"; "b"; "c" |]
    false 0 0L "/dev/null" "/dev/null" "buf";

  (* Test with an empty string list. *)
  g#internal_test "str" (Some "optstr") [||]
    false 0 0L "/dev/null" "/dev/null" "buf";

  (* Test with a large string list to exercise cleanup paths. *)
  let big = Array.init 1000 (fun i -> Printf.sprintf "string_%d" i) in
  g#internal_test "str" (Some "optstr") big
    false 0 0L "/dev/null" "/dev/null" "buf";

  (* Test with Unicode strings. *)
  g#internal_test "str" (Some "optstr") [| "\xc3\xa9"; "\xc3\xb1"; "\xe2\x98\x83" |]
    false 0 0L "/dev/null" "/dev/null" "buf";

  g#close ()

let () = Gc.compact ()
