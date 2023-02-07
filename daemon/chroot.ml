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
open Unix

open Std_utils
open Unix_utils

type t = {
  name : string;
  chroot : string;
}

let create ?(name = "<unnamed>") ?(chroot = Sysroot.sysroot ()) () =
  { name = name; chroot = chroot }

let f t func arg =
  if verbose () then
    eprintf "chroot: %s: running '%s'\n%!" t.chroot t.name;

  let rfd, wfd = pipe () in

  let pid = fork () in
  if pid = 0 then (
    (* Child. *)
    close rfd;

    chdir t.chroot;
    chroot t.chroot;

    let ret =
      try Either (func arg)
      with exn -> Or exn in

    try
      let chan = out_channel_of_descr wfd in
      output_value chan ret;
      Pervasives.flush chan;
      Exit._exit 0
    with
      exn ->
        prerr_endline (Printexc.to_string exn);
        Exit._exit 1
  );

  (* Parent. *)
  close wfd;

  let chan = in_channel_of_descr rfd in
  let ret = input_value chan in
  close_in chan;

  let _, status = waitpid [] pid in
  (match status with
   | WEXITED 0 -> ()
   | WEXITED i ->
      close rfd;
      failwithf "chroot ‘%s’ exited with non-zero error %d" t.name i
   | WSIGNALED i ->
      close rfd;
      failwithf "chroot ‘%s’ killed by signal %d" t.name i
   | WSTOPPED i ->
      close rfd;
      failwithf "chroot ‘%s’ stopped by signal %d" t.name i
  );

  match ret with
  | Either ret -> ret
  | Or exn -> raise exn
