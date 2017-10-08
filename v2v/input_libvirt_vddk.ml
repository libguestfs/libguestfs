(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** [-i libvirt] when the source is VMware via nbdkit vddk plugin *)

open Unix

open Common_gettext.Gettext
open Tools_utils
open Std_utils
open Unix_utils

open Types
open Utils
open Input_libvirt_other
open Parse_libvirt_xml
open Xpath_helpers

open Printf

(* Subclass specialized for handling VMware via nbdkit vddk plugin. *)
class input_libvirt_vddk vddk_options password libvirt_uri parsed_uri guest =

  (* The VDDK path. *)
  let libdir = vddk_options.vddk_libdir in
  (* Compute the LD_LIBRARY_PATH that we must pass to nbdkit. *)
  let library_path = libdir // sprintf "lib%d" Sys.word_size in

  (* Is SELinux enabled and enforcing on the host? *)
  let have_selinux =
    0 = Sys.command "getenforce 2>/dev/null | grep -isq Enforcing" in

  (* Check that the VDDK path looks reasonable. *)
  let error_unless_vddk_libdir () =
    if not (is_directory libdir) then
      error (f_"‘--vddk %s’ does not point to a directory.  See \"INPUT FROM VDDK\" in the virt-v2v(1) manual.") libdir;

    if not (is_directory library_path) then
      error (f_"VDDK library path %s not found or not a directory.  See \"INPUT FROM VDDK\" in the virt-v2v(1) manual.")
            library_path
  in

  (* Check that nbdkit is available and new enough. *)
  let error_unless_nbdkit_working () =
    if 0 <> Sys.command "nbdkit --version >/dev/null" then
      error (f_"nbdkit is not installed or not working.  It is required to use ‘--vddk’.  See \"INPUT FROM VDDK\" in the virt-v2v(1) manual.");

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
  in

  (* Check that the VDDK plugin is installed and working *)
  let error_unless_nbdkit_vddk_working () =
    let cmd =
      sprintf "LD_LIBRARY_PATH=%s nbdkit vddk --dump-plugin >/dev/null"
              (quote library_path) in
    if Sys.command cmd <> 0 then (
      (* See if we can diagnose why ... *)
      let cmd =
        sprintf "LD_LIBRARY_PATH=%s LANG=C nbdkit vddk --dump-plugin 2>&1 | grep -sq libvixDiskLib.so"
                (quote library_path) in
      let needs_library = Sys.command cmd = 0 in
      if not needs_library then
        error (f_"nbdkit VDDK plugin is not installed or not working.  It is required if you want to use VDDK.

The VDDK plugin is not enabled by default when you compile nbdkit.  You have to read the instructions in the nbdkit sources under ‘plugins/vddk/README.VDDK’ to find out how to enable the VDDK plugin.

See also \"INPUT FROM VDDK\" in the virt-v2v(1) manual.")
      else
        error (f_"nbdkit VDDK plugin is not installed or not working.  It is required if you want to use VDDK.

It looks like you did not set the right path in the ‘--vddk’ option, or your copy of the VDDK directory is incomplete.  There should be a library called ’%s/libvixDiskLib.so.?’.

See also \"INPUT FROM VDDK\" in the virt-v2v(1) manual.") library_path
    )
  in

  let error_unless_thumbprint () =
    if vddk_options.vddk_thumbprint = None then
      error (f_"You must pass the ‘--vddk-thumbprint’ option with the SSL thumbprint of the VMware server.  To find the thumbprint, see the nbdkit-vddk-plugin(1) manual.  See also \"INPUT FROM VDDK\" in the virt-v2v(1) manual.")
  in

  (* Check that nbdkit was compiled with SELinux support (for the
   * --selinux-label option).
   *)
  let error_unless_nbdkit_compiled_with_selinux () =
    let lines = external_command "nbdkit --dump-config" in
    (* In nbdkit <= 1.1.15 the selinux attribute was not present
     * at all in --dump-config output so there was no way to tell.
     * Ignore this case because there will be an error later when
     * we try to use the --selinux-label parameter.
     *)
    if List.mem "selinux=no" (List.map String.trim lines) then
      error (f_"nbdkit was compiled without SELinux support.  You will have to recompile nbdkit with libselinux-devel installed, or else set SELinux to Permissive mode while doing the conversion.")
  in

  (* List of passthrough parameters. *)
  let vddk_passthrus =
    [ "config",      (fun { vddk_config }      -> vddk_config);
      "cookie",      (fun { vddk_cookie }      -> vddk_cookie);
      "nfchostport", (fun { vddk_nfchostport } -> vddk_nfchostport);
      "port",        (fun { vddk_port }        -> vddk_port);
      "snapshot",    (fun { vddk_snapshot }    -> vddk_snapshot);
      "thumbprint",  (fun { vddk_thumbprint }  -> vddk_thumbprint);
      "transports",  (fun { vddk_transports }  -> vddk_transports);
      "vimapiver",   (fun { vddk_vimapiver }   -> vddk_vimapiver) ] in

