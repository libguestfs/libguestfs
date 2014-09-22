(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(* Functions for making files and directories as another user. *)

open Unix
open Printf

open Common_gettext.Gettext

open Utils

type t = {
  uid : int option;
  gid : int option;
}

let create ?uid ?gid () = { uid = uid; gid = gid }

(* Call _exit directly, ie. do not run OCaml atexit handlers. *)
external _exit : int -> unit = "v2v_exit" "noalloc"

let with_fork { uid = uid; gid = gid } f =
  let pid = fork () in
  if pid = 0 then ( (* child *)
    (match gid with None -> () | Some gid -> setgid gid);
    (match uid with None -> () | Some uid -> setuid uid);
    (try f ()
     with exn ->
       eprintf "%s: KVM uid wrapper: %s\n%!" prog (Printexc.to_string exn);
       _exit 1
    );
    _exit 0
  );
  (* parent *)
  let _, status = waitpid [] pid in
  match status with
  | WEXITED 0 -> ()
  | WEXITED i ->
    error (f_"subprocess exited with non-zero error code %d") i
  | WSIGNALED i | WSTOPPED i ->
    error (f_"subprocess signalled or stopped by signal %d") i

let mkdir t path perm =
  with_fork t (fun () -> mkdir path perm)

let rmdir t path =
  with_fork t (fun () -> rmdir path)

let output t path f =
  with_fork t (
    fun () ->
      let chan = open_out path in
      f chan;
      close_out chan
  )

let make_file t path content =
  output t path (fun chan -> output_string chan content)

let unlink t path =
  with_fork t (fun () -> unlink path)

let func t f = with_fork t f

let command t cmd =
  with_fork t (
    fun () ->
      let r = Sys.command cmd in
      if r <> 0 then failwith "external command failed"
  )
