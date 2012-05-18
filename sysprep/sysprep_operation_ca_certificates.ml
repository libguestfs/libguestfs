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

let ca_certificates_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let paths = [ "/etc/pki/CA/certs/*.crt";
                  "/etc/pki/CA/crl/*.crt";
                  "/etc/pki/CA/newcerts/*.crt";
                  "/etc/pki/CA/private/*.key";
                  "/etc/pki/tls/private/*.key";
                  "/etc/pki/tls/certs/*.crt"; ] in
    let excepts = [ "/etc/pki/tls/certs/ca-bundle.crt";
                    "/etc/pki/tls/certs/ca-bundle.trust.crt"; ] in
    (* Thanks Rich for this StringSet method *)
    let paths = List.concat (List.map Array.to_list (List.map g#glob_expand paths)) in
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

let ca_certificates_op = {
  name = "ca-certificates";
  enabled_by_default = false;
  heading = s_"Remove CA certificates in the guest";
  pod_description = None;
  extra_args = [];
  perform = ca_certificates_perform;
}

let () = register_operation ca_certificates_op
