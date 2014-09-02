(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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

open Printf

open Common_utils

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

module StringSet = Set.Make (String)

let users_included = ref StringSet.empty
let users_excluded = ref StringSet.empty
let set_users users =
  let users = string_nsplit "," users in
  List.iter (
    fun user ->
      let op =
        if string_prefix user "-" then
          `Exclude (String.sub user 1 (String.length user - 1))
        else
          `Include user in
      match op with
      | `Include "" | `Exclude "" ->
        eprintf (f_"%s: --user-accounts: empty user name\n")
          prog;
        exit 1
      | `Include n ->
        users_included := StringSet.add n !users_included;
        users_excluded := StringSet.remove n !users_excluded
      | `Exclude n ->
        users_included := StringSet.remove n !users_included;
        users_excluded := StringSet.add n !users_excluded
  ) users

let check_remove_user user =
  (* If an user is explicitly excluded, keep it. *)
  if StringSet.mem user !users_excluded then
    false
  (* If the list of included users is empty (thus no users were explicitly
   * included), or an user is explicitly included, remove it. *)
  else if StringSet.is_empty !users_included
          or StringSet.mem user !users_included then
    true
  (* Any other case, not a reason to remove it. *)
  else
    false

let user_account_perform ~verbose ~quiet g root side_effects =
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
        let username =
          let i = String.rindex userpath '/' in
          String.sub userpath (i+1) (String.length userpath -i-1) in
        if uid >= uid_min && uid <= uid_max
           && check_remove_user username then (
          g#aug_rm userpath;
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
  )

let op = {
  defaults with
    name = "user-account";
    enabled_by_default = false;
    heading = s_"Remove the user accounts in the guest";
    pod_description = Some (s_"\
By default remove all the user accounts and their home directories.
The \"root\" account is not removed.

See the I<--user-accounts> parameter for a way to specify
how to remove only some users, or to not remove some others.");
    pod_notes = Some (s_"\
Currently this does not remove the user accounts from
C</etc/shadow>.  This is because there is no lens for
the shadow password file in Augeas.");
    extra_args = [
      { extra_argspec = "--user-accounts", Arg.String set_users, s_"users" ^ " " ^ s_"Users to remove/keep";
        extra_pod_argval = Some "USERS";
        extra_pod_description = s_"\
The user accounts to be removed (or not) from the guest.
The value of this option is a list of user names separated by comma,
where specifying an user means it is going to be removed,
while prepending C<-> in front of it name means it is not removed.
For example:

 --user-accounts bob,eve

would only remove the user accounts C<bob> and C<eve>.

This option can be specified multiple times."
      };
    ];
    perform_on_filesystems = Some user_account_perform;
}

let () = register_operation op
