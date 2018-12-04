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

open Printf

open Common_gettext.Gettext
open Tools_utils

open Utils

(* Detect anti-virus (AV) software installed in Windows guests. *)
let rex_virus     = PCRE.compile ~caseless:true "virus" (* generic *)
let rex_kaspersky = PCRE.compile ~caseless:true "kaspersky"
let rex_mcafee    = PCRE.compile ~caseless:true "mcafee"
let rex_norton    = PCRE.compile ~caseless:true "norton"
let rex_sophos    = PCRE.compile ~caseless:true "sophos"
let rex_avg_tech  = PCRE.compile ~caseless:true "avg technologies" (* RHBZ#1261436 *)

let rec detect_antivirus { Types.i_type = t; i_apps = apps } =
  assert (t = "windows");
  List.exists check_app apps

and check_app { Guestfs.app2_name = name;
                app2_publisher = publisher } =
  name      =~ rex_virus     ||
  name      =~ rex_kaspersky ||
  name      =~ rex_mcafee    ||
  name      =~ rex_norton    ||
  name      =~ rex_sophos    ||
  publisher =~ rex_avg_tech

and (=~) str rex = PCRE.matches rex str

(* Unfortunately Powershell scripts cannot be directly executed
 * (unless some system config changes are made which for other
 * reasons we don't want to do) and so we have to run this via
 * a regular batch file.
 *)
let install_firstboot_powershell g { Types.i_windows_systemroot; i_root }
                                 filename code =
  let tempdir = sprintf "%s/Temp" i_windows_systemroot in
  g#mkdir_p tempdir;
  let code = String.concat "\r\n" code ^ "\r\n" in
  g#write (sprintf "%s/%s" tempdir filename) code;

  (* Powershell interpreter.  Should we check this exists? XXX *)
  let ps_exe =
    i_windows_systemroot ^
    "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" in

  (* Windows path to the Powershell script. *)
  let ps_path = i_windows_systemroot ^ "\\Temp\\" ^ filename in

  let fb = sprintf "%s -ExecutionPolicy ByPass -file %s" ps_exe ps_path in
  Firstboot.add_firstboot_script g i_root filename fb
