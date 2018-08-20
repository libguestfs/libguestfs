(* virt-builder
 * Copyright (C) 2016-2018 SUSE Inc.
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

open Std_utils
open Common_gettext.Gettext
open Tools_utils
open Unix_utils
open Getopt.OptionName
open Utils
open Yajl
open Xpath_helpers

open Printf

type cmdline = {
  gpg : string;
  gpgkey : string option;
  interactive : bool;
  compression : bool;
  repo : string;
}

type disk_image_info = {
  format : string;
  size : int64;
}

let parse_cmdline () =
  let gpg = ref "gpg" in
  let gpgkey = ref None in
  let set_gpgkey arg = gpgkey := Some arg in

  let interactive = ref false in
  let compression = ref true in

  let argspec = [
    [ L"gpg" ], Getopt.Set_string ("gpg", gpg), s_"Set GPG binary/command";
    [ S 'K'; L"gpg-key" ], Getopt.String ("gpgkey", set_gpgkey),
      s_"ID of the GPG key to sign the repo with";
    [ S 'i'; L"interactive" ], Getopt.Set interactive, s_"Ask the user about missing data";
    [ L"no-compression" ], Getopt.Clear compression, s_"Don’t compress the new images in the index";
  ] in

  let args = ref [] in
  let anon_fun s = List.push_front s args in
  let usage_msg =
    sprintf (f_"\
%s: create a repository for virt-builder

  virt-builder-repository REPOSITORY_PATH

A short summary of the options is given below.  For detailed help please
read the man page virt-builder-repository(1).
")
      prog in
  let opthandle = create_standard_options argspec ~anon_fun ~machine_readable:true usage_msg in
  Getopt.parse opthandle;

  (* Machine-readable mode?  Print out some facts about what
   * this binary supports.
   *)
  if machine_readable () then (
    printf "virt-builder-repository\n";
    exit 0
  );

  (* Dereference options. *)
  let args = List.rev !args in
  let gpg = !gpg in
  let gpgkey = !gpgkey in
  let interactive = !interactive in
  let compression = !compression in

  (* Check options *)
  let repo =
    match args with
    | [repo] -> repo
    | [] ->
      error (f_"virt-builder-repository /path/to/repo

Use ‘/path/to/repo’ to point to the repository folder.")
    | _ ->
      error (f_"too many parameters, only one path to repository is allowed") in

  {
    gpg = gpg;
    gpgkey = gpgkey;
    interactive = interactive;
    compression = compression;
    repo = repo;
  }

let do_mv src dest =
  let cmd = [ "mv"; src; dest ] in
  let r = run_command cmd in
  if r <> 0 then
    error (f_"moving file ‘%s’ to ‘%s’ failed") src dest

let checksums_get_sha512 = function
  | None -> None
  | Some csums ->
    let rec loop = function
    | [] -> None
    | Checksums.SHA512 csum :: _ -> Some (Checksums.SHA512 csum)
    | _ :: rest -> loop rest
    in
    loop csums

let osinfo_ids = ref None

let rec osinfo_get_short_ids () =
  match !osinfo_ids with
  | Some ids -> ids
  | None ->
    osinfo_ids :=
      Some (
        Osinfo.fold (
          fun set filepath ->
            let doc = Xml.parse_file filepath in
            let xpathctx = Xml.xpath_new_context doc in
            let nodes = xpath_get_nodes xpathctx "/libosinfo/os/short-id" in
            List.fold_left (
              fun set node ->
                let id = Xml.node_as_string node in
                StringSet.add id set
            ) set nodes
        ) StringSet.empty
      );
    osinfo_get_short_ids ()

let compress_to file outdir =
  let outimg = outdir // Filename.basename file ^ ".xz" in

  info "Compressing ...";
  let cmd = [ "xz"; "-f"; "--best"; "--block-size=16777216"; "-c"; file ] in
  let file_flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC; ] in
  let outfd = Unix.openfile outimg file_flags 0o666 in
  let res = run_command cmd ~stdout_fd:outfd in
  if res <> 0 then
    error (f_"‘xz’ command failed");
  outimg

let get_mime_type filepath =
  let file_cmd = "file --mime-type --brief " ^ (quote filepath) in
  match external_command file_cmd with
  | [] -> None
  | line :: _ -> Some line

let get_disk_image_info filepath =
  let infos = get_image_infos filepath in
  {
    format = object_get_string "format" infos;
    size = object_get_number "virtual-size" infos
  }

let cmp a b =
  Index.string_of_arch a = Index.string_of_arch b

let has_entry id arch index =
  List.exists (
    fun (item_id, { Index.arch = item_arch }) ->
      item_id = id && cmp item_arch arch
  ) index

let process_image acc_entries filename repo tmprepo index interactive
                  compression sigchecker =
  message (f_"Preparing %s") filename;

  let filepath = repo // filename in
  let { format; size } = get_disk_image_info filepath in
  let out_path =
    if not compression then filepath
    else compress_to filepath tmprepo in
  let out_filename = Filename.basename out_path in
  let checksum = Checksums.compute_checksum "sha512" out_path in
  let compressed_size = (Unix.LargeFile.stat out_path).Unix.LargeFile.st_size in

  let ask ~default ?values message =
    printf "%s [%s] " message default;
    (match values with
    | None -> ()
    | Some x ->
      printf (f_"Choose one from the list below:\n %s\n")
      (String.concat "\n " x));
    let value = read_line () in

    if value = "" then
      default
    else
      value
  in

  let re_valid_id = PCRE.compile ~anchored:true "[-a-zA-Z0-9_.]+" in
  let rec ask_id default =
    let id = ask (s_"Identifier: ") ~default in
    if not (PCRE.matches re_valid_id id) then (
      warning (f_"Allowed characters are letters, digits, - _ and .");
      ask_id default
    ) else
      id in

  let ask_arch guess =
    let arches = [ "x86_64"; "aarch64"; "armv7l"; "i686"; "ppc64"; "ppc64le"; "s390x" ] in
    Index.Arch (ask (s_"Architecture: ") ~default:guess ~values:arches)
  in

  let ask_osinfo default =
    let osinfo = ask (s_ "osinfo short ID: ") ~default in
    let osinfo_ids = osinfo_get_short_ids () in
    if not (StringSet.mem osinfo osinfo_ids) then
      warning (f_"‘%s’ is not a recognized osinfo OS id; using it anyway") osinfo;
    osinfo in

  let extract_entry_data ?entry () =
    message (f_"Extracting data from the image...");
    let g = Tools_utils.open_guestfs () in
    g#add_drive_ro filepath;
    g#launch ();

    let roots = g#inspect_os () in
    let nroots = Array.length roots in
    if nroots <> 1 then
      error (f_"virt-builder template images must have one and only one root file system, found %d")
            nroots;

    let root = Array.get roots 0 in
    let inspected_arch = g#inspect_get_arch root in
    let product = g#inspect_get_product_name root in
    let shortid = g#inspect_get_osinfo root in
    let lvs = g#lvs () in
    let filesystems = g#inspect_get_filesystems root in

    g#close ();

    let id =
      match entry with
      | Some (id, _) -> id
      | None -> (
        if interactive then ask_id shortid
        else error (f_"missing image identifier")
      ) in

    let arch =
      match entry with
      | Some (_, { Index.arch }) -> (
        match arch with
        | Index.Arch arch -> Index.Arch arch
        | Index.GuessedArch arch ->
          if interactive then ask_arch arch
          else Index.Arch arch )
      | None ->
        if interactive then ask_arch inspected_arch
        else Index.Arch inspected_arch in

    if has_entry id arch acc_entries then (
      let arch =
        match arch with
        | Index.Arch arch
        | Index.GuessedArch arch -> arch in
      error (f_"Already existing image with id %s and architecture %s") id arch
    );

    let printable_name =
      match entry with
      | Some (_, { Index.printable_name }) ->
        if printable_name = None then
          if interactive then Some (ask (s_"Display name: ") ~default:product)
          else Some product
        else
          printable_name
      | None -> Some product in

    let osinfo =
      match entry with
      | Some (_, { Index.osinfo }) ->
        if osinfo = None then
          Some (if interactive then ask_osinfo shortid else shortid)
        else
          osinfo
      | None ->
        Some (if interactive then ask_osinfo shortid else shortid) in

    let expand =
      match entry with
      | Some (_, { Index.expand }) ->
        if expand = None then
          if interactive then
            Some (ask (s_"Expandable partition: ") ~default:root
                      ~values:(Array.to_list filesystems))
          else Some root
        else
          expand
      | None ->
        if interactive then
          Some (ask (s_"Expandable partition: ") ~default:root
                    ~values:(Array.to_list filesystems))
        else Some root in

    let lvexpand =
      if lvs = [||] then
        None
      else
        match entry with
        | Some (_, { Index.lvexpand }) ->
          if lvexpand = None then
            if interactive then
              Some (ask (s_"Expandable volume: ") ~values:(Array.to_list lvs)
                    ~default:(Array.get lvs 0))
            else Some (Array.get lvs 0)
          else
            lvexpand
        | None ->
          if interactive then
            Some (ask (s_"Expandable volume: ") ~values:(Array.to_list lvs)
                  ~default:(Array.get lvs 0))
          else Some (Array.get lvs 0) in

    let revision =
      match entry with
      | Some (_, { Index.revision }) ->
        Utils.increment_revision revision
      | None -> Rev_int 1 in

    let notes =
      match entry with
      | Some (_, { Index.notes }) -> notes
      | None -> [] in

    let hidden =
      match entry with
      | Some (_, { Index.hidden }) -> hidden
      | None -> false in

    let aliases =
      match entry with
      | Some (_, { Index.aliases }) -> aliases
      | None -> None in

    (id, { Index.printable_name;
           osinfo;
           file_uri = Filename.basename out_path;
           arch;
           signature_uri = None;
           checksums = Some [checksum];
           revision;
           format = Some format;
           size;
           compressed_size = Some compressed_size;
           expand;
           lvexpand;
           notes;
           hidden;
           aliases;
           sigchecker;
           proxy = Curl.SystemProxy })
  in

  (* Do we have an entry for that file already? *)
  let file_entry =
    try
      List.hd (
        List.filter (
          fun (_, { Index.file_uri }) ->
            let basename = Filename.basename file_uri in
            basename = out_filename || basename = filename
        ) index
      )
    with
    | Failure _ -> extract_entry_data () in

  let _, { Index.checksums } = file_entry in
  let old_checksum = checksums_get_sha512 checksums in

  match old_checksum with
  | Some old_sum ->
      if old_sum = checksum then
        let id, entry = file_entry in
        (id, { entry with Index.file_uri = out_filename })
      else
        extract_entry_data ~entry:file_entry ()
  | None ->
    extract_entry_data ~entry:file_entry ()

let unsafe_remove_directory_prefix parent path =
  if path = parent then
    ""
  else if String.is_prefix path (parent // "") then (
    let len = String.length parent in
    String.sub path (len+1) (String.length path - len-1)
  ) else
    invalid_arg (sprintf "%S is not a path prefix of %S" parent path)

let main () =
  let cmdline = parse_cmdline () in

  (* If debugging, echo the command line arguments. *)
  debug "command line: %s" (String.concat " " (Array.to_list Sys.argv));

  (* Check that the paths are existing *)
  if not (Sys.file_exists cmdline.repo) then
    error (f_"repository folder ‘%s’ doesn’t exist") cmdline.repo;

  (* Create a temporary folder to work in *)
  let tmpdir = Mkdtemp.temp_dir ~base_dir:cmdline.repo
                                "virt-builder-repository." in
  rmdir_on_exit tmpdir;

  let tmprepo = tmpdir // "repo" in
  mkdir_p tmprepo 0o700;

  let sigchecker = Sigchecker.create ~gpg:cmdline.gpg
                                     ~check_signature:false
                                     ~gpgkey:No_Key
                                     ~tmpdir in

  let index =
    try
      let index_filename =
        List.find (
          fun filename -> Sys.file_exists (cmdline.repo // filename)
        ) [ "index.asc"; "index" ] in

      let downloader = Downloader.create ~curl:"do-not-use-curl"
                                         ~cache:None ~tmpdir in

      let source = { Sources.name = index_filename;
                     uri = cmdline.repo // index_filename;
                     gpgkey = No_Key;
                     proxy = Curl.SystemProxy;
                     format = Sources.FormatNative } in

      Index_parser.get_index ~downloader ~sigchecker ~template:true source
    with Not_found -> [] in

  (* Check for index/interactive consistency *)
  if not cmdline.interactive && index = [] then
    error (f_"the repository must contain an index file when running in automated mode");

  debug "Searching for images ...";

  let images =
    let is_supported_format file =
      let extension = last_part_of file '.' in
      match extension with
      | Some ext -> List.mem ext [ "qcow2"; "raw"; "img" ]
      | None ->
        match get_mime_type file with
        | None -> false
        | Some mime -> mime = "application/octet-stream" in
    let is_new file =
      try
        let _, { Index.checksums } =
          List.find (
            fun (_, { Index.file_uri }) ->
              Filename.basename file_uri = file
          ) index in
        let checksum = checksums_get_sha512 checksums in
        let path = cmdline.repo // file in
        let file_checksum = Checksums.compute_checksum "sha512" path in
        match checksum with
        | None -> true
        | Some sum -> sum <> file_checksum
      with Not_found -> true in
    let files = Array.to_list (Sys.readdir cmdline.repo) in
    let files = List.filter (
      fun file -> is_regular_file (cmdline.repo // file)
    ) files in
    List.filter (
      fun file -> is_supported_format (cmdline.repo // file) && is_new file
    ) files in

  if images = [] then (
    info (f_ "No new image found");
    exit 0
  );

  info (f_ "Found new images: %s") (String.concat " " images);

  with_open_out (tmprepo // "index") (
    fun index_channel ->
      (* Generate entries for uncompressed images *)
      let images_entries = List.fold_right (
        fun filename acc ->
          let image_entry = process_image acc
                                          filename
                                          cmdline.repo
                                          tmprepo
                                          index
                                          cmdline.interactive
                                          cmdline.compression
                                          sigchecker in
          image_entry :: acc
      ) images [] in

      (* Filter out entries for newly found images and entries
         without a corresponding image file or with empty arch *)
      let index = List.filter (
        fun (id, { Index.arch; file_uri }) ->
          not (has_entry id arch images_entries) && Sys.file_exists file_uri
      ) index in

      (* Convert all URIs back to relative ones *)
      let index = List.map (
        fun (id, entry) ->
          let { Index.file_uri } = entry in
          let rel_path =
            try (* XXX wrong *)
              unsafe_remove_directory_prefix cmdline.repo file_uri
            with
            | Invalid_argument _ ->
              file_uri in
          let rel_entry = { entry with Index.file_uri = rel_path } in
          (id, rel_entry)
      ) index in

      (* Write all the entries *)
      List.iter (
        fun entry ->
          Index_parser.write_entry index_channel entry;
      ) (index @ images_entries);
  );

  (* GPG sign the generated index *)
  (match cmdline.gpgkey with
  | None ->
    debug "Skip index signing"
  | Some gpgkey ->
    message (f_"Signing index with the GPG key %s") gpgkey;
    let cmd = sprintf "%s --armor --output %s --export %s"
                      (quote (cmdline.gpg // "index.gpg"))
                      (quote tmprepo) (quote gpgkey) in
    if shell_command cmd <> 0 then
      error (f_"failed to export the GPG key %s") gpgkey;

    let cmd = sprintf "%s --armor --default-key %s --clearsign %s"
                       (quote cmdline.gpg) (quote gpgkey)
                       (quote (tmprepo // "index" )) in
    if shell_command cmd <> 0 then
      error (f_"failed to sign index");
  );

  message (f_"Creating index backup copy");

  List.iter (
    fun filename ->
      let filepath = cmdline.repo // filename in
      if Sys.file_exists filepath then
        do_mv filepath (filepath ^ ".bak")
  ) ["index"; "index.asc"];

  message (f_"Moving files to final destination");

  Array.iter (
    fun filename ->
      do_mv (tmprepo // filename) cmdline.repo
  ) (Sys.readdir tmprepo);

  debug "Cleanup";

  (* Remove the processed image files *)
  if cmdline.compression then
    List.iter (
      fun filename -> Sys.remove (cmdline.repo // filename)
    ) images

let () = run_main_and_handle_errors main
