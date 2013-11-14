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

open Cmdline
open Pxzcat

open Unix
open Printf

let quote = Filename.quote

let prog = Filename.basename Sys.executable_name

let main () =
  (* Command line argument parsing - see cmdline.ml. *)
  let mode, arg,
    attach, cache, check_signature, curl, debug, delete, edit,
    firstboot, run, format, gpg, hostname, install, list_long, memsize, mkdirs,
    network, output, password_crypto, quiet, root_password, scrub,
    scrub_logfile, size, smp, sources, sync, upload, writes =
    parse_cmdline () in

  (* Timestamped messages in ordinary, non-debug non-quiet mode. *)
  let msg fs = make_message_function ~quiet fs in

  (* If debugging, echo the command line arguments and the sources. *)
  if debug then (
    eprintf "command line:";
    List.iter (eprintf " %s") (Array.to_list Sys.argv);
    prerr_newline ();
    iteri (
      fun i (source, fingerprint) ->
        eprintf "source[%d] = (%S, %S)\n" i source fingerprint
    ) sources
  );


  (* Handle some modes here, some later on. *)
  let mode =
    match mode with
    | `Get_kernel -> (* --get-kernel is really a different program ... *)
      Get_kernel.get_kernel ~debug ?format ?output arg;
      exit 0

    | `Delete_cache ->                  (* --delete-cache *)
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

    | (`Install|`List|`Notes|`Print_cache|`Cache_all) as mode -> mode in

  (* Check various programs/dependencies are installed. *)

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

  (* Create the cache directory. *)
  let cache =
    match cache with
    | None -> None
    | Some dir ->
      (* Annoyingly Sys.is_directory throws an exception on failure
       * (RHBZ#1022431).
       *)
      if (try Sys.is_directory dir with Sys_error _ -> false) then
        Some dir
      else (
        (* Try to make the directory.  If that fails, warn and continue
         * without any cache.
         *)
        try mkdir dir 0o755; Some dir
        with exn ->
          eprintf (f_"%s: warning: cache %s: %s\n") prog dir
            (Printexc.to_string exn);
          eprintf (f_"%s: disabling the cache\n%!") prog;
          None
      )
  in

  (* Download the sources. *)
  let downloader = Downloader.create ~debug ~curl ~cache in
  let index : Index_parser.index =
    List.concat (
      List.map (
        fun (source, fingerprint) ->
          let sigchecker =
            Sigchecker.create ~debug ~gpg ~fingerprint ~check_signature in
          Index_parser.get_index ~debug ~downloader ~sigchecker source
      ) sources
    ) in

  (* Now handle the remaining modes. *)
  let mode =
    match mode with
    | `List ->                          (* --list *)
      List_entries.list_entries ~list_long ~sources index;
      exit 0

    | `Print_cache ->                   (* --print-cache *)
      (match cache with
      | Some cachedir ->
        printf (f_"cache directory: %s\n") cachedir;
        List.iter (
          fun (name, { Index_parser.revision = revision; hidden = hidden }) ->
            if not hidden then (
              let filename = Downloader.cache_of_name cachedir name revision in
              let cached = Sys.file_exists filename in
              printf "%-24s %s\n" name
                (if cached then s_"cached" else (*s_*)"no")
            )
        ) index
      | None -> printf (f_"no cache directory\n")
      );
      exit 0

    | `Cache_all ->                     (* --cache-all-templates *)
      (match cache with
      | None ->
        eprintf (f_"%s: error: no cache directory\n") prog;
        exit 1
      | Some _ ->
        List.iter (
          fun (name,
               { Index_parser.revision = revision; file_uri = file_uri }) ->
            let template = name, revision in
            msg (f_"Downloading: %s") file_uri;
            let progress_bar = not quiet in
            ignore (Downloader.download downloader ~template ~progress_bar
                      file_uri)
        ) index;
        exit 0
      );

    | (`Install|`Notes) as mode -> mode in

  (* Which os-version (ie. index entry)? *)
  let entry =
    try List.assoc arg index
    with Not_found ->
      eprintf (f_"%s: cannot find os-version '%s'.\nUse --list to list available guest types.\n")
        prog arg;
      exit 1 in
  let sigchecker = entry.Index_parser.sigchecker in

  (match mode with
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
  );

  (* --- If we get here, we want to create a guest. --- *)

  (* Download the template, or it may be in the cache. *)
  let template =
    let template, delete_on_exit =
      let { Index_parser.revision = revision; file_uri = file_uri } = entry in
      let template = arg, revision in
      msg (f_"Downloading: %s") file_uri;
      let progress_bar = not quiet in
      Downloader.download downloader ~template ~progress_bar file_uri in
    if delete_on_exit then unlink_on_exit template;
    template in

  (* Check the signature of the file. *)
  let () =
    match entry with
    (* New-style: Using a checksum. *)
    | { Index_parser.checksum_sha512 = Some csum } ->
      Sigchecker.verify_checksum sigchecker (Sigchecker.SHA512 csum) template

    | { Index_parser.checksum_sha512 = None } ->
      (* Old-style: detached signature. *)
      let sigfile =
        match entry with
        | { Index_parser.signature_uri = None } -> None
        | { Index_parser.signature_uri = Some signature_uri } ->
          let sigfile, delete_on_exit =
            Downloader.download downloader signature_uri in
          if delete_on_exit then unlink_on_exit sigfile;
          Some sigfile in

      Sigchecker.verify_detached sigchecker template sigfile in

  (* Plan how to create the output.  This depends on:
   * - did the user specify --output?
   * - is the output a block device?
   * - did the user specify --size?
   *)
  let output, size, format, delete_output_file, do_resize, resize_sparse =
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
        eprintf (f_"%s: you cannot use --size option with block devices\n")
          prog;
        exit 1
      );
      (* XXX Should check the output size is big enough.  However this
       * requires running 'blockdev --getsize64 <output>'.
       *)

      let format = match format with None -> "raw" | Some f -> f in

      (* Dummy: The output file is never deleted in this case. *)
      let delete_output_file = ref false in

      output, None, format, delete_output_file, true, false

    (* Regular file output.  Note the file gets deleted. *)
    | _ ->
      (* Check the --size option. *)
      let size, do_resize =
        let { Index_parser.size = default_size } = entry in
        match size with
        | None -> default_size, false
        | Some size ->
          if size < default_size +^ headroom then (
            eprintf (f_"%s: --size is too small for this disk image, minimum size is %s\n")
              prog (human_size default_size);
            exit 1
          );
          size, true in

      (* Create the output file. *)
      let output, format =
        match output, format with
        | None, None -> sprintf "%s.img" arg, "raw"
        | None, Some "raw" -> sprintf "%s.img" arg, "raw"
        | None, Some format -> sprintf "%s.%s" arg format, format
        | Some output, None -> output, "raw"
        | Some output, Some format -> output, format in

      (* If the input format != output format then we must run virt-resize. *)
      let do_resize =
        let input_format =
          match entry with
          | { Index_parser.format = Some format } -> format
          | { Index_parser.format = None } -> "raw" in
        if input_format <> format then true else do_resize in

      msg (f_"Creating disk image: %s") output;
      let cmd =
        sprintf "qemu-img create -f %s%s %s %Ld%s"
          (quote format)
          (if format = "qcow2" then " -o preallocation=metadata" else "")
          (quote output) size
          (if debug then "" else " >/dev/null 2>&1") in
      let r = Sys.command cmd in
      if r <> 0 then (
        eprintf (f_"%s: error: could not create output file '%s'\n")
          prog output;
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

      output, Some size, format, delete_output_file, do_resize, true in

  if not do_resize then (
    (* If the user did not specify --size and the output is a regular
     * file and the format is raw, then we just uncompress the template
     * directly to the output file.  This is fast but less flexible.
     *)
    let { Index_parser.file_uri = file_uri } = entry in
    msg (f_"Uncompressing: %s") file_uri;
    pxzcat template output
  ) else (
    (* If none of the above apply, uncompress to a temporary file and
     * run virt-resize on the result.
     *)
    let tmpfile =
      (* Uncompress it to a temporary file. *)
      let { Index_parser.file_uri = file_uri } = entry in
      let tmpfile = Filename.temp_file "vbsrc" ".img" in
      msg (f_"Uncompressing: %s") file_uri;
      pxzcat template tmpfile;
      unlink_on_exit tmpfile;
      tmpfile in

    (* Resize the source to the output file. *)
    (match size with
    | None ->
      msg (f_"Running virt-resize to expand the disk")
    | Some size ->
      msg (f_"Running virt-resize to expand the disk to %s") (human_size size)
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
        (quote tmpfile) (quote output) in
    if debug then eprintf "%s\n%!" cmd;
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"%s: error: virt-resize failed\n") prog;
      exit 1
    )
  );

  (* Now mount the output disk so we can make changes. *)
  msg (f_"Opening the new disk");
  let g =
    let g = new G.guestfs () in
    if debug then g#set_trace true;

    (match memsize with None -> () | Some memsize -> g#set_memsize memsize);
    (match smp with None -> () | Some smp -> g#set_smp smp);
    g#set_network network;

    (* The output disk is being created, so use cache=unsafe here. *)
    g#add_drive_opts ~format ~cachemode:"unsafe" output;

    (* Attach ISOs, if we have any. *)
    List.iter (
      fun (format, file) ->
        g#add_drive_opts ?format ~readonly:true file;
    ) attach;

    g#launch ();

    g in

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
          with G.Error msg -> eprintf (f_"%s: %s (ignored)\n") prog msg
      ) mps;
      root
    | _ ->
      eprintf (f_"%s: no guest operating systems or multiboot OS found in this disk image\nThis is a failure of the source repository.  Use -v for more information.\n") prog;
      exit 1 in

  (* Set the random seed. *)
  msg (f_"Setting a random seed");
  if not (Random_seed.set_random_seed g root) then
    eprintf (f_"%s: warning: random seed could not be set for this type of guest\n%!") prog;

  (* Set the hostname. *)
  (match hostname with
  | None -> ()
  | Some hostname ->
    msg (f_"Setting the hostname: %s") hostname;
    if not (Hostname.set_hostname g root hostname) then
      eprintf (f_"%s: warning: hostname could not be set for this type of guest\n%!") prog
  );

  (* Root password.
   * Note 'None' means that we randomize the root password.
   *)
  let () =
    let read_byte fd =
      let s = String.make 1 ' ' in
      fun () ->
        if read fd s 0 1 = 0 then
          raise End_of_file;
        Char.code s.[0]
    in

    let make_random_password () =
      (* Get random characters from the set [A-Za-z0-9] with some
       * homoglyphs removed.
       *)
      let chars =
        "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789" in
      let nr_chars = String.length chars in

      let fd = openfile "/dev/urandom" [O_RDONLY] 0 in
      let buf = String.create 16 in
      for i = 0 to 15 do
        buf.[i] <- chars.[read_byte fd () mod nr_chars]
      done;
      close fd;

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
      eprintf (f_"%s: warning: root password could not be set for this type of guest\n%!") prog in

  (* Based on the guest type, choose a log file location. *)
  let logfile =
    match g#inspect_get_type root with
    | "windows" | "dos" ->
      if g#is_dir ~followsymlinks:true "/Temp" then "/Temp/builder.log"
      else "/builder.log"
    | _ ->
      if g#is_dir ~followsymlinks:true "/tmp" then "/tmp/builder.log"
      else "/builder.log" in

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
        prog logfile (Printexc.to_string exn) in

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
  in

  let guest_install_command packages =
    let quoted_args = String.concat " " (List.map quote packages) in
    match g#inspect_get_package_management root with
    | "apt" ->
      (* http://unix.stackexchange.com/questions/22820 *)
      sprintf "
        export DEBIAN_FRONTEND=noninteractive
        apt_opts='-q -y -o Dpkg::Options::=--force-confnew'
        apt-get $apt_opts update
        apt-get $apt_opts install %s
      " quoted_args
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
  in

  (* Install packages. *)
  if install <> [] then (
    msg (f_"Installing packages: %s") (String.concat " " install);

    let cmd = guest_install_command install in
    do_run ~display:cmd cmd
  );

  (* Make directories. *)
  List.iter (
    fun dir ->
      msg (f_"Making directory: %s") dir;
      g#mkdir_p dir
  ) mkdirs;

  (* Write files. *)
  List.iter (
    fun (file, content) ->
      msg (f_"Writing: %s") file;
      g#write file content
  ) writes;

  (* Upload files. *)
  List.iter (
    fun (file, dest) ->
      msg (f_"Uploading: %s to %s") file dest;
      let dest =
        if g#is_dir ~followsymlinks:true dest then
          dest ^ "/" ^ Filename.basename file
        else
          dest in
      (* Do the file upload. *)
      g#upload file dest;

      (* Copy (some of) the permissions from the local file to the
       * uploaded file.
       *)
      let statbuf = stat file in
      let perms = statbuf.st_perm land 0o7777 (* sticky & set*id *) in
      g#chmod perms dest;
      let uid, gid = statbuf.st_uid, statbuf.st_gid in
      g#chown uid gid dest
  ) upload;

  (* Edit files. *)
  List.iter (
    fun (file, expr) ->
      msg (f_"Editing: %s") file;

      if not (g#is_file file) then (
        eprintf (f_"%s: error: %s is not a regular file in the guest\n")
          prog file;
        exit 1
      );

      Perl_edit.edit_file ~debug g file expr
  ) edit;

  (* Delete files. *)
  List.iter (
    fun file ->
      msg (f_"Deleting: %s") file;
      g#rm_rf file
  ) delete;

  (* Scrub files. *)
  List.iter (
    fun file ->
      msg (f_"Scrubbing: %s") file;
      g#scrub_file file
  ) scrub;

  (* Firstboot scripts/commands/install. *)
  let () =
    let i = ref 0 in
    List.iter (
      fun op ->
        incr i;
        match op with
        | `Script script ->
          msg (f_"Installing firstboot script: [%d] %s") !i script;
          let cmd = read_whole_file script in
          Firstboot.add_firstboot_script g root !i cmd
        | `Command cmd ->
          msg (f_"Installing firstboot command: [%d] %s") !i cmd;
          Firstboot.add_firstboot_script g root !i cmd
        | `Packages pkgs ->
          msg (f_"Installing firstboot packages: [%d] %s") !i
            (String.concat " " pkgs);
          let cmd = guest_install_command pkgs in
          Firstboot.add_firstboot_script g root !i cmd
    ) firstboot in

  (* Run scripts. *)
  List.iter (
    function
    | `Script script ->
      msg (f_"Running: %s") script;
      let cmd = read_whole_file script in
      do_run ~display:script cmd
    | `Command cmd ->
      msg (f_"Running: %s") cmd;
      do_run ~display:cmd cmd
  ) run;

  (* Clean up the log file:
   *
   * If debugging, dump out the log file.
   * Then if asked, scrub the log file.
   *)
  if debug then debug_logfile ();
  if scrub_logfile && g#exists logfile then (
    msg (f_"Scrubbing the log file");

    (* Try various methods with decreasing complexity. *)
    try g#scrub_file logfile
    with _ -> g#rm_f logfile
  );

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
    else None in

  (* Unmount everything and we're done! *)
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
  g#close ();

  (* Because we used cache=unsafe when writing the output file, the
   * file might not be committed to disk.  This is a problem if qemu is
   * immediately used afterwards with cache=none (which uses O_DIRECT
   * and therefore bypasses the host cache).  In general you should not
   * use cache=none.
   *)
  if sync then
    Fsync.file output;

  (* Now that we've finished the build, don't delete the output file on
   * exit.
   *)
  delete_output_file := false;

  (* Print the stats calculated above. *)
  Pervasives.flush Pervasives.stdout;
  Pervasives.flush Pervasives.stderr;

  match stats with
  | None -> ()
  | Some stats -> print_string stats

let () =
  try main ()
  with
  | Unix_error (code, fname, "") ->     (* from a syscall *)
    eprintf (f_"%s: error: %s: %s\n") prog fname (error_message code);
    exit 1
  | Unix_error (code, fname, param) ->  (* from a syscall *)
    eprintf (f_"%s: error: %s: %s: %s\n") prog fname (error_message code) param;
    exit 1
  | G.Error msg ->                      (* from libguestfs *)
    eprintf (f_"%s: libguestfs error: %s\n") prog msg;
    exit 1
  | Failure msg ->                      (* from failwith/failwithf *)
    eprintf (f_"%s: failure: %s\n") prog msg;
    exit 1
  | Invalid_argument msg ->             (* probably should never happen *)
    eprintf (f_"%s: internal error: invalid argument: %s\n") prog msg;
    exit 1
  | Assert_failure (file, line, char) -> (* should never happen *)
    eprintf (f_"%s: internal error: assertion failed at %s, line %d, char %d\n") prog file line char;
    exit 1
  | Not_found ->                        (* should never happen *)
    eprintf (f_"%s: internal error: Not_found exception was thrown\n") prog;
    exit 1
  | exn ->                              (* something not matched above *)
    eprintf (f_"%s: exception: %s\n") prog (Printexc.to_string exn);
    exit 1
