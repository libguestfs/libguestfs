(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** Generate a qemu command line, dealing with quoting. *)

open Printf

open Common_utils

type t = {
  cmd : string;
  mutable args : arg list; (* list constructed in reverse order *)
}
and arg =
  | Flag of string
  | Arg of string * string * bool
  | Commas of string * string list

let create ?(arch = "x86_64") () =
  { cmd = "/usr/libexec/qemu-kvm"; args = [] }

let flag t k =
  assert (String.is_prefix k "-");
  t.args <- Flag k :: t.args

let arg t k v =
  assert (String.is_prefix k "-");
  t.args <- Arg (k, v, true) :: t.args

let arg_noquote t k v =
  assert (String.is_prefix k "-");
  t.args <- Arg (k, v, false) :: t.args

let commas t k vs =
  assert (String.is_prefix k "-");
  List.iter (fun v -> assert (v <> "")) vs;
  t.args <- Commas (k, vs) :: t.args

let nl = " \\\n\t"

(* If the value contains only simple characters then it doesn't
 * need quoting.  This keeps the output as similar as possible
 * to the old code.
 *)
let do_quoting str =
  let len = String.length str in
  let ret = ref false in
  for i = 0 to len-1 do
    let c = String.unsafe_get str i in
    if not (Char.isalnum c) &&
         c <> '.' && c <> '-' && c <> '_' &&
         c <> '=' && c <> ',' && c <> ':' && c <> '/'
    then
      ret := true
  done;
  !ret

let print_quoted_param chan k v =
  if not (do_quoting v) then
    fprintf chan "%s%s %s" nl k v
  else
    fprintf chan "%s%s %s" nl k (quote v)

let to_chan t chan =
  fprintf chan "%s" t.cmd;
  List.iter (
    function
    | Flag k ->
       fprintf chan "%s%s" nl k
    | Arg (k, v, true) ->
       print_quoted_param chan k v
    | Arg (k, v, false) ->
       fprintf chan "%s%s %s" nl k v
    | Commas (k, vs) ->
       let vs = List.map (fun s -> String.replace s "," ",,") vs in
       let v = String.concat "," vs in
       print_quoted_param chan k v
  ) (List.rev t.args);
  fprintf chan "\n"

let to_script t filename =
  let chan = open_out filename in
  fprintf chan "#!/bin/sh -\n";
  to_chan t chan;
  close_out chan;
  Unix.chmod filename 0o755
