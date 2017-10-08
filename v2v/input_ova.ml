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

open Printf

open Std_utils
open Tools_utils
open Unix_utils
open Common_gettext.Gettext

open Types
open Utils
open Parse_ovf_from_ova
open Name_from_disk

(* Return true if [libvirt] supports ["json:"] pseudo-URLs and accepts the
 * ["raw"] driver. Function also returns true if [libvirt] backend is not
 * used.  This didn't work in libvirt < 3.1.0.
 *)
let libvirt_supports_json_raw_driver () =
  if backend_is_libvirt () then (
    let sup = Libvirt_utils.libvirt_get_version () >= (3, 1, 0) in
    debug "libvirt supports  \"raw\" driver in json URL: %B" sup;
    sup
  )
  else
    true

let pigz_available =
  let test = lazy (shell_command "pigz --help >/dev/null 2>&1" = 0) in
  fun () -> Lazy.force test

let pxz_available =
  let test = lazy (shell_command "pxz --help >/dev/null 2>&1" = 0) in
  fun () -> Lazy.force test

let zcat_command_of_format = function
  | `GZip ->
     if pigz_available () then "pigz -c -d" else "gzip -c -d"
  | `XZ ->
     if pxz_available () then "pxz -c -d" else "xz -c -d"

(* Untar part or all files from tar archive. If [paths] is specified it is
 * a list of paths in the tar archive.
 *)
let untar ?format ?(paths = []) file outdir =
  let paths = String.concat " " (List.map quote paths) in
  let cmd =
    match format with
    | None ->
       sprintf "tar -xf %s -C %s %s"
               (quote file) (quote outdir) paths
    | Some ((`GZip|`XZ) as format) ->
       sprintf "%s %s | tar -xf - -C %s %s"
               (zcat_command_of_format format) (quote file)
               (quote outdir) paths in
  if shell_command cmd <> 0 then
    error (f_"error unpacking %s, see earlier error messages") file

(* Untar only ovf and manifest from the archive *)
let untar_metadata file outdir =
  let files = external_command (sprintf "tar -tf %s" (Filename.quote file)) in
  let files =
    List.filter_map (
      fun f ->
        if Filename.check_suffix f ".ovf" ||
           Filename.check_suffix f ".mf" then Some f
        else None
    ) files in
  untar ~paths:files file outdir

(* Uncompress the first few bytes of [file] and return it as
 * [(bytes, len)].
 *)
let uncompress_head format file =
  let cmd = sprintf "%s %s" (zcat_command_of_format format) (quote file) in
  let chan_out, chan_in, chan_err = Unix.open_process_full cmd [||] in
  let b = Bytes.create 512 in
  let len = input chan_out b 0 (Bytes.length b) in
  (* We're expecting the subprocess to fail because we close
   * the pipe early, so:
   *)
  ignore (Unix.close_process_full (chan_out, chan_in, chan_err));
  b, len

(* Run [detect_file_type] on a compressed file, returning the
 * type of the uncompressed content (if known).
 *)
let uncompressed_type format file =
  let head, headlen = uncompress_head format file in
  let tmpfile, chan =
    Filename.open_temp_file "ova.file." "" in
  output chan head 0 headlen;
  close_out chan;
  let ret = detect_file_type tmpfile in
  Sys.remove tmpfile;
  ret

(* Find files in [dir] ending with [ext]. *)
let find_files dir ext =
  let rec loop = function
    | [] -> []
    | dir :: rest ->
       let files = Array.to_list (Sys.readdir dir) in
       let files = List.map (Filename.concat dir) files in
       let dirs, files = List.partition Sys.is_directory files in
       let files =
         List.filter (fun x -> Filename.check_suffix x ext) files in
       files @ loop (rest @ dirs)
  in
  loop [dir]

class input_ova ova =
  let tmpdir =
    let base_dir = (open_guestfs ())#get_cachedir () in
    let t = Mkdtemp.temp_dir ~base_dir "ova." in
    rmdir_on_exit t;
    t in
