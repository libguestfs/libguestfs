(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

(* This module provides helper methods on top of the Libvirt
    module. *)

let auth_for_password_file ?password_file () =
  let auth_fn creds =
    let password = Option.map read_first_line_from_file password_file in
    List.map (
      function
      | { Libvirt.Connect.typ = Libvirt.Connect.CredentialPassphrase } -> password
      | _ -> None
    ) creds
  in

  {
    Libvirt.Connect.credtype = [ Libvirt.Connect.CredentialPassphrase ];
    cb = auth_fn;
  }

let get_domain conn name =
  let dom =
    try
      Libvirt.Domain.lookup_by_uuid_string conn name
    with
    (* No such domain. *)
    | Libvirt.Virterror { code = VIR_ERR_NO_DOMAIN }
    (* Invalid UUID string. *)
    | Libvirt.Virterror { code = VIR_ERR_INVALID_ARG; domain = VIR_FROM_DOMAIN } ->
      (try
        Libvirt.Domain.lookup_by_name conn name
      with
        Libvirt.Virterror { code = VIR_ERR_NO_DOMAIN; message } ->
          error (f_"cannot find libvirt domain ‘%s’: %s")
            name (Option.default "" message)
      ) in
  let uri = Libvirt.Connect.get_uri conn in
  (* As a side-effect we check that the domain is shut down.  Of course
   * this is only appropriate for virt-v2v.  (RHBZ#1138586)
   *)
  if not (String.is_prefix uri "test:") then (
    (match (Libvirt.Domain.get_info dom).Libvirt.Domain.state with
    | InfoRunning | InfoBlocked | InfoPaused ->
      error (f_"libvirt domain ‘%s’ is running or paused.  It must be shut down in order to perform virt-v2v conversion")
        (Libvirt.Domain.get_name dom)
    | InfoNoState | InfoShutdown | InfoShutoff | InfoCrashed | InfoPMSuspended ->
      ()
    )
  );
  dom

let get_pool conn name =
  try
    Libvirt.Pool.lookup_by_uuid_string conn name
  with
  (* No such pool. *)
  | Libvirt.Virterror { code = VIR_ERR_NO_STORAGE_POOL }
  (* Invalid UUID string. *)
  | Libvirt.Virterror { code = VIR_ERR_INVALID_ARG; domain = VIR_FROM_STORAGE } ->
    (try
      Libvirt.Pool.lookup_by_name conn name
    with Libvirt.Virterror { code = VIR_ERR_NO_STORAGE_POOL; message } ->
      error (f_"cannot find libvirt pool ‘%s’: %s\n\nUse ‘virsh pool-list --all’ to list all available pools, and ‘virsh pool-dumpxml <pool>’ to display details about a particular pool.\n\nTo set the pool which virt-v2v uses, add the ‘-os <pool>’ option.")
        name (Option.default "" message)
    )

let get_volume pool name =
  try
    Libvirt.Volume.lookup_by_name pool name
  with
  (* No such volume. *)
  | Libvirt.Virterror { code = VIR_ERR_NO_STORAGE_VOL; message } ->
    error (f_"cannot find libvirt volume ‘%s’: %s")
      name (Option.default "" message)

let domain_exists conn dom =
  try
    ignore (Libvirt.Domain.lookup_by_name conn dom);
    true
  with
    Libvirt.Virterror { code = VIR_ERR_NO_DOMAIN } -> false

let libvirt_get_version () =
  let v, _ = Libvirt.get_version () in
  let v_major = v / 1000000 in
  let v_minor = (v / 1000) mod 1000 in
  let v_micro = v mod 1000 in
  (v_major, v_minor, v_micro)
