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

open Unix
open Printf

open Common_gettext.Gettext
open Std_utils
open Tools_utils
open Unix_utils

open Utils

type t = {
  (* The nbdkit plugin name. *)
  plugin_name : string;

  (* Parameters (includes the plugin name). *)
  args : string list;

  (* Environment variables that may be needed for nbdkit to work. *)
  env : (string * string) list;
}

(* Check that nbdkit is available and new enough. *)
let error_unless_nbdkit_working () =
  if 0 <> Sys.command "nbdkit --version >/dev/null" then
    error (f_"nbdkit is not installed or not working");

  (* Check it's a new enough version.  The latest features we
   * require are ‘--exit-with-parent’ and ‘--selinux-label’, both
   * added in 1.1.14.  (We use 1.1.16 as the minimum here because
   * it also adds the selinux=yes|no flag in --dump-config).
   *)
  let lines = external_command "nbdkit --help" in
  let lines = String.concat " " lines in
  if String.find lines "exit-with-parent" == -1 ||
     String.find lines "selinux-label" == -1 then
    error (f_"nbdkit is not new enough, you need to upgrade to nbdkit ≥ 1.1.16")

(* Check that nbdkit was compiled with SELinux support (for the
 * --selinux-label option).
 *)
let error_unless_nbdkit_compiled_with_selinux () =
  if have_selinux then (
    let lines = external_command "nbdkit --dump-config" in
    (* In nbdkit <= 1.1.15 the selinux attribute was not present
     * at all in --dump-config output so there was no way to tell.
     * Ignore this case because there will be an error later when
     * we try to use the --selinux-label parameter.
     *)
    if List.mem "selinux=no" (List.map String.trim lines) then
      error (f_"nbdkit was compiled without SELinux support.  You will have to recompile nbdkit with libselinux-devel installed, or else set SELinux to Permissive mode while doing the conversion.")
  )

let common_create plugin_name plugin_args plugin_env =
  error_unless_nbdkit_working ();
  error_unless_nbdkit_compiled_with_selinux ();

  (* Start constructing the parts of the incredibly long nbdkit
   * command line which don't change between disks.
   *)
  let add_arg, get_args =
    let args = ref [] in
    let add_arg a = List.push_front a args in
    let get_args () = List.rev !args in
    add_arg, get_args in

  add_arg "nbdkit";
  if verbose () then add_arg "--verbose";
  add_arg "--readonly";         (* important! readonly mode *)
  add_arg "--foreground";       (* run in foreground *)
  add_arg "--exit-with-parent"; (* exit when virt-v2v exits *)
  add_arg "--newstyle";         (* use newstyle NBD protocol *)
  add_arg "--exportname"; add_arg "/";
  if have_selinux then (        (* label the socket so qemu can open it *)
    add_arg "--selinux-label"; add_arg "system_u:object_r:svirt_socket_t:s0"
  );
  let args = get_args () @ [ plugin_name ] @ plugin_args in

  (* Environment.  We always add LANG=C. *)
  let env = ("LANG", "C") :: plugin_env in

  { plugin_name; args; env }

(* VDDK libraries are located under lib32/ or lib64/ relative to the
 * libdir.  Note this is unrelated to Linux multilib or multiarch.
 *)
let libNN = sprintf "lib%d" Sys.word_size

