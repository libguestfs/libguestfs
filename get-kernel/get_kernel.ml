(* virt-get-kernel
 * Copyright (C) 2013-2015 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

module G = Guestfs

open Printf

let parse_cmdline () =
  let domain = ref None in
  let file = ref None in
  let libvirturi = ref "" in
  let format = ref "" in
  let output = ref "" in
  let machine_readable = ref false in
  let unversioned = ref false in
  let prefix = ref None in

  let set_file arg =
    if !file <> None then
      error (f_"--add option can only be given once");
    let uri =
      try URI.parse_uri arg
      with Invalid_argument "URI.parse_uri" ->
        error (f_"error parsing URI '%s'. Look for error messages printed above.") arg in
    file := Some uri
  and set_domain dom =
    if !domain <> None then
      error (f_"--domain option can only be given once");
    domain := Some dom
  and set_prefix p =
    if !prefix <> None then
      error (f_"--prefix option can only be given once");
    prefix := Some p in

  let ditto = " -\"-" in
  let argspec = [
    "-a",        Arg.String set_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "--add",     Arg.String set_file,       s_"file" ^ " " ^ s_"Add disk image file";
    "-c",        Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "--connect", Arg.Set_string libvirturi, s_"uri" ^ " " ^ s_"Set libvirt URI";
    "-d",        Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "--domain",  Arg.String set_domain,     s_"domain" ^ " " ^ s_"Set libvirt guest name";
    "--format",  Arg.Set_string format,     s_"format" ^ " " ^ s_"Format of input disk";
    "--machine-readable", Arg.Set machine_readable, " " ^ s_"Make output machine readable";
    "-o",        Arg.Set_string output, s_"directory" ^ " " ^ s_"Output directory";
    "--output",  Arg.Set_string output,     ditto;
    "--unversioned-names", Arg.Set unversioned,
                                            " " ^ s_"Use unversioned names for files";
    "--prefix",  Arg.String set_prefix,     "prefix" ^ " " ^ s_"Prefix for files";
  ] in
  let argspec = set_standard_options argspec in
  let anon_fun _ = raise (Arg.Bad (s_"extra parameter on the command line")) in
  let usage_msg =
    sprintf (f_"\
%s: extract kernel and ramdisk from a guest

A short summary of the options is given below.  For detailed help please
read the man page virt-get-kernel(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Machine-readable mode?  Print out some facts about what
   * this binary supports.
   *)
  if !machine_readable then (
    printf "virt-get-kernel\n";
    exit 0
  );

  (* Check -a and -d options. *)
  let file = !file in
  let domain = !domain in
  let libvirturi = match !libvirturi with "" -> None | s -> Some s in
  let add =
    match file, domain with
    | None, None ->
      error (f_"you must give either -a or -d options.  Read virt-get-kernel(1) man page for further information.")
    | Some _, Some _ ->
      error (f_"you cannot give -a and -d options together.  Read virt-get-kernel(1) man page for further information.")
    | None, Some dom ->
      fun (g : Guestfs.guestfs) ->
        let readonlydisk = "ignore" (* ignore CDs, data drives *) in
        ignore (g#add_domain
                  ~readonly:true ~allowuuid:true ~readonlydisk
                  ?libvirturi dom)
    | Some uri, None ->
      fun g ->
        let { URI.path = path; protocol = protocol;
              server = server; username = username;
              password = password } = uri in
        let format = match !format with "" -> None | s -> Some s in
        g#add_drive
          ~readonly:true ?format ~protocol ?server ?username ?secret:password
          path
  in

  (* Dereference the rest of the args. *)
  let output = match !output with "" -> None | str -> Some str in
  let unversioned = !unversioned in
  let prefix = !prefix in

  add, output, unversioned, prefix

(* Main program. *)
let main () =
  let add, output, unversioned, prefix = parse_cmdline () in

  (* Connect to libguestfs. *)
  let g = new G.guestfs () in
  if trace () then g#set_trace true;
  if verbose () then g#set_verbose true;
  add g;
  g#launch ();

  let roots = g#inspect_os () in
  if Array.length roots = 0 then
    error (f_"no operating system found");
  if Array.length roots > 1 then
    error (f_"dual/multi-boot images are not supported by this tool");
  let root = roots.(0) in

  (* Mount up the disks. *)
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (
    fun (mp, dev) ->
      try g#mount_ro dev mp
      with Guestfs.Error msg -> warning (f_"%s (ignored)") msg
  ) mps;

  (* Get all kernels and initramfses. *)
  let glob w = Array.to_list (g#glob_expand w) in
  let kernels = glob "/boot/vmlinuz-*" in
  let initrds = glob "/boot/initramfs-*" in

  (* Old RHEL: *)
  let initrds = if initrds <> [] then initrds else glob "/boot/initrd-*" in

  (* Debian/Ubuntu: *)
  let initrds = if initrds <> [] then initrds else glob "/boot/initrd.img-*" in

  (* Sort by version to get the latest version as first element. *)
  let kernels = List.rev (List.sort compare_version kernels) in
  let initrds = List.rev (List.sort compare_version initrds) in

  if kernels = [] then
    error (f_"no kernel found");

  let dest_filename fn =
    let fn = Filename.basename fn in
    let fn =
      if unversioned then fst (string_split "-" fn)
      else fn in
    match prefix with
    | None -> fn
    | Some p -> p ^ "-" ^ fn in

  (* Download the latest. *)
  let outputdir =
    match output with
    | None -> Filename.current_dir_name
    | Some dir -> dir in
  let kernel_in = List.hd kernels in
  let kernel_out = outputdir // dest_filename kernel_in in
  printf "download: %s -> %s\n%!" kernel_in kernel_out;
  g#download kernel_in kernel_out;

  if initrds <> [] then (
    let initrd_in = List.hd initrds in
    let initrd_out = outputdir // dest_filename initrd_in in
    printf "download: %s -> %s\n%!" initrd_in initrd_out;
    g#download initrd_in initrd_out
  );

  (* Shutdown. *)
  g#shutdown ();
  g#close ()

let () = run_main_and_handle_errors main
