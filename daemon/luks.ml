(* guestfs-inspection
 * Copyright (C) 2009-2026 Red Hat Inc.
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
open Unix

open Std_utils

open Utils

(* Deprecated APIs for backwards compatibility. *)
let luks_open device key mapname =
  Cryptsetup.cryptsetup_open ~crypttype:"luks" device key mapname
let luks_open_ro device key mapname =
  Cryptsetup.cryptsetup_open ~crypttype:"luks" ~readonly:true device key mapname
let luks_close =
  Cryptsetup.cryptsetup_close