object
  inherit input

  method as_options = "-i ova " ^ ova

  method source () =
    (* Extract ova file. *)
    let exploded, partial =
      (* The spec allows a directory to be specified as an ova.  This
       * is also pretty convenient.
       *)
      if is_directory ova then ova, false
      else (
        match detect_file_type ova with
        | `Tar ->
          (* Normal ovas are tar file (not compressed). *)
          if qemu_img_supports_offset_and_size () &&
              libvirt_supports_json_raw_driver () then (
            (* In newer QEMU we don't have to extract everything.
             * We can access disks inside the tar archive directly.
             *)
            untar_metadata ova tmpdir;
            tmpdir, true
          ) else (
            untar ova tmpdir;
            tmpdir, false
          )

        | `Zip ->
          (* However, although not permitted by the spec, people ship
           * zip files as ova too.
           *)
          let cmd = [ "unzip" ] @
            (if verbose () then [] else [ "-q" ]) @
            [ "-j"; "-d"; tmpdir; ova ] in
          if run_command cmd <> 0 then
            error (f_"error unpacking %s, see earlier error messages") ova;
          tmpdir, false

        | (`GZip|`XZ) as format ->
          (match uncompressed_type format ova with
          | `Tar ->
             untar ~format ova tmpdir;
             tmpdir, false
          | `Zip | `GZip | `XZ | `Unknown ->
            error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
          )

        | `Unknown ->
          error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
      ) in

    (* Exploded path must be absolute (RHBZ#1155121). *)
    let exploded = absolute_path exploded in

    (* If virt-v2v is running as root, and the backend is libvirt, then
     * we have to chmod the directory to 0755 and files to 0644
     * so it is readable by qemu.qemu.  This is libvirt bug RHBZ#890291.
     *)
    if Unix.geteuid () = 0 && backend_is_libvirt () then (
      warning (f_"making OVA directory public readable to work around libvirt bug https://bugzilla.redhat.com/1045069");
      let cmd = [ "chmod"; "-R"; "go=u,go-w"; exploded ] @
                if partial then [ ova ] else [] in
      ignore (run_command cmd)
    );

    (* Search for the ovf file. *)
    let ovf = find_files exploded ".ovf" in
    let ovf =
      match ovf with
      | [] ->
        error (f_"no .ovf file was found in %s") ova
      | [x] -> x
      | _ :: _ ->
        error (f_"more than one .ovf file was found in %s") ova in

    (* Read any .mf (manifest) files and verify sha1. *)
    let mf = find_files exploded ".mf" in
    let rex = PCRE.compile "^(SHA1|SHA256)\\((.*)\\)= ([0-9a-fA-F]+)\r?$" in
    List.iter (
      fun mf ->
        debug "processing manifest %s" mf;
        let mf_folder = Filename.dirname mf in
        let mf_subfolder = subdirectory exploded mf_folder in
        with_open_in mf (
          fun chan ->
            let rec loop () =
              let line = input_line chan in
              if PCRE.matches rex line then (
                let mode = PCRE.sub 1
                and disk = PCRE.sub 2
                and expected = PCRE.sub 3 in
                let csum = Checksums.of_string mode expected in
                try
                  if partial then
                    Checksums.verify_checksum csum
                                              ~tar:ova (mf_subfolder // disk)
                  else
                    Checksums.verify_checksum csum (mf_folder // disk)
                with Checksums.Mismatched_checksum (_, actual) ->
                  error (f_"checksum of disk %s does not match manifest %s (actual %s(%s) = %s, expected %s(%s) = %s)")
                        disk mf mode disk actual mode disk expected;
              )
              else
                warning (f_"unable to parse line from manifest file: %S") line;
              loop ()
            in
            (try loop () with End_of_file -> ())
        )
    ) mf;

    let ovf_folder = Filename.dirname ovf in

    (* Parse the ovf file. *)
    let name, memory, vcpu, cpu_sockets, cpu_cores, firmware,
        disks, removables, nics =
      parse_ovf_from_ova ovf in

    let name =
      match name with
      | None ->
         warning (f_"could not parse ovf:Name from OVF document");
         name_from_disk ova
      | Some name -> name in

    let disks = List.map (
      fun ({ href; compressed } as disk) ->
        let partial =
          if compressed && partial then (
            (* We cannot access compressed disk inside the tar;
             * we have to extract it.
             *)
            untar ~paths:[(subdirectory exploded ovf_folder) // href]
                  ova tmpdir;
            false
          )
          else
            partial in

        let filename =
          if partial then
            (subdirectory exploded ovf_folder) // href
          else (
            (* Does the file exist and is it readable? *)
            Unix.access (ovf_folder // href) [Unix.R_OK];
            ovf_folder // href
          ) in

        (* The spec allows the file to be gzip-compressed, in which case
         * we must uncompress it into the tmpdir.
         *)
        let filename =
          if compressed then (
            let new_filename = tmpdir // String.random8 () ^ ".vmdk" in
            let cmd =
              sprintf "zcat %s > %s" (quote filename) (quote new_filename) in
            if shell_command cmd <> 0 then
              error (f_"error uncompressing %s, see earlier error messages")
                    filename;
            new_filename
          )
          else filename in

        let qemu_uri =
          if not partial then (
            filename
          )
          else (
            let offset, size =
              try find_file_in_tar ova filename
              with
              | Not_found ->
                 error (f_"file ‘%s’ not found in the ova") filename
              | Failure msg -> error (f_"%s") msg in
            (* QEMU requires size aligned to 512 bytes. This is safe because
             * tar also works with 512 byte blocks.
             *)
            let size = roundup64 size 512L in

            (* Workaround for libvirt bug RHBZ#1431652. *)
            let ova_path = absolute_path ova in

            let doc = [
                "file", JSON.Dict [
                            "driver", JSON.String "raw";
                            "offset", JSON.Int64 offset;
                            "size", JSON.Int64 size;
                            "file", JSON.Dict [
                                        "driver", JSON.String "file";
                                        "filename", JSON.String ova_path]
                          ]
              ] in
            let uri =
              sprintf "json:%s" (JSON.string_of_doc ~fmt:JSON.Compact doc) in
            debug "json: %s" uri;
            uri
          ) in

        { disk.source_disk with s_qemu_uri = qemu_uri }
     ) disks in

    let source = {
      s_hypervisor = VMware;
      s_name = name;
      s_orig_name = name;
      s_memory = memory;
      s_vcpu = vcpu;
      s_cpu_vendor = None;
      s_cpu_model = None;
      s_cpu_sockets = cpu_sockets;
      s_cpu_cores = cpu_cores;
      s_cpu_threads = None; (* XXX *)
      s_features = []; (* XXX *)
      s_firmware = firmware;
      s_display = None; (* XXX *)
      s_video = None;
      s_sound = None;
      s_disks = disks;
      s_removables = removables;
      s_nics = nics;
    } in

    source
end

let input_ova = new input_ova
let () = Modules_list.register_input_module "ova"
