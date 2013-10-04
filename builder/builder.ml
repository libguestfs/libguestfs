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

let cachedir =
  try Some (Sys.getenv "XDG_CACHE_HOME" // "virt-builder")
  with Not_found ->
    try Some (Sys.getenv "HOME" // ".cache" // "virt-builder")
    with Not_found ->
      None (* no cache directory *)

let mode, arg,
  attach, cache, check_signature, curl, debug, fingerprint,
  firstboot, run,
  format, gpg, hostname, install, list_long, network, output,
  password_crypto, quiet, root_password,
  size, source, upload =
  let display_version () =
    let g = new G.guestfs () in
    let version = g#version () in
    printf (f_"virt-builder %Ld.%Ld.%Ld%s\n")
      version.G.major version.G.minor version.G.release version.G.extra;
    exit 0
  in

  let mode = ref `Install in
  let list_mode () = mode := `List in
  let get_kernel_mode () = mode := `Get_kernel in
  let delete_cache_mode () = mode := `Delete_cache in

  let attach = ref [] in
  let attach_format = ref None in
  let set_attach_format = function
    | "auto" -> attach_format := None
    | s -> attach_format := Some s
  in
  let attach_disk s = attach := (!attach_format, s) :: !attach in

  let cache = ref cachedir in
  let set_cache arg = cache := Some arg in
  let no_cache () = cache := None in

  let check_signature = ref true in
  let curl = ref "curl" in
  let debug = ref false in

  let fingerprint =
    try Some (Sys.getenv "VIRT_BUILDER_FINGERPRINT")
    with Not_found -> None in
  let fingerprint = ref fingerprint in
  let set_fingerprint fp = fingerprint := Some fp in

  let firstboot = ref [] in
  let add_firstboot s =
    if not (Sys.file_exists s) then (
      eprintf (f_"%s: --firstboot: %s: file not found.\n") prog s;
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
      eprintf (f_"%s: --run: %s: file not found.\n") prog s;
      exit 1
    );
    run := `Script s :: !run
  in
  let add_run_cmd s = run := `Command s :: !run in

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
      eprintf (f_"%s: --upload: %s: file not found.\n") prog file;
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
    "--check-signature", Arg.Set check_signature,
                                            " " ^ s_"Check digital signatures";
    "--check-signatures", Arg.Set check_signature, ditto;
    "--no-check-signature", Arg.Clear check_signature,
                                            " " ^ s_"Disable digital signatures";
    "--no-check-signatures", Arg.Clear check_signature, ditto;
    "--curl",    Arg.Set_string curl,       "curl" ^ " " ^ s_"Set curl binary/command";
    "--delete-cache", Arg.Unit delete_cache_mode,
                                            " " ^ s_"Delete the template cache";
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
    "--long-options", Arg.Unit display_long_options, " " ^ s_"List long options";
    "--network", Arg.Set network,           " " ^ s_"Enable appliance network (default)";
    "--no-network", Arg.Clear network,      " " ^ s_"Disable appliance network";
    "-o",        Arg.Set_string output,     "file" ^ " " ^ s_"Set output filename";
    "--output",  Arg.Set_string output,     "file" ^ ditto;
    "--password-crypto", Arg.String set_password_crypto,
                                            "md5|sha256|sha512" ^ " " ^ s_"Set password crypto";
    "--quiet",   Arg.Set quiet,             " " ^ s_"No progress messages";
    "--root-password", Arg.String set_root_password,
                                            "..." ^ " " ^ s_"Set root password";
    "--run",     Arg.String add_run,        "script" ^ " " ^ s_"Run script in disk image";
    "--run-command", Arg.String add_run_cmd, "cmd+args" ^ " " ^ s_"Run command in disk image";
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
    | `Delete_cache ->
      (match args with
      | [] -> ""
      | _ ->
        eprintf (f_"%s: virt-builder --delete-cache does not need any extra arguments.\n") prog;
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
  attach, cache, check_signature, curl, debug, fingerprint,
  firstboot, run,
  format, gpg, hostname, install, list_long, network, output,
  password_crypto, quiet, root_password,
  size, source, upload

(* Timestamped messages in ordinary, non-debug non-quiet mode. *)
let msg fs = make_message_function ~quiet fs

(* If debugging, echo the command line arguments. *)
let () =
  if debug then (
    eprintf "command line:";
    List.iter (eprintf " %s") (Array.to_list Sys.argv);
    prerr_newline ()
  )

(* --get-kernel is really a different program ... *)
let () =
  if mode = `Get_kernel then (
    Get_kernel.get_kernel ~debug ?format ?output arg;
    exit 0
  )

let () =
  if mode = `Delete_cache then (
    match cachedir with
    | Some cachedir ->
      msg "Deleting: %s" cachedir;
      let cmd = sprintf "rm -rf %s" (quote cachedir) in
      ignore (Sys.command cmd);
      exit 0
    | None ->
      eprintf (f_"%s: error: could not find cache directory\nIs $HOME set?\n")
        prog;
      exit 1
  )

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

(* Now we can do the --list option. *)
let () =
  if mode = `List then (
    List_entries.list_entries ~list_long ~source index;
    exit 0
  )

(* If we get here, we want to create a guest (but which one?) *)
let entry =
  assert (mode = `Install);

  try List.assoc arg index
  with Not_found ->
    eprintf (f_"%s: cannot find os-version '%s'.\nUse --list to list available guest types.\n")
      prog arg;
    exit 1

(* Download the template, or it may be in the cache. *)
let template =
  let template, delete_on_exit =
    let { Index_parser.revision = revision; file_uri = file_uri } = entry in
    let template = arg, revision in
    msg (f_"Downloading: %s") file_uri;
    Downloader.download downloader ~template file_uri in
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

(* Check the --size option. *)
let headroom = 256L *^ 1024L *^ 1024L
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
    size

(* Create the output file. *)
let output, format =
  match output, format with
  | None, None -> sprintf "%s.img" arg, "raw"
  | None, Some "raw" -> sprintf "%s.img" arg, "raw"
  | None, Some format -> sprintf "%s.%s" arg format, format
  | Some output, None -> output, "raw"
  | Some output, Some format -> output, format

let delete_output_file =
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
  delete_output_file

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
  msg (f_"Running virt-resize to expand the disk to %s") (human_size size);

  let { Index_parser.expand = expand; lvexpand = lvexpand;
        format = input_format } =
    entry in
  let cmd =
    sprintf "virt-resize%s%s --output-format %s%s%s %s %s"
      (if debug then " --verbose" else " --quiet")
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
let () = ignore (Random_seed.set_random_seed g root)

(* Set the hostname. *)
let () =
  match hostname with
  | None -> ()
  | Some hostname ->
    ignore (Hostname.set_hostname g root hostname)

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

    msg "Random root password: %s [did you mean to use --root-password?]" buf;

    buf
  in

  let root_password =
    match root_password with
    | Some pw -> pw
    | None -> make_random_password () in

  match g#inspect_get_type root with
  | "linux" ->
    let h = Hashtbl.create 1 in
    Hashtbl.replace h "root" root_password;
    set_linux_passwords ~prog ?password_crypto g root h
  | _ ->
    ()

(* Useful wrapper for scripts. *)
let do_run cmd =
  (* Add a prologue to the scripts:
   * - Pass environment variables through from the host.
   * - Send stdout to stderr so we capture all output in error messages.
   *)
  let env_vars =
    filter_map (
      fun name ->
        try Some (sprintf "export %s=%s" name (quote (Sys.getenv name)))
        with Not_found -> None
    ) [ "http_proxy"; "https_proxy"; "ftp_proxy" ] in
  let env_vars = String.concat "\n" env_vars ^ "\n" in

  let cmd = sprintf "\
exec 1>&2
%s
%s
" env_vars cmd in

  if debug then eprintf "running: %s\n%!" cmd;
  ignore (g#sh cmd)

let guest_install_command packages =
  let quoted_args = String.concat " " (List.map quote packages) in
  match g#inspect_get_package_management root with
  | "apt" ->
    sprintf "apt-get -y install %s" quoted_args
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
    do_run cmd;
  )

(* Upload files. *)
let () =
  List.iter (
    fun (file, dest) ->
      msg (f_"Uploading: %s") dest;
      g#upload file dest
  ) upload

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
      do_run cmd
    | `Command cmd ->
      msg (f_"Running: %s") cmd;
      do_run cmd
  ) run

(* Unmount everything and we're done! *)
let () =
  msg "Finishing off";

  g#umount_all ();
  g#shutdown ();
  g#close ()

(* Now that we've finished the build, don't delete the output file on
 * exit.
 *)
let () =
  delete_output_file := false
