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

open Sysprep_operation
open Sysprep_gettext.Gettext

module StringSet = Set.Make (String)
module G = Guestfs

let kerberos_data_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let excepts = [ "/var/kerberos/krb5kdc/kadm5.acl";
                    "/var/kerberos/krb5kdc/kdc.conf"; ] in
    let paths = Array.to_list (g#glob_expand "/var/kerberos/krb5kdc/*") in
    let set = List.fold_right StringSet.add paths StringSet.empty in
    let excepts = List.fold_right StringSet.add excepts StringSet.empty in
    let set = StringSet.diff set excepts in
    StringSet.iter (
      fun filename ->
        try g#rm filename with G.Error _ -> ()
    ) set;

    []
  )
  else []

let kerberos_data_op = {
  name = "kerberos-data";
  enabled_by_default = false;
  heading = s_"Remove Kerberos data in the guest";
  pod_description = None;
  extra_args = [];
  perform = kerberos_data_perform;
}

let () = register_operation kerberos_data_op