(* Create an nbdkit module specialized for reading from VDDK sources. *)
let create_vddk ?config ?cookie ?libdir ~moref
                ?nfchostport ?password_file ?port
                ~server ?snapshot ~thumbprint ?transports ?user path =
  (* Compute the LD_LIBRARY_PATH that we may have to pass to nbdkit. *)
  let ld_library_path = Option.map (fun libdir -> libdir // libNN) libdir in

  (* Check that the VDDK path looks reasonable. *)
  let error_unless_vddk_libdir () =
    (match libdir with
     | None -> ()
     | Some libdir ->
        if not (is_directory libdir) then
          error (f_"‘-io vddk-libdir=%s’ does not point to a directory.  See the virt-v2v-input-vmware(1) manual.") libdir
    );

    (match ld_library_path with
     | None -> ()
     | Some ld_library_path ->
        if not (is_directory ld_library_path) then
          error (f_"VDDK library path %s not found or not a directory.  See the virt-v2v-input-vmware(1) manual.") ld_library_path
    )
  in

  (* Check that the VDDK plugin is installed and working *)
  let error_unless_nbdkit_vddk_working () =
    let set_ld_library_path =
      match ld_library_path with
      | None -> ""
      | Some ld_library_path ->
         sprintf "LD_LIBRARY_PATH=%s " (quote ld_library_path) in

    let cmd =
      sprintf "%snbdkit vddk --dump-plugin >/dev/null"
              set_ld_library_path in
    if Sys.command cmd <> 0 then (
      (* See if we can diagnose why ... *)
      let cmd =
        sprintf "LANG=C %snbdkit vddk --dump-plugin 2>&1 |
                     grep -sq \"cannot open shared object file\""
                set_ld_library_path in
      let needs_library = Sys.command cmd = 0 in
      if not needs_library then
        error (f_"nbdkit VDDK plugin is not installed or not working.  It is required if you want to use VDDK.

The VDDK plugin is not enabled by default when you compile nbdkit.  You have to read the instructions in the nbdkit sources under ‘plugins/vddk/README.VDDK’ to find out how to enable the VDDK plugin.

See also the virt-v2v-input-vmware(1) manual.")
      else
        error (f_"nbdkit VDDK plugin is not installed or not working.  It is required if you want to use VDDK.

It looks like you did not set the right path in the ‘-io vddk-libdir’ option, or your copy of the VDDK directory is incomplete.  There should be a library called ’<libdir>/%s/libvixDiskLib.so.?’.

See also the virt-v2v-input-vmware(1) manual.") libNN
    )
  in

  error_unless_vddk_libdir ();
  error_unless_nbdkit_vddk_working ();

  (* For VDDK we require some user.  If it's not supplied, assume root. *)
  let user = Option.default "root" user in

  let add_arg, get_args =
    let args = ref [] in
    let add_arg a = List.push_front a args in
    let get_args () = List.rev !args in
    add_arg, get_args in

  let password_param =
    match password_file with
    | None ->
       (* nbdkit asks for the password interactively *)
       "password=-"
    | Some password_file ->
       (* nbdkit reads the password from the file *)
       "password=+" ^ password_file in
  add_arg (sprintf "server=%s" server);
  add_arg (sprintf "user=%s" user);
  add_arg password_param;
  add_arg (sprintf "vm=moref=%s" moref);
  add_arg (sprintf "file=%s" path);

  (* The passthrough parameters. *)
  Option.may (fun s -> add_arg (sprintf "config=%s" s)) config;
  Option.may (fun s -> add_arg (sprintf "cookie=%s" s)) cookie;
  Option.may (fun s -> add_arg (sprintf "libdir=%s" s)) libdir;
  Option.may (fun s -> add_arg (sprintf "nfchostport=%s" s)) nfchostport;
  Option.may (fun s -> add_arg (sprintf "port=%s" s)) port;
  Option.may (fun s -> add_arg (sprintf "snapshot=%s" s)) snapshot;
  add_arg (sprintf "thumbprint=%s" thumbprint);
  Option.may (fun s -> add_arg (sprintf "transports=%s" s)) transports;

  let env =
    match ld_library_path with
    | None -> []
    | Some ld_library_path -> ["LD_LIBRARY_PATH", ld_library_path] in

  common_create "vddk" (get_args ()) env

let run { args; env } =
  (* Create a temporary directory where we place the sockets. *)
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "v2vnbdkit." in
    (* tmpdir must be readable (but not writable) by "other" so that
     * qemu can open the sockets.
     *)
    chmod t 0o755;
    rmdir_on_exit t;
    t in

  let id = unique () in
  let sock = tmpdir // sprintf "nbdkit%d.sock" id in
  let qemu_uri = sprintf "nbd:unix:%s:exportname=/" sock in
  let pidfile = tmpdir // sprintf "nbdkit%d.pid" id in

  (* Construct the final command line with the "static" args
   * above plus the pidfile and socket which vary for each run.
   *)
  let args = args @ [ "--pidfile"; pidfile; "--unix"; sock ] in

  (* Print the full command we are about to run when debugging. *)
  if verbose () then (
    eprintf "running nbdkit:\n";
    List.iter (fun (k, v) -> eprintf " %s=%s" k v) env;
    List.iter (fun arg -> eprintf " %s" (quote arg)) args;
    prerr_newline ()
  );

  (* Start an nbdkit instance in the background.  By using
   * --exit-with-parent we don't have to worry about cleaning
   * it up, hopefully.
   *)
  let args = Array.of_list args in
  let pid = fork () in
  if pid = 0 then (
    (* Child process (nbdkit). *)
    List.iter (fun (k, v) -> putenv k v) env;
    execvp "nbdkit" args
  );

  (* Wait for the pidfile to appear so we know that nbdkit
   * is listening for requests.
   *)
  if not (wait_for_file pidfile 30) then (
    if verbose () then
      error (f_"nbdkit did not start up.  See previous debugging messages for problems.")
    else
      error (f_"nbdkit did not start up.  There may be errors printed by nbdkit above.

If the messages above are not sufficient to diagnose the problem then add the ‘virt-v2v -v -x’ options and examine the debugging output carefully.")
         );

  if have_selinux then (
    (* Note that Unix domain sockets have both a file label and
     * a socket/process label.  Using --selinux-label above
     * only set the socket label, but we must also set the file
     * label.
     *)
    ignore (
        run_command ["chcon"; "system_u:object_r:svirt_image_t:s0"; sock]
      );
  );
  (* ... and the regular Unix permissions, in case qemu is
   * running as another user.
   *)
  chmod sock 0o777;

  if verbose () then (
    eprintf "nbdkit: tmpdir %s:\n%!" tmpdir;
    ignore (Sys.command (sprintf "ls -laZ %s" (quote tmpdir)))
  );

  qemu_uri
