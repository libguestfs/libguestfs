(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

(* Command line argument parsing. *)

open Common_gettext.Gettext
open Common_utils

open Utils

open Printf

type cmdline = {
  debug : int;
  basepath : string;
  elements : string list;
  excluded_elements : string list;
  element_paths : string list;
  excluded_scripts : string list;
  use_base : bool;
  drive : string option;
  image_name : string;
  fs_type : string;
  size : int64;
  root_label : string option;
  install_type : string;
  image_cache : string option;
  compressed : bool;
  qemu_img_options : string option;
  mkfs_options : string option;
  is_ramdisk : bool;
  ramdisk_element : string;
  extra_packages : string list;
  memsize : int option;
  network : bool;
  smp : int option;
  delete_on_failure : bool;
  formats : string list;
  arch : string;
  envvars : string list;
}

let parse_cmdline () =
  let usage_msg =
    sprintf (f_"\
%s: run diskimage-builder elements to generate images

 virt-dib -B DIB-LIB -p ELEMENTS-PATH elements...

A short summary of the options is given below.  For detailed help please
read the man page virt-dib(1).
")
      prog in

  let elements = ref [] in
  let append_element element = unshift element elements in

  let excluded_elements = ref [] in
  let append_excluded_element element = unshift element excluded_elements in

  let element_paths = ref [] in
  let append_element_path arg = unshift arg element_paths in

  let excluded_scripts = ref [] in
  let append_excluded_script arg = unshift arg excluded_scripts in

  let debug = ref 0 in
  let set_debug arg =
    if arg < 0 then
      error (f_"--debug parameter must be >= 0");
    debug := arg in

  let basepath = ref "" in

  let image_name = ref "image" in

  let fs_type = ref "ext4" in

  let size = ref (unit_GB 5) in
  let set_size arg = size := parse_size arg in

  let memsize = ref None in
  let set_memsize arg = memsize := Some arg in

  let network = ref true in

  let smp = ref None in
  let set_smp arg = smp := Some arg in

  let formats = ref ["qcow2"] in
  let set_format arg =
    let fmts = remove_dups (String.nsplit "," arg) in
    List.iter (
      function
      | "qcow2" | "tar" | "raw" | "vhd" -> ()
      | fmt ->
        error (f_"invalid format '%s' in --formats") fmt
    ) fmts;
    formats := fmts in

  let envvars = ref [] in
  let append_envvar arg = unshift arg envvars in

  let use_base = ref true in

  let arch = ref "" in

  let drive = ref None in
  let set_drive arg = drive := Some arg in

  let root_label = ref None in
  let set_root_label arg = root_label := Some arg in

  let install_type = ref "source" in

  let image_cache = ref None in
  let set_image_cache arg = image_cache := Some arg in

  let compressed = ref true in

  let delete_on_failure = ref true in

  let is_ramdisk = ref false in
  let ramdisk_element = ref "ramdisk" in

  let qemu_img_options = ref None in
  let set_qemu_img_options arg = qemu_img_options := Some arg in

  let mkfs_options = ref None in
  let set_mkfs_options arg = mkfs_options := Some arg in

  let machine_readable = ref false in

  let extra_packages = ref [] in
  let append_extra_packages arg =
    prepend (List.rev (String.nsplit "," arg)) extra_packages in

  let argspec = [
    "-p",           Arg.String append_element_path, "path" ^ " " ^ s_"Add new a elements location";
    "--element-path", Arg.String append_element_path, "path" ^ " " ^ s_"Add new a elements location";
    "--exclude-element", Arg.String append_excluded_element,
      "element" ^ " " ^ s_"Exclude the specified element";
    "--exclude-script", Arg.String append_excluded_script,
      "script" ^ " " ^ s_"Exclude the specified script";
    "--envvar",     Arg.String append_envvar,  "envvar[=value]" ^ " " ^ s_"Carry/set this environment variable";
    "--skip-base",  Arg.Clear use_base,        " " ^ s_"Skip the inclusion of the 'base' element";
    "--root-label", Arg.String set_root_label, "label" ^ " " ^ s_"Label for the root fs";
    "--install-type", Arg.Set_string install_type, "type" ^ " " ^ s_"Installation type";
    "--image-cache", Arg.String set_image_cache, "directory" ^ " " ^ s_"Location for cached images";
    "-u",           Arg.Clear compressed,      " " ^ "Do not compress the qcow2 image";
    "--qemu-img-options", Arg.String set_qemu_img_options,
                                              "option" ^ " " ^ s_"Add qemu-img options";
    "--mkfs-options", Arg.String set_mkfs_options,
                                              "option" ^ " " ^ s_"Add mkfs options";
    "--extra-packages", Arg.String append_extra_packages,
      "pkg,..." ^ " " ^ s_"Add extra packages to install";

    "--ramdisk",    Arg.Set is_ramdisk,        " " ^ "Switch to a ramdisk build";
    "--ramdisk-element", Arg.Set_string ramdisk_element, "name" ^ " " ^ s_"Main element for building ramdisks";

    "--name",       Arg.Set_string image_name, "name" ^ " " ^ s_"Name of the image";
    "--fs-type",    Arg.Set_string fs_type,    "fs" ^ " " ^ s_"Filesystem for the image";
    "--size",       Arg.String set_size,       "size" ^ " " ^ s_"Set output disk size";
    "--formats",    Arg.String set_format,     "qcow2,tgz,..." ^ " " ^ s_"Output formats";
    "--arch",       Arg.Set_string arch,       "arch" ^ " " ^ s_"Output architecture";
    "--drive",      Arg.String set_drive,      "path" ^ " " ^ s_"Optional drive for caches";

    "-m",           Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--memsize",    Arg.Int set_memsize,       "mb" ^ " " ^ s_"Set memory size";
    "--network",    Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "--smp",        Arg.Int set_smp,           "vcpus" ^ " " ^ s_"Set number of vCPUs";
    "--no-delete-on-failure", Arg.Clear delete_on_failure,
                                               " " ^ s_"Don't delete output file on failure";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";

    "--debug",      Arg.Int set_debug,         "level" ^ " " ^ s_"Set debug level";
    "-B",           Arg.Set_string basepath,   "path" ^ " " ^ s_"Base path of diskimage-builder library";
  ] in

  let argspec = set_standard_options argspec in

  Arg.parse argspec append_element usage_msg;

  let debug = !debug in
  let basepath = !basepath in
  let elements = List.rev !elements in
  let excluded_elements = List.rev !excluded_elements in
  let element_paths = List.rev !element_paths in
  let excluded_scripts = List.rev !excluded_scripts in
  let image_name = !image_name in
  let fs_type = !fs_type in
  let size = !size in
  let memsize = !memsize in
  let network = !network in
  let smp = !smp in
  let formats = !formats in
  let envvars = !envvars in
  let use_base = !use_base in
  let arch = !arch in
  let drive = !drive in
  let root_label = !root_label in
  let install_type = !install_type in
  let image_cache = !image_cache in
  let compressed = !compressed in
  let delete_on_failure = !delete_on_failure in
  let is_ramdisk = !is_ramdisk in
  let ramdisk_element = !ramdisk_element in
  let qemu_img_options = !qemu_img_options in
  let mkfs_options = !mkfs_options in
  let machine_readable = !machine_readable in
  let extra_packages = List.rev !extra_packages in

  (* No elements and machine-readable mode?  Print some facts. *)
  if elements = [] && machine_readable then (
    printf "virt-dib\n";
    printf "output:qcow2\n";
    printf "output:tar\n";
    printf "output:raw\n";
    printf "output:vhd\n";
    exit 0
  );

  if basepath = "" then
    error (f_"-B must be specified");

  if formats = [] then
    error (f_"the list of output formats cannot be empty");

  if elements = [] then
    error (f_"at least one distribution root element must be specified");

  { debug = debug; basepath = basepath; elements = elements;
    excluded_elements = excluded_elements; element_paths = element_paths;
    excluded_scripts = excluded_scripts; use_base = use_base; drive = drive;
    image_name = image_name; fs_type = fs_type; size = size;
    root_label = root_label; install_type = install_type;
    image_cache = image_cache; compressed = compressed;
    qemu_img_options = qemu_img_options; mkfs_options = mkfs_options;
    is_ramdisk = is_ramdisk; ramdisk_element = ramdisk_element;
    extra_packages = extra_packages; memsize = memsize; network = network;
    smp = smp; delete_on_failure = delete_on_failure;
    formats = formats; arch = arch; envvars = envvars;
  }
