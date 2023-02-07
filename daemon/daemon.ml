(* guestfs-inspection
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Printf

(* When guestfsd starts up, early on (after parsing the command line
 * but not much else), it calls 'caml_startup' which runs all
 * initialization code in the OCaml modules, including this one.
 *
 * Therefore this is where we can place OCaml initialization code
 * for the daemon.
 *)
let () =
  (* Connect the guestfsd [-v] (verbose) flag into 'verbose ()'
   * used in OCaml code to print debugging messages.
   *)
  if Utils.get_verbose_flag () then (
    Std_utils.set_verbose ();
    eprintf "OCaml daemon loaded\n%!"
  );

  (* Register the callbacks which are used to call OCaml code from C. *)
  Callbacks.init_callbacks ()
