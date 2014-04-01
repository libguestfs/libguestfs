(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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
open Common_utils

open Types
open Utils

module StringMap = Map.Make (String)
let keys map = StringMap.fold (fun k _ ks -> k :: ks) map []

(* Wrappers around aug_init & aug_load which can dump out full Augeas
 * parsing problems when debugging is enabled.
 *)
let rec augeas_init verbose g =
  g#aug_init "/" 1;
  if verbose then augeas_debug_errors g

and augeas_reload verbose g =
  g#aug_load ();
  if verbose then augeas_debug_errors g

and augeas_debug_errors g =
  try
    let errors = g#aug_match "/augeas/files//error" in
    let errors = Array.to_list errors in
    let map =
      List.fold_left (
        fun map error ->
          let detail_paths = g#aug_match (error ^ "//*") in
          let detail_paths = Array.to_list detail_paths in
          List.fold_left (
            fun map path ->
              (* path is "/augeas/files/<filename>/error/<field>".  Put
               * <filename>, <field> and the value of this Augeas field
               * into a map.
               *)
              let i = string_find path "/error/" in
              assert (i >= 0);
              let filename = String.sub path 13 (i-13) in
              let field = String.sub path (i+7) (String.length path - (i+7)) in

              let detail = g#aug_get path in

              let fmap : string StringMap.t =
                try StringMap.find filename map
                with Not_found -> StringMap.empty in
              let fmap = StringMap.add field detail fmap in
              StringMap.add filename fmap map
          ) map detail_paths
      ) StringMap.empty errors in

    let filenames = keys map in
    let filenames = List.sort compare filenames in

    List.iter (
      fun filename ->
        printf "augeas failed to parse %s:\n" filename;
        let fmap = StringMap.find filename map in
        (try
           let msg = StringMap.find "message" fmap in
           printf " error \"%s\"" msg
         with Not_found -> ()
        );
        (try
           let line = StringMap.find "line" fmap
           and char = StringMap.find "char" fmap in
           printf " at line %s char %s" line char
         with Not_found -> ()
        );
        (try
           let lens = StringMap.find "lens" fmap in
           printf " in lens %s" lens
         with Not_found -> ()
        );
        printf "\n"
    ) filenames;

    flush stdout
  with
    G.Error msg -> eprintf "%s: augeas: %s (ignored)\n" prog msg

let install verbose g inspect packages =
  assert false

let remove verbose g inspect packages =
  if packages <> [] then (
    let root = inspect.i_root in
    let package_format = g#inspect_get_package_format root in
    match package_format with
    | "rpm" ->
      let cmd = [ "rpm"; "-e" ] @ packages in
      let cmd = Array.of_list cmd in
      ignore (g#command cmd);

      (* Reload Augeas in case anything changed. *)
      augeas_reload verbose g

    | format ->
      error (f_"don't know how to remove packages using %s: packages: %s")
        format (String.concat " " packages)
  )

let file_owned verbose g inspect file =
  let root = inspect.i_root in
  let package_format = g#inspect_get_package_format root in
  match package_format with
  | "rpm" ->
      let cmd = [| "rpm"; "-qf"; file |] in
      (try ignore (g#command cmd); true with G.Error _ -> false)

  | format ->
    error (f_"don't know how to find package owner using %s") format

type kernel_info = {
  base_package : string;          (* base package, eg. "kernel-PAE" *)
  version : string;               (* kernel version *)
  modules : string list;          (* list of kernel modules *)
  arch : string;                  (* kernel arch *)
}

(* There was some crazy SUSE stuff going on in the Perl version
 * of virt-v2v, which I have dropped from this as I couldn't
 * understand what on earth it was doing.  - RWMJ
 *)
let inspect_linux_kernel verbose (g : Guestfs.guestfs) inspect path =
  let root = inspect.i_root in

  let base_package =
    let package_format = g#inspect_get_package_format root in
    match package_format with
    | "rpm" ->
      let cmd = [| "rpm"; "-qf"; "--qf"; "%{NAME}"; path |] in
      g#command cmd
    | format ->
      error (f_"don't know how to inspect kernel using %s") format in

  (* Try to get kernel version by examination of the binary.
   * See supermin.git/src/kernel.ml
   *)
  let version =
    try
      let hdrS = g#pread path 4 514L in
      if hdrS <> "HdrS" then raise Not_found;
      let s = g#pread path 2 518L in
      let s = (Char.code s.[1] lsl 8) lor Char.code s.[0] in
      if s < 0x1ff then raise Not_found;
      let offset = g#pread path 2 526L in
      let offset = (Char.code offset.[1] lsl 8) lor Char.code offset.[0] in
      if offset < 0 then raise Not_found;
      let buf = g#pread path (offset + 0x200) 132L in
      let rec loop i =
        if i < 132 then (
          if buf.[i] = '\000' || buf.[i] = ' ' ||
            buf.[i] = '\t' || buf.[i] = '\n' then
            String.sub buf 0 i
          else
            loop (i+1)
        )
        else raise Not_found
      in
      let v = loop 0 in
      (* There must be a corresponding modules directory. *)
      let modpath = sprintf "/lib/modules/%s" v in
      if not (g#is_dir modpath) then
        raise Not_found;
      Some (v, modpath)
    with Not_found -> None in

  (* Apparently Xen PV kernels don't contain a version number,
   * so try to guess the version from the filename.
   *)
  let version =
    match version with
    | Some v -> Some v
    | None ->
      let rex = Str.regexp "^/boot/vmlinuz-\\(.*\\)" in
      if Str.string_match rex path 0 then (
        let v = Str.matched_group 1 path in
        let modpath = sprintf "/lib/modules/%s" v in
        if g#is_dir modpath then Some (v, modpath) else None
      )
      else None in

  (* If we sill didn't find a version, give up here. *)
  match version with
  | None -> None
  | Some (version, modpath) ->

    (* List modules. *)
    let modules = g#find modpath in
    let modules = Array.to_list modules in
    let rex = Str.regexp ".*\\.k?o$" in
    let modules = List.filter (fun m -> Str.string_match rex m 0) modules in

    assert (List.length modules > 0);

    (* Determine the kernel architecture by looking at the architecture
     * of an arbitrary kernel module.
     *)
    let arch =
      let any_module = modpath ^ List.hd modules in
      g#file_architecture any_module in

    (* Just return the module names, without path or extension. *)
    let rex = Str.regexp ".*/\\([^/]+\\)\\.k?o$/" in
    let modules = filter_map (
      fun m ->
        if Str.string_match rex m 0 then
          Some (Str.matched_group 1 m)
        else
          None
    ) modules in

    Some { base_package = base_package;
           version = version;
           modules = modules;
           arch = arch }