object
  inherit input_libvirt password libvirt_uri guest as super

  method precheck () =
    error_unless_vddk_libdir ();
    error_unless_nbdkit_working ();
    error_unless_nbdkit_vddk_working ();
    error_unless_thumbprint ();
    if have_selinux then
      error_unless_nbdkit_compiled_with_selinux ()

  method as_options =
    let pt_options =
      String.concat "" (
        List.map (
          fun (name, get_field) ->
            match get_field vddk_options with
            | None -> ""
            | Some field -> sprintf " --vddk-%s %s" name field
        ) vddk_passthrus
      ) in
    sprintf "%s --vddk %s%s"
            super#as_options (* superclass prints "-i libvirt etc" *)
            vddk_options.vddk_libdir
            pt_options

  method source () =
    (* Get the libvirt XML.  This also checks (as a side-effect)
     * that the domain is not running.  (RHBZ#1138586)
     *)
    let xml = Libvirt_utils.dumpxml ?password ?conn:libvirt_uri guest in
    let source, disks = parse_libvirt_xml ?conn:libvirt_uri xml in

    (* Find the <vmware:moref> element from the XML.  This was added
     * in libvirt >= 3.7 and is required.
     *)
    let moref =
      let doc = Xml.parse_memory xml in
      let xpathctx = Xml.xpath_new_context doc in
      Xml.xpath_register_ns xpathctx
        "vmware" "http://libvirt.org/schemas/domain/vmware/1.0";
      let xpath_string = xpath_string xpathctx in
      match xpath_string "/domain/vmware:moref" with
      | Some moref -> moref
      | None ->
         error (f_"<vmware:moref> was not found in the output of ‘virsh dumpxml \"%s\"’.  The most likely reason is that libvirt is too old, try upgrading libvirt to ≥ 3.7.") guest in

    (* Create a temporary directory where we place the sockets and
     * password file.
     *)
    let tmpdir =
      let base_dir = (open_guestfs ())#get_cachedir () in
      let t = Mkdtemp.temp_dir ~base_dir "vddk." in
      (* tmpdir must be readable (but not writable) by "other" so that
       * qemu can open the sockets.  If we place a password file in
       * this directory then we'll chmod that to 0600 below.
       *)
      chmod t 0o755;
      rmdir_on_exit t;
      t in

    (* Start constructing the parts of the incredibly long nbdkit
     * command line which don't change between disks.
     *)
    let args =
      let add_arg, get_args =
        let args = ref [] in
        let add_arg a = List.push_front a args in
        let get_args () = List.rev !args in
        add_arg, get_args in

      (* It probably never happens that the server name can be missing
       * from the libvirt URI, but we need a server name to pass to
       * nbdkit, so ...
       *)
      let server =
        match parsed_uri.Xml.uri_server with
        | Some server -> server
        | None ->
           match libvirt_uri with
           | Some libvirt_uri ->
              error (f_"‘-ic %s’ URL does not contain a host name field")
                    libvirt_uri
           | None ->
              error (f_"you must use the ‘-ic’ parameter.  See \"INPUT FROM VDDK\" in the virt-v2v(1) manual.") in

      (* Similar to above, we also need a username to pass. *)
      let user =
        match parsed_uri.Xml.uri_user with
        | Some user -> user
        | None -> "root" (* ? *) in

      add_arg "nbdkit";
      if verbose () then add_arg "--verbose";
      add_arg "--readonly";         (* important! readonly mode *)
      add_arg "--foreground";       (* run in foreground *)
      add_arg "--exit-with-parent"; (* exit when virt-v2v exits *)
      add_arg "--newstyle";         (* use newstyle NBD protocol *)
      add_arg "--exportname"; add_arg "/";
      if have_selinux then (        (* label the socket so qemu can open it *)
        add_arg "--selinux-label"; add_arg "system_u:object_r:svirt_t:s0"
      );

      (* Name of the plugin.  Everything following is a plugin parameter. *)
      add_arg "vddk";

      let password_param =
        match password with
        | None ->
           (* nbdkit asks for the password interactively *)
           "password=-"
        | Some password ->
           let password_file = tmpdir // "password" in
           with_open_out password_file (
             fun chan ->
               fchmod (descr_of_out_channel chan) 0o600;
               output_string chan password
           );
           (* nbdkit reads the password from the file *)
           "password=+" ^ password_file in
      add_arg (sprintf "server=%s" server);
      add_arg (sprintf "user=%s" user);
      add_arg password_param;
      add_arg (sprintf "vm=moref=%s" moref);
      add_arg (sprintf "libdir=%s" libdir);

      (* The passthrough parameters. *)
      List.iter (
        fun (name, get_field) ->
          Option.may (fun field -> add_arg (sprintf "%s=%s" name field))
                     (get_field vddk_options)
      ) vddk_passthrus;

      get_args () in

    (* Create an nbdkit instance for each disk and rewrite the source
     * paths to point to the NBD socket.
     *)
    let disks = List.map (
      function
      | { p_source_disk = disk; p_source = P_dont_rewrite } ->
         disk

      | { p_source = P_source_dev _ } -> (* Should never happen. *)
         error (f_"source disk has <source dev=...> attribute in XML")

      | { p_source_disk = disk; p_source = P_source_file path } ->
         (* The <source file=...> attribute returned by the libvirt
          * VMX driver looks like "[datastore] path".  We can use it
          * directly as the nbdkit file= parameter, and it is passed
          * directly in this form to VDDK.
          *)

         let sock = tmpdir // sprintf "nbdkit%d.sock" disk.s_disk_id in
         let qemu_uri = sprintf "nbd:unix:%s:exportname=/" sock in

         let pidfile = tmpdir // sprintf "nbdkit%d.pid" disk.s_disk_id in

         (* Construct the final command line with the "static" args
          * above plus the args which vary for each disk.
          *)
         let args =
           args @ [ "--pidfile"; pidfile;
                    "--unix"; sock;
                    sprintf "file=%s" path ] in

         (* Print the full command we are about to run when debugging. *)
         if verbose () then (
           eprintf "running nbdkit:\n";
           eprintf "LD_LIBRARY_PATH=%s" library_path;
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
           putenv "LD_LIBRARY_PATH" library_path;
           execvp "nbdkit" args
         );

         (* Wait for the pidfile to appear so we know that nbdkit
          * is listening for requests.
          *)
         let rec loop i =
           if i = 0 then false
           else if Sys.file_exists pidfile then true
           else (
             sleep 1;
             loop (i-1)
           )
         in
         if not (loop 30) then (
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
               run_command ["chcon"; "system_u:object_r:svirt_image_t:s0";
                            sock]
           );
         );
         (* ... and the regular Unix permissions, in case qemu is
          * running as another user.
          *)
         chmod sock 0o777;

         (* nbdkit from a vddk source always presents us with the raw
          * disk blocks from the guest, so force the format to raw here.
          *)
         { disk with s_qemu_uri = qemu_uri;
                     s_format = Some "raw" }
     ) disks in

    if verbose () then (
      eprintf "vddk: tmpdir %s:\n%!" tmpdir;
      ignore (Sys.command (sprintf "ls -laZ %s" (quote tmpdir)))
    );

    { source with s_disks = disks }
end

let input_libvirt_vddk = new input_libvirt_vddk
