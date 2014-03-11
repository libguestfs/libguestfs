(* virt-sparsify
 * Copyright (C) 2011-2014 Red Hat Inc.
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

open Unix
open Printf

open Common_gettext.Gettext

module G = Guestfs

open Common_utils
open Cmdline

let () = Random.self_init ()

let rec main () =
  let indisk, debug_gc, format, ignores, machine_readable,
    quiet, verbose, trace, zeroes, mode =
    parse_cmdline () in

  (match mode with
  | Mode_copying (outdisk, check_tmpdir, compress, convert, option) ->
    Copying.run indisk outdisk check_tmpdir compress convert
      format ignores machine_readable option quiet verbose trace zeroes
  | Mode_in_place ->
    In_place.run indisk format ignores machine_readable
      quiet verbose trace zeroes
  );

  if debug_gc then
    Gc.compact ()

let () =
  try main ()
  with
  | Unix.Unix_error (code, fname, "") -> (* from a syscall *)
    eprintf (f_"%s: error: %s: %s\n") prog fname (Unix.error_message code);
    exit 1
  | Unix.Unix_error (code, fname, param) -> (* from a syscall *)
    eprintf (f_"%s: error: %s: %s: %s\n") prog fname (Unix.error_message code)
      param;
    exit 1
  | G.Error msg ->                      (* from libguestfs *)
    eprintf (f_"%s: libguestfs error: %s\n") prog msg;
    exit 1
  | Failure msg ->                      (* from failwith/failwithf *)
    eprintf (f_"%s: failure: %s\n") prog msg;
    exit 1
  | Invalid_argument msg ->             (* probably should never happen *)
    eprintf (f_"%s: internal error: invalid argument: %s\n") prog msg;
    exit 1
  | Assert_failure (file, line, char) -> (* should never happen *)
    eprintf (f_"%s: internal error: assertion failed at %s, line %d, char %d\n") prog file line char;
    exit 1
  | Not_found ->                        (* should never happen *)
    eprintf (f_"%s: internal error: Not_found exception was thrown\n") prog;
    exit 1
  | exn ->                              (* something not matched above *)
    eprintf (f_"%s: exception: %s\n") prog (Printexc.to_string exn);
    exit 1
