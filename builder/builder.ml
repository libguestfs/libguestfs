(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

module G = Guestfs

open Common_utils
open Password

open Unix
open Printf

let quote = Filename.quote

(* Command line argument parsing. *)
let prog = Filename.basename Sys.executable_name

let default_cachedir =
  try Some (Sys.getenv "XDG_CACHE_HOME" // "virt-builder")
  with Not_found ->
    try Some (Sys.getenv "HOME" // ".cache" // "virt-builder")
    with Not_found ->
      None (* no cache directory *)

let mode, arg,
  attach, cache, check_signature, curl, debug, delete, edit, fingerprint,
  firstboot, run,
  format, gpg, hostname, install, list_long, network, output,
  password_crypto, quiet, root_password,
  scrub, scrub_logfile, size, source, upload =
  let display_version () =
    let g = new G.guestfs () in
    let version = g#version () in
    printf (f_"virt-builder %Ld.%Ld.%Ld%s\n")
      version.G.major version.G.minor version.G.release version.G.extra;
    exit 0
  in

  let mode = ref `Install in
  let list_mode () = mode := `List in
  let notes_mode () = mode := `Notes in
  let get_kernel_mode () = mode := `Get_kernel in
  let cache_all_mode () = mode := `Cache_all in
  let print_cache_mode () = mode := `Print_cache in
  let delete_cache_mode () = mode := `Delete_cache in

  let attach = ref [] in
  let attach_format = ref None in
  let set_attach_format = function
    | "auto" -> attach_format := None
    | s -> attach_format := Some s
  in
  let attach_disk s = attach := (!attach_format, s) :: !attach in

  let cache = ref default_cachedir in
  let set_cache arg = cache := Some arg in
  let no_cache () = cache := None in

  let check_signature = ref true in
  let curl = ref "curl" in
  let debug = ref false in

  let delete = ref [] in
  let add_delete s = delete := s :: !delete in

  let edit = ref [] in
  let add_edit arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        eprintf (f_"%s: invalid --edit format, see the man page.\n") prog;
        exit 1 in
    let len = String.length arg in
    let file = String.sub arg 0 i in
    let expr = String.sub arg (i+1) (len-(i+1)) in
    edit := (file, expr) :: !edit
  in

  let fingerprint =
    try Some (Sys.getenv "VIRT_BUILDER_FINGERPRINT")
    with Not_found -> None in
  let fingerprint = ref fingerprint in
  let set_fingerprint fp = fingerprint := Some fp in

  let firstboot = ref [] in
  let add_firstboot s =
    if not (Sys.file_exists s) then (
      if not (String.contains s ' ') then
        eprintf (f_"%s: %s: %s: file not found\n") prog "--firstboot" s
      else
        eprintf (f_"%s: %s: %s: file not found [did you mean %s?]\n") prog "--firstboot" s "--firstboot-command";
      exit 1
    );
    firstboot := `Script s :: !firstboot
  in
  let add_firstboot_cmd s = firstboot := `Command s :: !firstboot in
  let add_firstboot_install pkgs =
    let pkgs = string_nsplit "," pkgs in
    firstboot := `Packages pkgs :: !firstboot
  in

  let format = ref "" in
  let gpg = ref "gpg" in

  let hostname = ref None in
  let set_hostname s = hostname := Some s in

  let install = ref [] in
  let add_install pkgs =
    let pkgs = string_nsplit "," pkgs in
    install := pkgs @ !install
  in

  let list_long = ref false in
  let network = ref true in
  let output = ref "" in

  let password_crypto : password_crypto option ref = ref None in
  let set_password_crypto arg =
    password_crypto := Some (password_crypto_of_string ~prog arg)
  in

  let quiet = ref false in

  let root_password = ref None in
  let set_root_password arg =
    let pw = get_password ~prog arg in
    root_password := Some pw
  in

  let run = ref [] in
  let add_run s =
    if not (Sys.file_exists s) then (
      if not (String.contains s ' ') then
        eprintf (f_"%s: %s: %s: file not found\n") prog "--run" s
      else
        eprintf (f_"%s: %s: %s: file not found [did you mean %s?]\n") prog "--run" s "--run-command";
      exit 1
    );
    run := `Script s :: !run
  in
  let add_run_cmd s = run := `Command s :: !run in

  let scrub = ref [] in
  let add_scrub s = scrub := s :: !scrub in

  let scrub_logfile = ref false in

  let size = ref None in
  let set_size arg = size := Some (parse_size ~prog arg) in

  let source =
    try Sys.getenv "VIRT_BUILDER_SOURCE"
    with Not_found -> "http://libguestfs.org/download/builder/index.asc" in
  let source = ref source in

  let upload = ref [] in
  let add_upload arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        eprintf (f_"%s: invalid --upload format, see the man page.\n") prog;
        exit 1 in
    let len = String.length arg in
    let file = String.sub arg 0 i in
    if not (Sys.file_exists file) then (
      eprintf (f_"%s: --upload: %s: file not found\n") prog file;
      exit 1
    );
    let dest = String.sub arg (i+1) (len-(i+1)) in
    upload := (file, dest) :: !upload
  in

  let ditto = " -\"-" in
  let argspec = Arg.align [
    "--attach",  Arg.String attach_disk,    "iso" ^ " " ^ s_"Attach data disk/ISO during install";
    "--attach-format",  Arg.String set_attach_format,
                                            "format" ^ " " ^ s_"Set attach disk format";
    "--cache",   Arg.String set_cache,      "dir" ^ " " ^ s_"Set template cache dir";
    "--no-cache", Arg.Unit no_cache,        " " ^ s_"Disable template cache";
    "--cache-all-templates", Arg.Unit cache_all_mode,
                                            " " ^ s_"Download all templates to the cache";
    "--check-signature", Arg.Set check_signature,
                                            " " ^ s_"Check digital signatures";
    "--check-signatures", Arg.Set check_signature, ditto;
    "--no-check-signature", Arg.Clear check_signature,
                                            " " ^ s_"Disable digital signatures";
    "--no-check-signatures", Arg.Clear check_signature, ditto;
    "--curl",    Arg.Set_string curl,       "curl" ^ " " ^ s_"Set curl binary/command";
    "--delete",  Arg.String add_delete,     "name" ^ s_"Delete a file or dir";
    "--delete-cache", Arg.Unit delete_cache_mode,
                                            " " ^ s_"Delete the template cache";
    "--edit",    Arg.String add_edit,       "file:expr" ^ " " ^ s_"Edit file with Perl expr";
    "--fingerprint", Arg.String set_fingerprint,
                                            "AAAA.." ^ " " ^ s_"Fingerprint of valid signing key";
    "--firstboot", Arg.String add_firstboot, "script" ^ " " ^ s_"Run script at first guest boot";
    "--firstboot-command", Arg.String add_firstboot_cmd, "cmd+args" ^ " " ^ s_"Run command at first guest boot";
    "--firstboot-install", Arg.String add_firstboot_install,
                                            "pkg,pkg" ^ " " ^ s_"Add package(s) to install at firstboot";
    "--format",  Arg.Set_string format,     "raw|qcow2" ^ " " ^ s_"Output format (default: raw)";
    "--get-kernel", Arg.Unit get_kernel_mode,
                                            "image" ^ " " ^ s_"Get kernel from image";
    "--gpg",    Arg.Set_string gpg,         "gpg" ^ " " ^ s_"Set GPG binary/command";
    "--hostname", Arg.String set_hostname,  "hostname" ^ " " ^ s_"Set the hostname";
    "--install", Arg.String add_install,    "pkg,pkg" ^ " " ^ s_"Add package(s) to install";
    "-l",        Arg.Unit list_mode,        " " ^ s_"List available templates";
    "--list",    Arg.Unit list_mode,        ditto;
    "--long",    Arg.Set list_long,         ditto;
    "--no-logfile", Arg.Set scrub_logfile,  " " ^ s_"Scrub build log file";
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--network", Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "--notes",   Arg.Unit notes_mode,       " " ^ s_"Display installation notes";
    "-o",        Arg.Set_string output,     "file" ^ " " ^ s_"Set output filename";
    "--output",  Arg.Set_string output,     "file" ^ ditto;
    "--password-crypto", Arg.String set_password_crypto,
                                            "md5|sha256|sha512" ^ " " ^ s_"Set password crypto";
    "--print-cache", Arg.Unit print_cache_mode,
                                            " " ^ s_"Print info about template cache";
    "--quiet",   Arg.Set quiet,             " " ^ s_"No progress messages";
    "--root-password", Arg.String set_root_password,
                                            "..." ^ " " ^ s_"Set root password";
    "--run",     Arg.String add_run,        "script" ^ " " ^ s_"Run script in disk image";
    "--run-command", Arg.String add_run_cmd, "cmd+args" ^ " " ^ s_"Run command in disk image";
    "--scrub",   Arg.String add_scrub,      "name" ^ s_"Scrub a file";
    "--size",    Arg.String set_size,       "size" ^ " " ^ s_"Set output disk size";
    "--source",  Arg.Set_string source,     "URL" ^ " " ^ s_"Set source URL";
    "--upload",  Arg.String add_upload,     "file:dest" ^ " " ^ s_"Upload file to dest";
    "-v",        Arg.Set debug,             " " ^ s_"Enable debugging messages";
    "--verbose", Arg.Set debug,             ditto;
    "-V",        Arg.Unit display_version,  " " ^ s_"Display version and exit";
    "--version", Arg.Unit display_version,  ditto;
  ] in
  long_options := argspec;

  let args = ref [] in
  let anon_fun s = args := s :: !args in
  let usage_msg =
    sprintf (f_"\
%s: build virtual machine images quickly

 virt-builder OS-VERSION
 virt-builder -l
 virt-builder --notes OS-VERSION
 virt-builder --print-cache
 virt-builder --cache-all-templates
 virt-builder --delete-cache
 virt-builder --get-kernel IMAGE

A short summary of the options is given below.  For detailed help please
read the man page virt-builder(1).
")
      prog in
  Arg.parse argspec anon_fun usage_msg;

  (* Dereference options. *)
  let args = List.rev !args in
  let mode = !mode in
  let attach = List.rev !attach in
  let cache = !cache in
  let check_signature = !check_signature in
  let curl = !curl in
  let debug = !debug in
  let delete = List.rev !delete in
  let edit = List.rev !edit in
  let fingerprint = !fingerprint in
  let firstboot = List.rev !firstboot in
  let run = List.rev !run in
  let format = match !format with "" -> None | s -> Some s in
  let gpg = !gpg in
  let hostname = !hostname in
  let install = !install in
  let list_long = !list_long in
  let network = !network in
  let output = match !output with "" -> None | s -> Some s in
  let password_crypto = !password_crypto in
  let quiet = !quiet in
  let root_password = !root_password in
  let scrub = List.rev !scrub in
  let scrub_logfile = !scrub_logfile in
  let size = !size in
  let source = !source in
  let upload = List.rev !upload in

  (* Check options. *)
  let arg =
    match mode with
    | `Install ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder os-version\nMissing 'os-version'. Use '--list' to list available template names.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder: too many parameters, expecting 'os-version'\n") prog;
        exit 1
      )
    | `List ->
      (match args with
      | [] -> ""
      | _ ->
        eprintf (f_"%s: virt-builder --list does not need any extra arguments.\n") prog;
        exit 1
      )
    | `Notes ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder --notes os-version\nMissing 'os-version'. Use '--list' to list available template names.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder: too many parameters, expecting 'os-version'\n") prog;
        exit 1
      )
    | `Cache_all
    | `Print_cache
    | `Delete_cache ->
      (match args with
      | [] -> ""
      | _ ->
        eprintf (f_"%s: virt-builder --cache-all-templates/--print-cache/--delete-cache does not need any extra arguments.\n") prog;
        exit 1
      )
    | `Get_kernel ->
      (match args with
      | [arg] -> arg
      | [] ->
        eprintf (f_"%s: virt-builder --get-kernel image\nMissing 'image' (disk image file) argument.\n") prog;
        exit 1
      | _ ->
        eprintf (f_"%s: virt-builder --get-kernel: too many parameters\n") prog;
        exit 1
      ) in

  mode, arg,
  attach, cache, check_signature, curl, debug, delete, edit, fingerprint,
  firstboot, run,
  format, gpg, hostname, install, list_long, network, output,
  password_crypto, quiet, root_password,
  scrub, scrub_logfile, size, source, upload

(* Timestamped messages in ordinary, non-debug non-quiet mode. *)
let msg fs = make_message_function ~quiet fs

(* If debugging, echo the command line arguments. *)
let () =
  if debug then (
    eprintf "command line:";
    List.iter (eprintf " %s") (Array.to_list Sys.argv);
    prerr_newline ()
  )

(* Handle some modes here, some later on. *)
let mode =
  match mode with
  | `Get_kernel -> (* --get-kernel is really a different program ... *)
    Get_kernel.get_kernel ~debug ?format ?output arg;
    exit 0

  | `Delete_cache ->                    (* --delete-cache *)
    (match cache with
    | Some cachedir ->
      msg "Deleting: %s" cachedir;
      let cmd = sprintf "rm -rf %s" (quote cachedir) in
      ignore (Sys.command cmd);
      exit 0
    | None ->
      eprintf (f_"%s: error: could not find cache directory. Is $HOME set?\n")
        prog;
      exit 1
    )

  | (`Install|`List|`Notes|`Print_cache|`Cache_all) as mode -> mode

(* Check various programs/dependencies are installed. *)
let have_nbdkit =
  (* Check that gpg is installed.  Optional as long as the user
   * disables all signature checks.
   *)
  let cmd = sprintf "%s --help >/dev/null 2>&1" gpg in
  if Sys.command cmd <> 0 then (
    if check_signature then (
      eprintf (f_"%s: gpg is not installed (or does not work)\nYou should install gpg, or use --gpg option, or use --no-check-signature.\n") prog;
      exit 1
    )
    else if debug then
      eprintf (f_"%s: warning: gpg program is not available\n") prog
  );

  (* Check that curl works. *)
  let cmd = sprintf "%s --help >/dev/null 2>&1" curl in
  if Sys.command cmd <> 0 then (
    eprintf (f_"%s: curl is not installed (or does not work)\n") prog;
    exit 1
  );

  (* Check that virt-resize works. *)
  let cmd = "virt-resize --help >/dev/null 2>&1" in
  if Sys.command cmd <> 0 then (
    eprintf (f_"%s: virt-resize is not installed (or does not work)\n") prog;
    exit 1
  );

  (* Find out if nbdkit + nbdkit-xz-plugin is installed (optional). *)
  let cmd =
    sprintf "nbdkit %s/nbdkit/plugins/nbdkit-xz-plugin.so --help >/dev/null 2>&1"
      Libdir.libdir in
  let have_nbdkit = Sys.command cmd = 0 in
  if not have_nbdkit && debug then
    eprintf (f_"%s: warning: nbdkit or nbdkit-xz-plugin is not available\n")
      prog;

  have_nbdkit

(* Create the cache directory. *)
let cache =
  match cache with
  | None -> None
  | (Some dir) as cache ->
    (try mkdir dir 0o755 with _ -> ());
    if Sys.is_directory dir then cache else None

(* Make the downloader and signature checker abstract data types. *)
let downloader =
  Downloader.create ~debug ~curl ~cache
let sigchecker =
  Sigchecker.create ~debug ~gpg ?fingerprint ~check_signature

(* Download the source (index) file. *)
let index =
  Index_parser.get_index ~debug ~downloader ~sigchecker source

(* Now handle the remaining modes. *)
let mode =
  match mode with
  | `List ->                            (* --list *)
    List_entries.list_entries ~list_long ~source index;
    exit 0

  | `Print_cache ->                     (* --print-cache *)
    (match cache with
    | Some cachedir ->
      printf (f_"cache directory: %s\n") cachedir;
      List.iter (
        fun (name, { Index_parser.revision = revision; hidden = hidden }) ->
          if not hidden then (
            let filename = Downloader.cache_of_name cachedir name revision in
            let cached = Sys.file_exists filename in
            printf "%-24s %s\n" name (if cached then s_"cached" else (*s_*)"no")
          )
      ) index
    | None -> printf (f_"no cache directory\n")
    );
    exit 0

  | `Cache_all ->                       (* --cache-all-templates *)
    (match cache with
    | None ->
      eprintf (f_"%s: error: no cache directory\n") prog;
      exit 1
    | Some _ ->
      List.iter (
        fun (name, { Index_parser.revision = revision; file_uri = file_uri }) ->
          let template = name, revision in
          msg (f_"Downloading: %s") file_uri;
          let progress_bar = not quiet in
          ignore (Downloader.download downloader ~template ~progress_bar
                    file_uri)
      ) index;
      exit 0
    );

  | (`Install|`Notes) as mode -> mode

(* Which os-version (ie. index entry)? *)
let entry =
  try List.assoc arg index
  with Not_found ->
    eprintf (f_"%s: cannot find os-version '%s'.\nUse --list to list available guest types.\n")
      prog arg;
    exit 1

let () =
  match mode with
  | `Notes ->                           (* --notes *)
    (match entry with
    | { Index_parser.notes = Some notes } ->
      print_endline notes;
    | { Index_parser.notes = None } ->
      printf (f_"There are no notes for %s\n") arg
    );
    exit 0

  | `Install ->
    () (* fall through to create the guest *)

(* If we get here, we want to create a guest. *)

(* Download the template, or it may be in the cache. *)
let template =
  let template, delete_on_exit =
    let { Index_parser.revision = revision; file_uri = file_uri } = entry in
    let template = arg, revision in
    msg (f_"Downloading: %s") file_uri;
    let progress_bar = not quiet in
    Downloader.download downloader ~template ~progress_bar file_uri in
  if delete_on_exit then unlink_on_exit template;
  template

(* Check the signature of the file. *)
let () =
  let sigfile =
    match entry with
    | { Index_parser.signature_uri = None } -> None
    | { Index_parser.signature_uri = Some signature_uri } ->
      let sigfile, delete_on_exit =
        Downloader.download downloader signature_uri in
      if delete_on_exit then unlink_on_exit sigfile;
      Some sigfile in

  Sigchecker.verify_detached sigchecker template sigfile

let output, size, format, delete_output_file, resize_sparse =
  let is_block_device file =
    try (stat file).st_kind = S_BLK
    with Unix_error _ -> false
  in

  let headroom = 256L *^ 1024L *^ 1024L in

  match output with
  (* If the output file was specified and it exists and it's a block
   * device, then we should skip the creation step.
   *)
  | Some output when is_block_device output ->
    if size <> None then (
      eprintf (f_"%s: you cannot use --size option with block devices\n") prog;
      exit 1
    );
    (* XXX Should check the output size is big enough.  However this
     * requires running 'blockdev --getsize64 <output>'.
     *)

    let format = match format with None -> "raw" | Some f -> f in

    (* Dummy: The output file is never deleted in this case. *)
    let delete_output_file = ref false in

    output, None, format, delete_output_file, false

  (* Regular file output.  Note the file gets deleted. *)
  | _ ->
    (* Check the --size option. *)
    let size =
      let { Index_parser.size = default_size } = entry in
      match size with
      | None -> default_size +^ headroom
      | Some size ->
        if size < default_size +^ headroom then (
          eprintf (f_"%s: --size is too small for this disk image, minimum size is %s\n")
            prog (human_size default_size);
          exit 1
        );
        size in

    (* Create the output file. *)
    let output, format =
      match output, format with
      | None, None -> sprintf "%s.img" arg, "raw"
      | None, Some "raw" -> sprintf "%s.img" arg, "raw"
      | None, Some format -> sprintf "%s.%s" arg format, format
      | Some output, None -> output, "raw"
      | Some output, Some format -> output, format in

    msg (f_"Creating disk image: %s") output;
    let cmd =
      sprintf "qemu-img create -f %s %s %Ld%s"
        (quote format) (quote output) size
        (if debug then "" else " >/dev/null 2>&1") in
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"%s: error: could not create output file '%s'\n") prog output;
      exit 1
    );
    (* This ensures the output file will be deleted on failure,
     * until we set !delete_output_file = false at the end of the build.
     *)
    let delete_output_file = ref true in
    let delete_file () =
      if !delete_output_file then
        try unlink output with _ -> ()
    in
    at_exit delete_file;

    output, Some size, format, delete_output_file, true

let source =
  (* XXX Disable this for now because libvirt is broken:
   * https://bugzilla.redhat.com/show_bug.cgi?id=1011063
   *)
  if have_nbdkit && false then (
    (* If we have nbdkit, then we can use NBD to uncompress the xz
     * file on the fly.
     *)
    let socket = Filename.temp_file "vbnbd" ".sock" in
    let source = sprintf "nbd://?socket=%s" socket in
    let argv = [| "nbdkit"; "-r"; "-f"; "-U"; socket;
                  Libdir.libdir // "nbdkit/plugins/nbdkit-xz-plugin.so";
                  "file=" ^ template |] in
    let pid =
      match fork () with
      | 0 ->                            (* child *)
        execvp "nbdkit" argv
      | pid -> pid in
    (* Clean up when the program exits. *)
    let clean_up () =
      (try kill pid Sys.sigterm with _ -> ());
      (try unlink socket with _ -> ())
    in
    at_exit clean_up;
    source
  )
  else (
    (* Otherwise we have to uncompress it to a temporary file. *)
    let { Index_parser.file_uri = file_uri } = entry in
    let tmpfile = Filename.temp_file "vbsrc" ".img" in
    let cmd = sprintf "xzcat %s > %s" (quote template) (quote tmpfile) in
    if debug then eprintf "%s\n%!" cmd;
    msg (f_"Uncompressing: %s") file_uri;
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"%s: error: failed to uncompress template\n") prog;
      exit 1
    );
    unlink_on_exit tmpfile;
    tmpfile
  )

(* Resize the source to the output file. *)
let () =
  (match size with
  | None ->
    msg (f_"Running virt-resize to expand the disk")
  | Some size ->
    msg (f_"Running virt-resize to expand the disk to %s")
      (human_size size)
  );

  let { Index_parser.expand = expand; lvexpand = lvexpand;
        format = input_format } =
    entry in
  let cmd =
    sprintf "virt-resize%s%s%s --output-format %s%s%s %s %s"
      (if debug then " --verbose" else " --quiet")
      (if not resize_sparse then " --no-sparse" else "")
      (match input_format with
      | None -> ""
      | Some input_format -> sprintf " --format %s" (quote input_format))
      (quote format)
      (match expand with
      | None -> ""
      | Some expand -> sprintf " --expand %s" (quote expand))
      (match lvexpand with
      | None -> ""
      | Some lvexpand -> sprintf " --lv-expand %s" (quote lvexpand))
      (quote source) (quote output) in
  if debug then eprintf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then (
    eprintf (f_"%s: error: virt-resize failed\n") prog;
    exit 1
  )

(* Now mount the output disk so we can make changes. *)
let g =
  msg (f_"Opening the new disk");

  let g = new G.guestfs () in
  if debug then g#set_trace true;

  g#set_network network;

  g#add_drive_opts ~format output;

  (* Attach ISOs, if we have any. *)
  List.iter (
    fun (format, file) ->
      g#add_drive_opts ?format ~readonly:true file;
  ) attach;

  g#launch ();

  g

(* Inspect the disk and mount it up. *)
let root =
  match Array.to_list (g#inspect_os ()) with
  | [root] ->
    let mps = g#inspect_get_mountpoints root in
    let cmp (a,_) (b,_) =
      compare (String.length a) (String.length b) in
    let mps = List.sort cmp mps in
    List.iter (
      fun (mp, dev) ->
        try g#mount dev mp
        with Guestfs.Error msg -> eprintf (f_"%s: %s (ignored)\n") prog msg
    ) mps;
    root
  | _ ->
    eprintf (f_"%s: no guest operating systems or multiboot OS found in this disk image\nThis is a failure of the source repository.  Use -v for more information.\n") prog;
    exit 1

(* Set the random seed. *)
let () =
  msg (f_"Setting a random seed");
  if not (Random_seed.set_random_seed g root) then
    eprintf (f_"%s: warning: random seed could not be set for this type of guest\n%!") prog

(* Set the hostname. *)
let () =
  match hostname with
  | None -> ()
  | Some hostname ->
    msg (f_"Setting the hostname: %s") hostname;
    if not (Hostname.set_hostname g root hostname) then
      eprintf (f_"%s: warning: hostname could not be set for this type of guest\n%!") prog

(* Root password.
 * Note 'None' means that we randomize the root password.
 *)
let () =
  let make_random_password () =
    (* Get random characters from the set [A-Za-z0-9] *)
    let chars =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" in
    let nr_chars = String.length chars in

    let chan = open_in "/dev/urandom" in
    let buf = String.create 16 in
    for i = 0 to 15 do
      buf.[i] <- chars.[Char.code (input_char chan) mod nr_chars]
    done;
    close_in chan;

    buf
  in

  let root_password =
    match root_password with
    | Some pw ->
      msg (f_"Setting root password");
      pw
    | None ->
      let pw = make_random_password () in
      msg (f_"Random root password: %s [did you mean to use --root-password?]")
        pw;
      pw in

  match g#inspect_get_type root with
  | "linux" ->
    let h = Hashtbl.create 1 in
    Hashtbl.replace h "root" root_password;
    set_linux_passwords ~prog ?password_crypto g root h
  | _ ->
    eprintf (f_"%s: warning: root password could not be set for this type of guest\n%!") prog

(* Based on the guest type, choose a log file location. *)
let logfile =
  match g#inspect_get_type root with
  | "windows" | "dos" ->
    if g#is_dir "/Temp" then "/Temp/builder.log" else "/builder.log"
  | _ ->
    if g#is_dir "/tmp" then "/tmp/builder.log" else "/builder.log"

(* Function to cat the log file, for debugging and error messages. *)
let debug_logfile () =
  try
    (* XXX If stderr is redirected this actually truncates the
     * redirection file, which is pretty annoying to say the
     * least.
     *)
    g#download logfile "/dev/stderr"
  with exn ->
    eprintf (f_"%s: log file %s: %s (ignored)\n")
      prog logfile (Printexc.to_string exn)

(* Useful wrapper for scripts. *)
let do_run ~display cmd =
  (* Add a prologue to the scripts:
   * - Pass environment variables through from the host.
   * - Send stdout and stderr to a log file so we capture all output
   *   in error messages.
   * Also catch errors and dump the log file completely on error.
   *)
  let env_vars =
    filter_map (
      fun name ->
        try Some (sprintf "export %s=%s" name (quote (Sys.getenv name)))
        with Not_found -> None
    ) [ "http_proxy"; "https_proxy"; "ftp_proxy" ] in
  let env_vars = String.concat "\n" env_vars ^ "\n" in

  let cmd = sprintf "\
exec >>%s 2>&1
%s
%s
" (quote logfile) env_vars cmd in

  if debug then eprintf "running command:\n%s\n%!" cmd;
  try ignore (g#sh cmd)
  with
    Guestfs.Error msg ->
      debug_logfile ();
      eprintf (f_"%s: %s: command exited with an error\n") prog display;
      exit 1

let guest_install_command packages =
  let quoted_args = String.concat " " (List.map quote packages) in
  match g#inspect_get_package_management root with
  | "apt" ->
    sprintf "apt-get update; apt-get -y install %s" quoted_args
  | "pisi" ->
    sprintf "pisi it %s" quoted_args
  | "pacman" ->
    sprintf "pacman -S %s" quoted_args
  | "urpmi" ->
    sprintf "urpmi %s" quoted_args
  | "yum" ->
    sprintf "yum -y install %s" quoted_args
  | "zypper" ->
    (* XXX Should we use -n option? *)
    sprintf "zypper in %s" quoted_args
  | "unknown" ->
    eprintf (f_"%s: --install is not supported for this guest operating system\n")
      prog;
    exit 1
  | pm ->
    eprintf (f_"%s: sorry, don't know how to use --install with the '%s' package manager\n")
      prog pm;
    exit 1

(* Install packages. *)
let () =
  if install <> [] then (
    msg (f_"Installing packages: %s") (String.concat " " install);

    let cmd = guest_install_command install in
    do_run ~display:cmd cmd
  )

(* Upload files. *)
let () =
  List.iter (
    fun (file, dest) ->
      msg (f_"Uploading: %s") dest;
      g#upload file dest
  ) upload

(* Edit files. *)
let () =
  List.iter (
    fun (file, expr) ->
      msg (f_"Editing: %s") file;

      if not (g#is_file file) then (
        eprintf (f_"%s: error: %s is not a regular file in the guest\n")
          prog file;
        exit 1
      );

      Perl_edit.edit_file ~debug g file expr
  ) edit

(* Delete files. *)
let () =
  List.iter (
    fun file ->
      msg (f_"Deleting: %s") file;
      g#rm_rf file
  ) delete

(* Scrub files. *)
let () =
  List.iter (
    fun file ->
      msg (f_"Scrubbing: %s") file;
      g#scrub_file file
  ) scrub

(* Firstboot scripts/commands/install. *)
let () =
  let id = ref 0 in
  List.iter (
    fun op ->
      incr id;
      let id = sprintf "%03d" !id in
      match op with
      | `Script script ->
        msg (f_"Installing firstboot script: [%s] %s") id script;
        let cmd = read_whole_file script in
        Firstboot.add_firstboot_script g root id cmd
      | `Command cmd ->
        msg (f_"Installing firstboot command: [%s] %s") id cmd;
        Firstboot.add_firstboot_script g root id cmd
      | `Packages pkgs ->
        msg (f_"Installing firstboot packages: [%s] %s") id
          (String.concat " " pkgs);
        let cmd = guest_install_command pkgs in
        Firstboot.add_firstboot_script g root id cmd
  ) firstboot

(* Run scripts. *)
let () =
  List.iter (
    function
    | `Script script ->
      msg (f_"Running: %s") script;
      let cmd = read_whole_file script in
      do_run ~display:script cmd
    | `Command cmd ->
      msg (f_"Running: %s") cmd;
      do_run ~display:cmd cmd
  ) run

(* Clean up the log file:
 *
 * If debugging, dump out the log file.
 * Then if asked, scrub the log file.
 *)
let () =
  if debug then debug_logfile ();
  if scrub_logfile && g#exists logfile then (
    msg (f_"Scrubbing the log file");

    (* Try various methods with decreasing complexity. *)
    try g#scrub_file logfile
    with _ -> g#rm_f logfile
  )

(* Collect some stats about the final output file.
 * Notes:
 * - These are virtual disk stats.
 * - Never fail here.
 *)
let stats =
  if not quiet then (
    try
      (* Calculate the free space (in bytes) across all mounted
       * filesystems in the guest.
       *)
      let free_bytes, total_bytes =
        let filesystems = List.map snd (g#mountpoints ()) in
        let stats = List.map g#statvfs filesystems in
        let stats = List.map (
          fun { G.bfree = bfree; bsize = bsize; blocks = blocks } ->
            bfree *^ bsize, blocks *^ bsize
        ) stats in
        List.fold_left (
          fun (f,t) (f',t') -> f +^ f', t +^ t'
        ) (0L, 0L) stats in
      let free_percent = 100L *^ free_bytes /^ total_bytes in

      Some (
        String.concat "\n" [
          sprintf (f_"Output: %s") output;
          sprintf (f_"Total usable space: %s")
            (human_size total_bytes);
          sprintf (f_"Free space: %s (%Ld%%)")
            (human_size free_bytes) free_percent;
        ] ^ "\n"
      )
    with
      _ -> None
  )
  else None

(* Unmount everything and we're done! *)
let () =
  msg (f_"Finishing off");

  (* Kill any daemons (eg. started by newly installed packages) using
   * the sysroot.
   * XXX How to make this nicer?
   * XXX fuser returns an error if it doesn't kill any processes, which
   * is not very useful.
   *)
  (try ignore (g#debug "sh" [| "fuser"; "-k"; "/sysroot" |])
   with exn ->
     if debug then
       eprintf (f_"%s: %s (ignored)\n") prog (Printexc.to_string exn)
  );
  g#ping_daemon (); (* tiny delay after kill *)

  g#umount_all ();
  g#shutdown ();
  g#close ()

(* Now that we've finished the build, don't delete the output file on
 * exit.
 *)
let () =
  delete_output_file := false

(* Print the stats calculated above. *)
let () =
  Pervasives.flush Pervasives.stdout;
  Pervasives.flush Pervasives.stderr;

  match stats with
  | None -> ()
  | Some stats -> print_string stats
