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
open Planner

open Cmdline

open Unix
open Printf

let quote = Filename.quote

let prog = Filename.basename Sys.executable_name

let main () =
  (* Command line argument parsing - see cmdline.ml. *)
  let mode, arg,
    attach, cache, check_signature, curl, debug, delete, edit,
    firstboot, run, format, gpg, hostname, install, list_long, links,
    memsize, mkdirs,
    network, output, password_crypto, quiet, root_password, scrub,
    scrub_logfile, size, smp, sources, sync, timezone, update, upload,
    writes =
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
          Index_parser.get_index ~prog ~debug ~downloader ~sigchecker source
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
            ignore (Downloader.download ~prog downloader ~template ~progress_bar
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
      Downloader.download ~prog downloader ~template ~progress_bar file_uri in
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
            Downloader.download ~prog downloader signature_uri in
          if delete_on_exit then unlink_on_exit sigfile;
          Some sigfile in

      Sigchecker.verify_detached sigchecker template sigfile in

  (* For an explanation of the Planner, see:
   * http://rwmj.wordpress.com/2013/12/14/writing-a-planner-to-solve-a-tricky-programming-optimization-problem/
   *)

  (* Planner: Input tags. *)
  let itags =
    let { Index_parser.size = size; format = format } = entry in
    let format_tag =
      match format with
      | None -> []
      | Some format -> [`Format, format] in
    let compression_tag =
      match detect_compression template with
      | `XZ -> [ `XZ, "" ]
      | `Unknown -> [] in
    [ `Template, ""; `Filename, template; `Size, Int64.to_string size ] @
      format_tag @ compression_tag in

  (* Planner: Goal. *)
  let output_filename, output_format =
    match output, format with
    | None, None -> sprintf "%s.img" arg, "raw"
    | None, Some "raw" -> sprintf "%s.img" arg, "raw"
    | None, Some format -> sprintf "%s.%s" arg format, format
    | Some output, None -> output, "raw"
    | Some output, Some format -> output, format in

  if is_char_device output_filename then (
    eprintf (f_"%s: cannot output to a character device or /dev/null\n") prog;
    exit 1
  );

  let blockdev_getsize64 dev =
    let cmd = sprintf "blockdev --getsize64 %s" (quote dev) in
    let lines = external_command ~prog cmd in
    assert (List.length lines >= 1);
    Int64.of_string (List.hd lines)
  in
  let output_is_block_dev, blockdev_size =
    let b = is_block_device output_filename in
    let sz = if b then blockdev_getsize64 output_filename else 0L in
    b, sz in

  let output_size =
    let { Index_parser.size = original_image_size } = entry in

    let size =
      match size with
      | Some size -> size
      (* --size parameter missing, output to file: use original image size *)
      | None when not output_is_block_dev -> original_image_size
      (* --size parameter missing, block device: use block device size *)
      | None -> blockdev_size in

    if size < original_image_size then (
      eprintf (f_"%s: images cannot be shrunk, the output size is too small for this image.  Requested size = %s, minimum size = %s\n")
        prog (human_size size) (human_size original_image_size);
      exit 1
    )
    else if output_is_block_dev && output_format = "raw" && size > blockdev_size then (
      eprintf (f_"%s: output size is too large for this block device.  Requested size = %s, output block device = %s, output block device size = %s\n")
        prog (human_size size) output_filename (human_size blockdev_size);
      exit 1
    );
    size in

  let goal =
    (* MUST *)
    let goal_must = [
      `Filename, output_filename;
      `Size, Int64.to_string output_size;
      `Format, output_format
    ] in

    (* MUST NOT *)
    let goal_must_not = [ `Template, ""; `XZ, "" ] in

    goal_must, goal_must_not in

  (* Planner: Transitions. *)
  let transitions itags =
    let is t = List.mem_assoc t itags in
    let is_not t = not (is t) in
    let remove = List.remove_assoc in
    let ret = ref [] in
    let tr task weight otags = ret := (task, weight, otags) :: !ret in

    (* XXX Weights are not very smartly chosen.  At the moment I'm
     * using a range [0..100] where 0 = free and 100 = expensive.  We
     * could estimate weights better by looking at file sizes.
     *)

    (* Since the final plan won't run in parallel, we don't only need
     * to choose unique tempfiles per transition, so this is OK:
     *)
    let tempfile = Filename.temp_file "vb" ".img" in
    unlink_on_exit tempfile;

    (* Always possible to copy from one place to another.  The only
     * thing a copy does is to remove the template tag (since it's always
     * copied out of the cache directory).
     *)
    tr `Copy 50 ((`Filename, output_filename) :: remove `Template itags);
    tr `Copy 50 ((`Filename, tempfile) :: remove `Template itags);

    (* We can rename a file instead of copying, but don't rename the
     * cache copy!  (XXX Also this is not free if copying across
     * filesystems)
     *)
    if is_not `Template then (
      if not output_is_block_dev then
        tr `Rename 0 ((`Filename, output_filename) :: itags);
      tr `Rename 0 ((`Filename, tempfile) :: itags);
    );

    if is `XZ then (
      (* If the input is XZ-compressed, then we can run xzcat, either
       * to the output file or to a temp file.
       *)
      if not output_is_block_dev then
        tr `Pxzcat 80
          ((`Filename, output_filename) :: remove `XZ (remove `Template itags));
      tr `Pxzcat 80
        ((`Filename, tempfile) :: remove `XZ (remove `Template itags));
    )
    else (
      (* If the input is NOT compressed then we could run virt-resize
       * if it makes sense to resize the image.  Note that virt-resize
       * can do both size and format conversions.
       *)
      let old_size = Int64.of_string (List.assoc `Size itags) in
      let headroom = 256L *^ 1024L *^ 1024L in
      if output_size >= old_size +^ headroom then (
        tr `Virt_resize 100
          ((`Size, Int64.to_string output_size) ::
              (`Filename, output_filename) ::
              (`Format, output_format) :: (remove `Template itags));
        tr `Virt_resize 100
          ((`Size, Int64.to_string output_size) ::
              (`Filename, tempfile) ::
              (`Format, output_format) :: (remove `Template itags))
      )

      (* If the size increase is smaller than the amount of headroom
       * inside the disk image, then virt-resize won't work.  However
       * we can do a disk resize (using 'qemu-img resize') instead,
       * although it won't resize the filesystems for the user.
       *
       * 'qemu-img resize' works on the file in-place and won't change
       * the format.  It must not be run on a template directly.
       *
       * Don't run 'qemu-img resize' on an auto format.  This is to
       * force an explicit conversion step to a real format.
       *)
      else if output_size > old_size && is_not `Template && List.mem_assoc `Format itags then (
        tr `Disk_resize 60 ((`Size, Int64.to_string output_size) :: itags);
        tr `Disk_resize 60 ((`Size, Int64.to_string output_size) :: itags);
      );

      (* qemu-img convert is always possible, and quicker.  It doesn't
       * resize, but it does change the format.
       *)
      tr `Convert 60
        ((`Filename, output_filename) :: (`Format, output_format) ::
            (remove `Template itags));
      tr `Convert 60
        ((`Filename, tempfile) :: (`Format, output_format) ::
            (remove `Template itags));
    );

    (* Return the list of possible transitions. *)
    !ret
  in

  (* Plan how to create the disk image. *)
  msg (f_"Planning how to build this image");
  let plan =
    try plan ~max_depth:5 transitions itags goal
    with
      Failure "plan" ->
        eprintf (f_"%s: no plan could be found for making a disk image with\nthe required size, format etc. This is a bug in libguestfs!\nPlease file a bug, giving the command line arguments you used.\n") prog;
        exit 1
  in

  (* Print out the plan. *)
  if debug then (
    let print_tags tags =
      (try
         let v = List.assoc `Filename tags in eprintf " +filename=%s" v
       with Not_found -> ());
      (try
         let v = List.assoc `Size tags in eprintf " +size=%s" v
       with Not_found -> ());
      (try
         let v = List.assoc `Format tags in eprintf " +format=%s" v
       with Not_found -> ());
      if List.mem_assoc `Template tags then eprintf " +template";
      if List.mem_assoc `XZ tags then eprintf " +xz"
    in
    let print_task = function
      | `Copy -> eprintf "cp"
      | `Rename -> eprintf "mv"
      | `Pxzcat -> eprintf "pxzcat"
      | `Virt_resize -> eprintf "virt-resize"
      | `Disk_resize -> eprintf "qemu-img resize"
      | `Convert -> eprintf "qemu-img convert"
    in

    iteri (
      fun i (itags, task, otags) ->
        eprintf "%d: itags:" i;
        print_tags itags;
        eprintf "\n";
        eprintf "%d: task : " i;
        print_task task;
        eprintf "\n";
        eprintf "%d: otags:" i;
        print_tags otags;
        eprintf "\n\n%!"
    ) plan
  );

  (* Delete the output file before we finish.  However don't delete it
   * if it's block device.
   *)
  let delete_output_file = ref (not output_is_block_dev) in
  let delete_file () =
    if !delete_output_file then
      try unlink output_filename with _ -> ()
  in
  at_exit delete_file;

  (* Carry out the plan. *)
  List.iter (
    function
    | itags, `Copy, otags ->
      let ifile = List.assoc `Filename itags in
      let ofile = List.assoc `Filename otags in
      msg (f_"Copying");
      let cmd = sprintf "cp %s %s" (quote ifile) (quote ofile) in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1

    | itags, `Rename, otags ->
      let ifile = List.assoc `Filename itags in
      let ofile = List.assoc `Filename otags in
      let cmd = sprintf "mv %s %s" (quote ifile) (quote ofile) in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1

    | itags, `Pxzcat, otags ->
      let ifile = List.assoc `Filename itags in
      let ofile = List.assoc `Filename otags in
      msg (f_"Uncompressing");
      Pxzcat.pxzcat ifile ofile

    | itags, `Virt_resize, otags ->
      let ifile = List.assoc `Filename itags in
      let iformat =
        try Some (List.assoc `Format itags) with Not_found -> None in
      let ofile = List.assoc `Filename otags in
      let osize = Int64.of_string (List.assoc `Size otags) in
      let osize = roundup64 osize 512L in
      let oformat = List.assoc `Format otags in
      let { Index_parser.expand = expand; lvexpand = lvexpand } = entry in
      msg (f_"Resizing (using virt-resize) to expand the disk to %s")
        (human_size osize);
      let cmd =
        sprintf "qemu-img create -f %s%s %s %Ld%s"
          (quote oformat)
          (if oformat = "qcow2" then " -o preallocation=metadata" else "")
          (quote ofile) osize
          (if debug then "" else " >/dev/null 2>&1") in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1;
      let cmd =
        sprintf "virt-resize%s%s%s --output-format %s%s%s %s %s"
          (if debug then " --verbose" else " --quiet")
          (if is_block_device ofile then " --no-sparse" else "")
          (match iformat with
          | None -> ""
          | Some iformat -> sprintf " --format %s" (quote iformat))
          (quote oformat)
          (match expand with
          | None -> ""
          | Some expand -> sprintf " --expand %s" (quote expand))
          (match lvexpand with
          | None -> ""
          | Some lvexpand -> sprintf " --lv-expand %s" (quote lvexpand))
          (quote ifile) (quote ofile) in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1

    | itags, `Disk_resize, otags ->
      let ofile = List.assoc `Filename otags in
      let osize = Int64.of_string (List.assoc `Size otags) in
      let osize = roundup64 osize 512L in
      msg (f_"Resizing container (but not filesystems) to expand the disk to %s")
        (human_size osize);
      let cmd = sprintf "qemu-img resize %s %Ld%s"
        (quote ofile) osize (if debug then "" else " >/dev/null") in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1

    | itags, `Convert, otags ->
      let ifile = List.assoc `Filename itags in
      let iformat =
        try Some (List.assoc `Format itags) with Not_found -> None in
      let ofile = List.assoc `Filename otags in
      let oformat = List.assoc `Format otags in
      msg (f_"Converting %s to %s")
        (match iformat with None -> "auto" | Some f -> f) oformat;
      let cmd = sprintf "qemu-img convert%s %s -O %s %s%s"
        (match iformat with
        | None -> ""
        | Some iformat -> sprintf " -f %s" (quote iformat))
        (quote ifile) (quote oformat) (quote ofile)
        (if debug then "" else " >/dev/null 2>&1") in
      if debug then eprintf "%s\n%!" cmd;
      if Sys.command cmd <> 0 then exit 1
  ) plan;

  (* Now mount the output disk so we can make changes. *)
  msg (f_"Opening the new disk");
  let g =
    let g = new G.guestfs () in
    if debug then g#set_trace true;

    (match memsize with None -> () | Some memsize -> g#set_memsize memsize);
    (match smp with None -> () | Some smp -> g#set_smp smp);
    g#set_network network;

    (* The output disk is being created, so use cache=unsafe here. *)
    g#add_drive_opts ~format:output_format ~cachemode:"unsafe" output_filename;

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

  (* Set the timezone. *)
  (match timezone with
  | None -> ()
  | Some timezone ->
    msg (f_"Setting the timezone: %s") timezone;
    if not (Timezone.set_timezone ~prog g root timezone) then
      eprintf (f_"%s: warning: timezone could not be set for this type of guest\n%!") prog
  );

  (* Root password.
   * Note 'None' means that we randomize the root password.
   *)
  let () =
    match g#inspect_get_type root with
    | "linux" ->
      let password_map = Hashtbl.create 1 in
      let pw =
        match root_password with
        | Some pw ->
          msg (f_"Setting root password");
          pw
        | None ->
          msg (f_"Setting random root password [did you mean to use --root-password?]");
          parse_selector ~prog "random" in
      Hashtbl.replace password_map "root" pw;
      set_linux_passwords ~prog ?password_crypto g root password_map
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
      ) [ "http_proxy"; "https_proxy"; "ftp_proxy"; "no_proxy" ] in
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

  (* http://distrowatch.com/dwres.php?resource=package-management *)
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

  and guest_update_command () =
    match g#inspect_get_package_management root with
    | "apt" ->
      (* http://unix.stackexchange.com/questions/22820 *)
      sprintf "
        export DEBIAN_FRONTEND=noninteractive
        apt_opts='-q -y -o Dpkg::Options::=--force-confnew'
        apt-get $apt_opts update
        apt-get $apt_opts upgrade
      "
    | "pisi" ->
      sprintf "pisi upgrade"
    | "pacman" ->
      sprintf "pacman -Su"
    | "urpmi" ->
      sprintf "urpmi --auto-select"
    | "yum" ->
      sprintf "yum -y update"
    | "zypper" ->
      sprintf "zypper update"
    | "unknown" ->
      eprintf (f_"%s: --update is not supported for this guest operating system\n")
        prog;
      exit 1
    | pm ->
      eprintf (f_"%s: sorry, don't know how to use --update with the '%s' package manager\n")
        prog pm;
      exit 1
  in

  (* Update core/template packages. *)
  if update then (
    msg (f_"Updating core packages");

    let cmd = guest_update_command () in
    do_run ~display:cmd cmd
  );

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

  (* Symbolic links. *)
  List.iter (
    fun (target, links) ->
      List.iter (
        fun link ->
          msg (f_"Linking: %s -> %s") link target;
          g#ln_sf target link
      ) links
  ) links;

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
          sprintf (f_"Output: %s") output_filename;
          sprintf (f_"Output size: %s") (human_size output_size);
          sprintf (f_"Output format: %s") output_format;
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
    Fsync.file output_filename;

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
