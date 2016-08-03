(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

open Common_utils
open Common_gettext.Gettext

open Utils

type t = {
  uid : int option;
  gid : int option;
}

let create ?uid ?gid () = { uid = uid; gid = gid }

let with_fork { uid = uid; gid = gid } name f =
  let pid = fork () in

  if pid = 0 then (
    (* Child. *)
    may setgid gid;
    may setuid uid;
    (try f ()
     with exn ->
       eprintf "%s: changeuid: %s: %s\n%!" prog name (Printexc.to_string exn);
       Exit._exit 1
    );
    Exit._exit 0
  );

  (* Parent. *)
  let _, status = waitpid [] pid in
  match status with
  | WEXITED 0 -> ()
  | WEXITED i ->
    error (f_"subprocess exited with non-zero error code %d") i
  | WSIGNALED i | WSTOPPED i ->
    error (f_"subprocess signalled or stopped by signal %d") i

let mkdir t path perm =
  with_fork t (sprintf "mkdir: %s" path) (fun () -> mkdir path perm)

let rmdir t path =
  with_fork t (sprintf "rmdir: %s" path) (fun () -> rmdir path)

let output t path f =
  with_fork t path (
    fun () ->
      let chan = open_out path in
      f chan;
      close_out chan
  )

let make_file t path content =
  output t path (fun chan -> output_string chan content)

let unlink t path =
  with_fork t (sprintf "unlink: %s" path) (fun () -> unlink path)

let func t = with_fork t "func"

let command t cmd =
  with_fork t cmd (
    fun () ->
      let r = Sys.command cmd in
      if r <> 0 then failwith "external command failed"
  )
