(* virt-sysprep
 * Copyright (C) 2020 Red Hat Inc.
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
open Common_gettext.Gettext

module G = Guestfs

let ipa_client_perform (g : Guestfs.guestfs) root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    (* Simple paths with no side effects. *)
    let paths = [ "/etc/ipa/ca.crt";
                  "/etc/ipa/default.conf";
                  "/var/lib/ipa-client/sysrestore/*";
                  "/var/lib/ipa-client/pki/*" ] in
    let paths = List.concat (List.map Array.to_list (List.map g#glob_expand paths)) in
    List.iter (
      fun filename ->
        try g#rm filename with G.Error _ -> ()
    ) paths;

    (* Certificates in the system CA store. *)
    let certs = [ "/etc/pki/ca-trust/source/anchors/ipa-ca.crt";
                  "/usr/local/share/ca-certificates/ipa-ca.crt";
                  "/etc/pki/ca-trust/source/ipa.p11-kit" ] in
    List.iter (
      fun filename ->
        try
          g#rm filename;
          side_effects#update_system_ca_store ()
        with
          G.Error _ -> ()
    ) certs
  )

let op = {
  defaults with
    name = "ipa-client";
    enabled_by_default = true;
    heading = s_"Remove the IPA files";
    pod_description = Some (s_"\
Remove all the files related to an IPA (Identity, Policy, Audit) system.
This effectively unenrolls the guest from an IPA server without interacting
with it.

This operation does not run C<ipa-client>.");
    perform_on_filesystems = Some ipa_client_perform;
}

let () = register_operation op
