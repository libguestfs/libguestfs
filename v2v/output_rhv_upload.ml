(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

open Common_utils
open Unix_utils
open Common_gettext.Gettext

open Types
open Utils

type rhv_options = {
  rhv_cafile : string;
  rhv_cluster : string option;
  rhv_direct : bool;
  rhv_verifypeer : bool;
}

let print_output_options () =
  printf (f_"Output options (-oo) which can be used with -o rhv-upload:

  -oo rhv-cafile=CA.PEM           Set ‘ca.pem’ certificate bundle filename.
  -oo rhv-cluster=CLUSTERNAME     Set RHV cluster name.
  -oo rhv-direct[=true|false]     Use direct transfer mode (default: false).
  -oo rhv-verifypeer[=true|false] Verify server identity (default: false).
")

let parse_output_options options =
  let rhv_cafile = ref None in
  let rhv_cluster = ref None in
  let rhv_direct = ref false in
  let rhv_verifypeer = ref false in

  List.iter (
    function
    | "rhv-cafile", v ->
       if !rhv_cafile <> None then
         error (f_"-o rhv-upload: -oo rhv-cafile set twice");
       rhv_cafile := Some v
    | "rhv-cluster", v ->
       if !rhv_cluster <> None then
         error (f_"-o rhv-upload: -oo rhv-cluster set twice");
       rhv_cluster := Some v
    | "rhv-direct", "" -> rhv_direct := true
    | "rhv-direct", v -> rhv_direct := bool_of_string v
    | "rhv-verifypeer", "" -> rhv_verifypeer := true
    | "rhv-verifypeer", v -> rhv_verifypeer := bool_of_string v
    | k, _ ->
       error (f_"-o rhv-upload: unknown output option ‘-oo %s’") k
  ) options;

  let rhv_cafile =
    match !rhv_cafile with
    | Some s -> s
    | None ->
       error (f_"-o rhv-upload: must use ‘-oo rhv-cafile’ to supply the path to the oVirt or RHV user’s ‘ca.pem’ file") in
  let rhv_cluster = !rhv_cluster in
  let rhv_direct = !rhv_direct in
  let rhv_verifypeer = !rhv_verifypeer in

  { rhv_cafile; rhv_cluster; rhv_direct; rhv_verifypeer }

let pidfile_timeout = 30
let finalization_timeout = 5*60

class output_rhv_upload output_alloc output_conn
                        output_password output_storage
                        rhv_options =
  (* Create a temporary directory which will be deleted on exit. *)
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "rhvupload." in
    rmdir_on_exit t;
    t in

  let diskid_file_of_id id = tmpdir // sprintf "diskid.%d" id in

  (* Write the Python precheck, plugin and create VM to a temporary file. *)
  let precheck =
    let precheck = tmpdir // "rhv-upload-precheck.py" in
    with_open_out
      precheck
      (fun chan -> output_string chan Output_rhv_upload_precheck_source.code);
    precheck in
  let plugin =
    let plugin = tmpdir // "rhv-upload-plugin.py" in
    with_open_out
      plugin
      (fun chan -> output_string chan Output_rhv_upload_plugin_source.code);
    plugin in
  let createvm =
    let createvm = tmpdir // "rhv-upload-createvm.py" in
    with_open_out
      createvm
      (fun chan -> output_string chan Output_rhv_upload_createvm_source.code);
    createvm in

  (* Is SELinux enabled and enforcing on the host? *)
  let have_selinux =
    0 = Sys.command "getenforce 2>/dev/null | grep -isq Enforcing" in

  (* Check that the Python binary is available. *)
  let error_unless_python_binary_on_path () =
    try ignore (which "python")
    with Executable_not_found _ ->
      error (f_"no python binary called ‘%s’ can be found on the $PATH")
            "python"
  in

  (* Check that nbdkit is available and new enough. *)
  let error_unless_nbdkit_working () =
    if 0 <> Sys.command "nbdkit --version >/dev/null" then
      error (f_"nbdkit is not installed or not working.  It is required to use ‘-o rhv-upload’.  See \"OUTPUT TO RHV\" in the virt-v2v(1) manual.");

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

  (* Check that the python plugin is installed and working
   * and can load the plugin script.
   *)
  let error_unless_nbdkit_python_working () =
    let cmd = sprintf "nbdkit %s %s --dump-plugin >/dev/null"
                      "python" (quote plugin) in
    if Sys.command cmd <> 0 then
      error (f_"nbdkit Python plugin is not installed or not working.  It is required if you want to use ‘-o rhv-upload’.

See also \"OUTPUT TO RHV\" in the virt-v2v(1) manual.")
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

  (* Output format must be raw. *)
  let error_current_limitation required_param =
    error (f_"rhv-upload: currently you must use ‘%s’.  This restriction will be loosened in a future version.") required_param
  in

  (* JSON parameters which are invariant between disks. *)
  let json_params = [
    "verbose", JSON.Bool (verbose ());

    "output_conn", JSON.String output_conn;
    "output_password", JSON.String output_password;
    "output_storage", JSON.String output_storage;
    "output_sparse", JSON.Bool (match output_alloc with
                                | Sparse -> true
                                | Preallocated -> false);
    "rhv_cafile", JSON.String rhv_options.rhv_cafile;
    "rhv_cluster",
      JSON.String (match rhv_options.rhv_cluster with
                   | None -> "Default"
                   | Some s -> s);
    "rhv_direct", JSON.Bool rhv_options.rhv_direct;

    (* The 'Insecure' flag seems to be a number with various possible
     * meanings, however we just set it to True/False.
     *
     * https://github.com/oVirt/ovirt-engine-sdk/blob/19aa7070b80e60a4cfd910448287aecf9083acbe/sdk/lib/ovirtsdk4/__init__.py#L395
     *)
    "insecure", JSON.Bool (not rhv_options.rhv_verifypeer);
  ] in

  (* nbdkit command line args which are invariant between disks. *)
  let nbdkit_args =
    let args = [
      "nbdkit";

      "--foreground";           (* run in foreground *)
      "--exit-with-parent";     (* exit when virt-v2v exits *)
      "--newstyle";             (* use newstyle NBD protocol *)
      "--exportname"; "/";

      "python";                 (* use the nbdkit Python plugin *)
      plugin;                   (* Python plugin script *)
    ] in
    let args = if verbose () then args @ ["--verbose"] else args in
    let args =
      (* label the socket so qemu can open it *)
      if have_selinux then
        args @ ["--selinux-label"; "system_u:object_r:svirt_t:s0"]
      else args in
    args in

object
  inherit output

  method precheck () =
    error_unless_python_binary_on_path ();
    error_unless_nbdkit_working ();
    error_unless_nbdkit_python_working ();
    if have_selinux then
      error_unless_nbdkit_compiled_with_selinux ()

  method as_options =
    "-o rhv-upload" ^
    (match output_alloc with
     | Sparse -> "" (* default, don't need to print it *)
     | Preallocated -> " -oa preallocated") ^
    sprintf " -oc %s -op %s -os %s"
            output_conn output_password output_storage

  method supported_firmware = [ TargetBIOS ]

  (* rhev-apt.exe will be installed (if available). *)
  method install_rhev_apt = true

  method prepare_targets source targets =
    let output_name = source.s_name in
    let json_params =
      ("output_name", JSON.String output_name) :: json_params in

    (* Python code prechecks.  These can't run in #precheck because
     * we need to know the name of the virtual machine.
     *)
    let json_param_file = tmpdir // "params.json" in
    with_open_out
      json_param_file
      (fun chan -> output_string chan (JSON.string_of_doc json_params));
    if run_command [ "python"; precheck; json_param_file ] <> 0 then
      error (f_"failed server prechecks, see earlier errors");

    (* Create an nbdkit instance for each disk and set the
     * target URI to point to the NBD socket.
     *)
    List.map (
      fun t ->
        let id = t.target_overlay.ov_source.s_disk_id in
        let disk_name = sprintf "%s-%03d" output_name id in
        let json_params =
          ("disk_name", JSON.String disk_name) :: json_params in

        let disk_format =
          match t.target_format with
          | "raw" as fmt -> fmt
          | "qcow2" ->
             error_current_limitation "-of raw"
          | _ ->
             error (f_"rhv-upload: -of %s: Only output format ‘raw’ or ‘qcow2’ is supported.  If the input is in a different format then force one of these output formats by adding either ‘-of raw’ or ‘-of qcow2’ on the command line.")
                   t.target_format in
        let json_params =
          ("disk_format", JSON.String disk_format) :: json_params in

        let disk_size = t.target_overlay.ov_virtual_size in
        let json_params =
          ("disk_size", JSON.Int64 disk_size) :: json_params in

        (* Ask the plugin to write the disk ID to a special file. *)
        let diskid_file = diskid_file_of_id id in
        let json_params =
          ("diskid_file", JSON.String diskid_file) :: json_params in

        (* Write the JSON parameters to a file. *)
        let json_param_file = tmpdir // sprintf "params%d.json" id in
        with_open_out
          json_param_file
          (fun chan -> output_string chan (JSON.string_of_doc json_params));

        let sock = tmpdir // sprintf "nbdkit%d.sock" id in
        let pidfile = tmpdir // sprintf "nbdkit%d.pid" id in

        (* Add common arguments to per-target arguments. *)
        let args =
          nbdkit_args @ [ "--pidfile"; pidfile;
                          "--unix"; sock;
                          sprintf "params=%s" json_param_file ] in

        (* Print the full command we are about to run when debugging. *)
        if verbose () then (
          eprintf "running nbdkit:\n";
          List.iter (fun arg -> eprintf " %s" (quote arg)) args;
          prerr_newline ()
        );

        (* Start an nbdkit instance in the background.  By using
         * --exit-with-parent we don't have to worry about clean-up.
         *)
        let args = Array.of_list args in
        let pid = fork () in
        if pid = 0 then (
          (* Child process (nbdkit). *)
          execvp "nbdkit" args
        );

        (* Wait for the pidfile to appear so we know that nbdkit
         * is listening for requests.
         *)
        if not (wait_for_file pidfile pidfile_timeout) then (
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

        (* Tell ‘qemu-img convert’ to write to the nbd socket which is
         * connected to nbdkit.
         *)
        let json_params = [
          "file.driver", JSON.String "nbd";
          "file.path", JSON.String sock;
          "file.export", JSON.String "/";
        ] in
        let target_file =
          TargetURI ("json:" ^ JSON.string_of_doc json_params) in
        { t with target_file }
    ) targets

  method create_metadata source targets _ guestcaps inspect target_firmware =
    (* Get the UUIDs of each disk image.  These files are written
     * out by the nbdkit plugins on successful finalization of the
     * transfer.
     *)
    let nr_disks = List.length targets in
    let image_uuids =
      List.map (
        fun t ->
          let id = t.target_overlay.ov_source.s_disk_id in
          let diskid_file = diskid_file_of_id id in
          if not (wait_for_file diskid_file finalization_timeout) then
            error (f_"transfer of disk %d/%d failed, see earlier error messages")
                  (id+1) nr_disks;
          let diskid = read_whole_file diskid_file in
          diskid
      ) targets in

    (* We don't have the storage domain UUID, but instead we write
     * in a magic value which the Python code (which can get it)
     * will substitute.
     *)
    let sd_uuid = "@SD_UUID@" in

    (* The volume and VM UUIDs are made up. *)
    let vol_uuids = List.map (fun _ -> uuidgen ()) targets
    and vm_uuid = uuidgen () in

    (* Create the metadata. *)
    let ovf =
      OVF.create_ovf source targets guestcaps inspect
                            output_alloc
                            sd_uuid image_uuids vol_uuids vm_uuid
                            OVirt in
    let ovf = DOM.doc_to_string ovf in

    let json_param_file = tmpdir // "params.json" in
    with_open_out
      json_param_file
      (fun chan -> output_string chan (JSON.string_of_doc json_params));

    let ovf_file = tmpdir // "vm.ovf" in
    with_open_out ovf_file (fun chan -> output_string chan ovf);
    if run_command [ "python"; createvm; json_param_file; ovf_file ] <> 0 then
      error (f_"failed to create virtual machine, see earlier errors")

end

let output_rhv_upload = new output_rhv_upload
let () = Modules_list.register_output_module "rhv-upload"
