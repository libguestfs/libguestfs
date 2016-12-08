(* Set timezone in virt-sysprep and virt-builder.
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

open Common_utils

open Printf

let set_timezone (g : Guestfs.guestfs) root timezone =
  let typ = g#inspect_get_type root in

  match typ with
  (* Every known Linux has /etc/localtime be either a copy of or a
   * symlink to a timezone file in /usr/share/zoneinfo.
   * Even systemd didn't fuck this up.
   *)
  | "linux" ->
    let target = sprintf "/usr/share/zoneinfo/%s" timezone in
    if not (g#exists target) then
      error "timezone '%s' does not exist, use a location like 'Europe/London'" timezone;
    g#ln_sf target "/etc/localtime";
    true

  | _ ->
    false
