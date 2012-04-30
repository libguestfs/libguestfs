(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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

open Utils

open Sysprep_operation
open Sysprep_gettext.Gettext

module G = Guestfs

let user_account_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    g#aug_init "/" 0;
    let uid_min = g#aug_get "/files/etc/login.defs/UID_MIN" in
    let uid_min = int_of_string uid_min in
    let uid_max = g#aug_get "/files/etc/login.defs/UID_MAX" in
    let uid_max = int_of_string uid_max in
    let users = Array.to_list (g#aug_ls "/files/etc/passwd") in
    List.iter (
      fun userpath ->
        let uid = userpath ^ "/uid" in
        let uid = g#aug_get uid in
        let uid = int_of_string uid in
        if uid >= uid_min && uid <= uid_max then (
          g#aug_rm userpath;
          let username =
            let i = String.rindex userpath '/' in
            String.sub userpath (i+1) (String.length userpath -i-1) in
          (* XXX Augeas doesn't yet have a lens for /etc/shadow, so the
           * next line currently does nothing, but should start to
           * work in a future version.
           *)
          g#aug_rm (sprintf "/files/etc/shadow/%s" username);
          g#aug_rm (sprintf "/files/etc/group/%s" username);
          g#rm_rf ("/home/" ^ username)
        )
    ) users;
    g#aug_save ();
    []
  )
  else []

let user_account_op = {
  name = "user-account";
  enabled_by_default = false;
  heading = s_"Remove the user accounts in the guest";
  pod_description = Some (s_"\
Remove all the user accounts and their home directories.
The \"root\" account is not removed.");
  extra_args = [];
  perform = user_account_perform;
}

let () = register_operation user_account_op
