(* virt-customize
 * Copyright (C) 2014 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Customize_utils

open Printf
open Sys
open Unix

module G = Guestfs

type ssh_key_selector =
| SystemKey
| KeyFile of string
| KeyString of string

let rec parse_selector arg =
  parse_selector_list arg (String.nsplit ":" arg)

and parse_selector_list orig_arg = function
  | [] | [ "" ] ->
    SystemKey
  | [ "file"; f ] ->
    KeyFile f
  | [ "string"; s ] ->
    KeyString s
  | _ ->
    error (f_"invalid ssh-inject selector '%s'; see the man page") orig_arg

(* Find the local [on the host] user's SSH public key.  See
 * ssh-copy-id(1) default_ID_file for rationale.
 *)
let pubkey_re = Str.regexp "^id.*\\.pub$"
let pubkey_ignore_re = Str.regexp ".*-cert\\.pub$"

let local_user_ssh_pubkey () =
  let home_dir =
    try getenv "HOME"
    with Not_found ->
      error (f_"ssh-inject: $HOME environment variable is not set") in
  let ssh_dir = home_dir // ".ssh" in
  let files = Sys.readdir ssh_dir in
  let files = Array.to_list files in
  let files = List.filter (
    fun file ->
      Str.string_match pubkey_re file 0 &&
        not (Str.string_match pubkey_ignore_re file 0)
  ) files in
  if files = [] then
    error (f_"ssh-inject: no public key file found in %s") ssh_dir;

  (* Newest file. *)
  let files = List.map (
    fun file ->
      let file = ssh_dir // file in
      let stat = stat file in
      (file, stat.st_mtime)
  ) files in
  let files = List.sort (fun (_,m1) (_,m2) -> compare m2 m1) files in

  fst (List.hd files)

let read_key file =
  (* Read and return the public key. *)
  let key = read_whole_file file in
  if key = "" then
    error (f_"ssh-inject: public key file (%s) is empty") file;
  key

let key_string_from_selector = function
  | SystemKey ->
    read_key (local_user_ssh_pubkey ())
  | KeyFile f ->
    read_key f
  | KeyString s ->
    if String.length s < 1 then
      error (f_"ssh-inject: key is an empty string");
    s

(* Inject SSH key, where possible. *)
let do_ssh_inject_unix (g : Guestfs.guestfs) user selector =
  let key = key_string_from_selector selector in
  assert (String.length key > 0);

  (* If the key doesn't have \n at the end, add it. *)
  let len = String.length key in
  let key = if key.[len-1] = '\n' then key else key ^ "\n" in

  (* Get user's home directory. *)
  g#aug_init "/" 0;
  let read_user_detail what =
    try
      let expr = sprintf "/files/etc/passwd/%s/%s" user what in
      g#aug_get expr
    with G.Error _ ->
      error (f_"ssh-inject: the user %s does not exist on the guest")
        user
  in
  let home_dir = read_user_detail "home" in
  g#aug_close ();

  (* Create ~user/.ssh if it doesn't exist. *)
  let ssh_dir = sprintf "%s/.ssh" home_dir in
  if not (g#exists ssh_dir) then (
    g#mkdir ssh_dir;
    g#chmod 0o700 ssh_dir
  );

  (* Create ~user/.ssh/authorized_keys if it doesn't exist. *)
  let auth_keys = sprintf "%s/authorized_keys" ssh_dir in
  if not (g#exists auth_keys) then (
    g#touch auth_keys;
    g#chmod 0o600 auth_keys
  );

  (* Append the key. *)
  g#write_append auth_keys key
