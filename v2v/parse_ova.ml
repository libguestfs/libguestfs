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
open Unix

open Std_utils
open Tools_utils
open Unix_utils
open Common_gettext.Gettext

open Utils
open Parse_ovf_from_ova

type t = {
  (* Save the original OVA name, for error messages. *)
  orig_ova : string;

  (* Top directory of OVA.  If the OVA was already a directory then
   * this is just that directory.  However in normal cases this is
   * a temporary directory that we create, unpacking either just the
   * OVF and MF files, or those plus the disks.  This temporary
   * directory will be cleaned up on exit.
   *)
  top_dir : string;

  ova_type : ova_type;
}

and ova_type =
  (* The original OVA was a directory.  Or the OVA was fully unpacked
   * into a temporary directory.
   *
   * In either case everything is available in [top_dir].
   *)
  | Directory

  (* The original OVA was an uncompressed tar file and we are able
   * to optimize access to the disks by keeping them in the tarball.
   *
   * The OVF and MF files only have been unpacked in [top_dir].
   *)
  | TarOptimized of string (* tarball *)

type file_ref =
  | LocalFile of string
  | TarFile of string * string

type mf_record = file_ref * Checksums.csum_t

let rec parse_ova ova =
  (* The spec allows a directory to be specified as an ova.  This
   * is also pretty convenient.
   *)
  let top_dir, ova_type =
    if is_directory ova then ova, Directory
    else (
      let tmpdir =
        let base_dir = (open_guestfs ())#get_cachedir () in
        let t = Mkdtemp.temp_dir ~base_dir "ova." in
        rmdir_on_exit t;
        t in

      match detect_file_type ova with
      | `Tar ->
         (* Normal ovas are tar file (not compressed). *)

         (* In newer QEMU we don't have to extract everything.
          * We can access disks inside the tar archive directly.
          *)
         if qemu_img_supports_offset_and_size () &&
            libvirt_supports_json_raw_driver () &&
            (untar_metadata ova tmpdir;
             no_disks_are_compressed ova tmpdir) then
           tmpdir, TarOptimized ova
         else (
           (* If qemu/libvirt is too old or any disk is compressed
            * then we must fall back on the slow path.
            *)
           untar ova tmpdir;
           tmpdir, Directory
         )

      | `Zip ->
         (* However, although not permitted by the spec, people ship
          * zip files as ova too.
          *)
         let cmd =
           [ "unzip" ] @ (if verbose () then [] else [ "-q" ]) @
           [ "-j"; "-d"; tmpdir; ova ] in
         if run_command cmd <> 0 then
           error (f_"error unpacking %s, see earlier error messages") ova;
         tmpdir, Directory

      | (`GZip|`XZ) as format ->
         (match uncompressed_type format ova with
          | `Tar ->
             untar ~format ova tmpdir;
             tmpdir, Directory
          | `Zip | `GZip | `XZ | `Unknown ->
             error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
         )

      | `Unknown ->
         error (f_"%s: unsupported file format\n\nFormats which we currently understand for '-i ova' are: tar (uncompressed, compress with gzip or xz), zip") ova
    ) in

  (* Exploded path must be absolute (RHBZ#1155121). *)
  let top_dir = absolute_path top_dir in

  (* If virt-v2v is running as root, and the backend is libvirt, then
   * we have to chmod the directory to 0755 and files to 0644
   * so it is readable by qemu.qemu.  This is libvirt bug RHBZ#890291.
   *)
  if Unix.geteuid () = 0 && backend_is_libvirt () then (
    warning (f_"making OVA directory public readable to work around libvirt bug https://bugzilla.redhat.com/1045069");
    let what =
      match ova_type with
      | Directory -> [ top_dir ]
      | TarOptimized ova -> [ top_dir; ova ] in
    let cmd = [ "chmod"; "-R"; "go=u,go-w" ] @ what in
    ignore (run_command cmd)
  );

  { orig_ova = ova; top_dir; ova_type }

(* Return true if [libvirt] supports ["json:"] pseudo-URLs and accepts the
 * ["raw"] driver. Function also returns true if [libvirt] backend is not
 * used.  This didn't work in libvirt < 3.1.0.
 *)
and libvirt_supports_json_raw_driver () =
  if backend_is_libvirt () then (
    let sup = Libvirt_utils.libvirt_get_version () >= (3, 1, 0) in
    debug "libvirt supports  \"raw\" driver in json URL: %B" sup;
    sup
  )
  else
    true

(* No disks compressed?  We need to check the OVF file. *)
and no_disks_are_compressed ova tmpdir =
  let t = { orig_ova = ova; top_dir = tmpdir; ova_type = Directory } in
  let ovf = get_ovf_file t in
  let disks = parse_disks ovf in
  not (List.exists (fun { compressed } -> compressed) disks)

and pigz_available =
  let test = lazy (shell_command "pigz --help >/dev/null 2>&1" = 0) in
  fun () -> Lazy.force test

and pxz_available =
  let test = lazy (shell_command "pxz --help >/dev/null 2>&1" = 0) in
  fun () -> Lazy.force test

and zcat_command_of_format = function
  | `GZip ->
     if pigz_available () then "pigz -c -d" else "gzip -c -d"
  | `XZ ->
     if pxz_available () then "pxz -c -d" else "xz -c -d"

(* Untar part or all files from tar archive. If [paths] is specified it is
 * a list of paths in the tar archive.
 *)
and untar ?format ?(paths = []) file outdir =
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
and untar_metadata file outdir =
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
and uncompress_head format file =
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
and uncompressed_type format file =
  let head, headlen = uncompress_head format file in
  let tmpfile, chan =
    Filename.open_temp_file "ova.file." "" in
  output chan head 0 headlen;
  close_out chan;
  let ret = detect_file_type tmpfile in
  Sys.remove tmpfile;
  ret

(* Find files in [dir] ending with [ext]. *)
and find_files dir ext =
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

and get_ovf_file { orig_ova; top_dir } =
  let ovf = find_files top_dir ".ovf" in
  match ovf with
  | [] ->
     error (f_"no .ovf file was found in %s") orig_ova
  | [x] -> x
  | _ :: _ ->
     error (f_"more than one .ovf file was found in %s") orig_ova

let rex = PCRE.compile "^(SHA1|SHA256)\\((.*)\\)= ([0-9a-fA-F]+)\r?$"

let get_manifest { top_dir; ova_type } =
  let mf_files = find_files top_dir ".mf" in
  let manifest =
    List.map (
      fun mf ->
        debug "ova: processing manifest file %s" mf;
        (*               (1)                 (2)
         * mf:           <top_dir>/bar.mf    <top_dir>/foo/bar.mf
         * mf_folder:    <top_dir>           <top_dir>/foo
         * mf_subfolder: ""                  foo
         *)
        let mf_folder = Filename.dirname mf in
        let mf_subfolder =
          if String.is_prefix mf_folder (top_dir // "") then ( (* 2 *)
            let len = String.length top_dir + 1 in
            String.sub mf_folder len (String.length mf_folder - len)
          )
          else if top_dir = mf_folder then "" (* 1 *)
          else assert false in
        with_open_in mf (
          fun chan ->
            let ret = ref [] in
            let rec loop () =
              let line = input_line chan in
              if PCRE.matches rex line then (
                let csum_type = PCRE.sub 1
                and filename = PCRE.sub 2
                and expected = PCRE.sub 3 in
                let csum = Checksums.of_string csum_type expected in
                let file_ref =
                  match ova_type with
                  | Directory ->
                     LocalFile (mf_folder // filename)
                  | TarOptimized tar ->
                     TarFile (tar, mf_subfolder // filename) in
                List.push_front (file_ref, csum) ret
              )
              else
                warning (f_"unable to parse line from manifest file: %S") line;
              loop ()
            in
            (try loop () with End_of_file -> ());
            !ret
        )
    ) mf_files in

  List.flatten manifest

let get_file_list { top_dir; ova_type } =
  match ova_type with
  | Directory ->
     let cmd = sprintf "cd %s && find -type f" (quote top_dir) in
     let files = external_command cmd in
     let files = List.sort compare files in
     List.map (fun filename -> LocalFile (top_dir // filename)) files

  | TarOptimized tar ->
     let cmd = sprintf "tar -tf %s" (quote tar) in
     let files = external_command cmd in
     (* Don't include directories in the final list. *)
     let files = List.filter (fun s -> not (String.is_suffix s "/")) files in
     let files = List.sort compare files in
     List.map (fun filename -> TarFile (tar, filename)) files

let resolve_href ({ top_dir; ova_type } as t) href =
  let ovf = get_ovf_file t in
  let ovf_folder = Filename.dirname ovf in

  (* Since [href] comes from an untrusted source, we must ensure
   * that it doesn't reference a path outside [top_dir].  An
   * additional complication is that [href] is relative to
   * the directory containing the OVF ([ovf_folder]).  A further
   * complication is that the file might not exist at all.
   *)
  match ova_type with
  | Directory ->
     let filename = ovf_folder // href in
     let real_top_dir = Realpath.realpath top_dir in
     (try
        let filename = Realpath.realpath filename in
        if not (String.is_prefix filename real_top_dir) then
          error (f_"-i ova: invalid OVA file: path ‘%s’ references a file outside the archive") href;
        Some (LocalFile filename)
      with
        Unix_error (ENOENT, "realpath", _) -> None
     )

  | TarOptimized tar ->
     (* Security: Since the only thing we will do with the computed
      * filename is to call get_tar_offet_and_size, it doesn't
      * matter if the filename is bogus or references some file
      * on the filesystem outside the tarball.  Therefore we don't
      * need to do any sanity checking here.
      *)

     (*             (1)                 (2)
      * ovf:        <top_dir>/bar.ovf   <top_dir>/foo/bar.ovf
      * ovf_folder: <top_dir>           <top_dir>/foo
      * subdir:     ""                  foo
      * filename:   href                foo/href
      *)
     let filename =
       if String.is_prefix ovf_folder (top_dir // "") then ( (* 2 *)
         let len = String.length top_dir + 1 in
         String.sub ovf_folder len (String.length ovf_folder - len) // href
       )
       else if top_dir = ovf_folder then href (* 1 *)
       else assert false in

     (* Does the file exist in the tarball? *)
     let cmd = sprintf "tar tf %s %s >/dev/null 2>&1"
                       (quote tar) (quote filename) in
     debug "ova: testing if %s exists in %s" filename tar;
     if Sys.command cmd = 0 then (
       debug "ova: file exists";
       Some (TarFile (tar, filename))
     )
     else (
       debug "ova: file does not exist";
       None
     )

let ws = PCRE.compile "\\s+"
let re_tar_message = PCRE.compile "\\*\\* [^*]+ \\*\\*$"

let get_tar_offet_and_size tar filename =
  let lines = external_command (sprintf "tar tRvf %s" (Filename.quote tar)) in
  let rec loop lines =
    match lines with
    | [] -> raise Not_found
    | line :: lines -> (
      (* Lines have the form:
       * block <offset>: <perms> <owner>/<group> <size> <mdate> <mtime> <file>
       * or:
       * block <offset>: ** Block of NULs **
       * block <offset>: ** End of File **
       *)
      if PCRE.matches re_tar_message line then
        loop lines (* ignore "** Block of NULs **" etc. *)
      else (
        let elems = PCRE.nsplit ~max:8 ws line in
        if List.length elems = 8 && List.hd elems = "block" then (
          let elems = Array.of_list elems in
          let offset = elems.(1) in
          let size = elems.(4) in
          let fname = elems.(7) in

          if fname <> filename then
            loop lines
          else (
            let offset =
              try
                (* There should be a colon at the end *)
                let i = String.rindex offset ':' in
                if i == (String.length offset)-1 then
                  Int64.of_string (String.sub offset 0 i)
                else
                  failwith "colon at wrong position"
              with Failure _ | Not_found ->
                failwithf (f_"invalid offset returned by tar: %S") offset in

            let size =
              try Int64.of_string size
              with Failure _ ->
                failwithf (f_"invalid size returned by tar: %S") size in

            (* Note: Offset is actually block number and there is a single
             * block with tar header at the beginning of the file. So skip
             * the header and convert the block number to bytes before
             * returning.
             *)
            (offset +^ 1L) *^ 512L, size
          )
        )
        else
          failwithf (f_"failed to parse line returned by tar: %S") line
      )
    )
  in
  loop lines
