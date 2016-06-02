(* virt-builder
 * Copyright (C) 2013-2016 Red Hat Inc.
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
open Utils

open Cmdline
open Customize_cmdline

open Unix
open Printf

let () = Random.self_init ()

let remove_duplicates index =
  let compare_revisions rev1 rev2 =
    match rev1, rev2 with
    | Rev_int n1, Rev_int n2 -> compare n1 n2
    | Rev_string s1, Rev_int n2 -> compare s1 (string_of_int n2)
    | Rev_int n1, Rev_string s2 -> compare (string_of_int n1) s2
    | Rev_string s1, Rev_string s2 -> compare s1 s2
  in
  (* Fill an hash with the higher revision of the available
   * (name, arch) tuples, so it possible to ignore duplicates,
   * and versions with a lower revision.
   *)
  let nseen = Hashtbl.create 13 in
  List.iter (
    fun (name, { Index.arch = arch; revision = revision }) ->
      let id = name, arch in
      try
        let rev = Hashtbl.find nseen id in
        if compare_revisions rev revision > 0 then
          Hashtbl.replace nseen id revision
      with Not_found ->
        Hashtbl.add nseen id revision
  ) index;
  List.filter (
    fun (name, { Index.arch = arch; revision = revision }) ->
      let id = name, arch in
      try
        let rev = Hashtbl.find nseen (name, arch) in
        (* Take the first occurrency with the higher revision,
         * removing it from the hash so the other occurrencies
         * are ignored.
         *)
        if revision = rev then (
          Hashtbl.remove nseen id;
          true
        ) else
          false
      with Not_found ->
        (* Already taken, so ignore. *)
        false
  ) index

let main () =
  (* Command line argument parsing - see cmdline.ml. *)
  let cmdline = parse_cmdline () in

  (* If debugging, echo the command line arguments and the sources. *)
  if verbose () then (
    printf "command line:";
    List.iter (printf " %s") (Array.to_list Sys.argv);
    print_newline ();
    iteri (
      fun i (source, fingerprint) ->
        printf "source[%d] = (%S, %S)\n" i source fingerprint
    ) cmdline.sources
  );

  (* Handle some modes here, some later on. *)
  let mode =
    match cmdline.mode with
    | `Get_kernel -> (* --get-kernel is really a different program ... *)
      let cmd = [ "virt-get-kernel" ] @
        (if verbose () then [ "--verbose" ] else []) @
        (if trace () then [ "-x" ] else []) @
        (match cmdline.format with
        | None -> []
        | Some format -> [ "--format"; format ]) @
        (match cmdline.output with
        | None -> []
        | Some output -> [ "--output"; output ]) @
        [ "--add"; cmdline.arg ] in
      exit (run_command cmd)

    | `Delete_cache ->                  (* --delete-cache *)
      (match cmdline.cache with
      | Some cachedir ->
        message (f_"Deleting: %s") cachedir;
        Cache.clean_cachedir cachedir;
        exit 0
      | None ->
        error (f_"could not find cache directory. Is $HOME set?")
      )

    | (`Install|`List|`Notes|`Print_cache|`Cache_all) as mode -> mode in

  (* Check various programs/dependencies are installed. *)

  (* Check that gpg is installed.  Optional as long as the user
   * disables all signature checks.
   *)
  let cmd = sprintf "%s --help >/dev/null 2>&1" cmdline.gpg in
  if shell_command cmd <> 0 then (
    if cmdline.check_signature then
      error (f_"gpg is not installed (or does not work)\nYou should install gpg, or use --gpg option, or use --no-check-signature.")
    else if verbose () then
      warning (f_"gpg program is not available")
  );

  (* Check that curl works. *)
  let cmd = sprintf "%s --help >/dev/null 2>&1" cmdline.curl in
  if shell_command cmd <> 0 then
    error (f_"curl is not installed (or does not work)");

  (* Check that virt-resize works. *)
  let cmd = "virt-resize --help >/dev/null 2>&1" in
  if shell_command cmd <> 0 then
    error (f_"virt-resize is not installed (or does not work)");

  (* Create the cache. *)
  let cache =
    match cmdline.cache with
    | None -> None
    | Some dir ->
      try Some (Cache.create ~directory:dir)
      with exn ->
        warning (f_"cache %s: %s") dir (Printexc.to_string exn);
        warning (f_"disabling the cache");
        None
  in

  (* Download the sources. *)
  let downloader = Downloader.create ~curl:cmdline.curl ~cache in
  let repos = Sources.read_sources () in
  let sources = List.map (
    fun (source, fingerprint) ->
      {
        Sources.name = source; uri = source;
        gpgkey = Utils.Fingerprint fingerprint;
        proxy = Curl.SystemProxy;
        format = Sources.FormatNative;
      }
  ) cmdline.sources in
  let sources = List.append sources repos in
  let index : Index.index =
    List.concat (
      List.map (
        fun source ->
          let sigchecker =
            Sigchecker.create ~gpg:cmdline.gpg
                              ~check_signature:cmdline.check_signature
                              ~gpgkey:source.Sources.gpgkey in
          match source.Sources.format with
          | Sources.FormatNative ->
            Index_parser.get_index ~downloader ~sigchecker source
          | Sources.FormatSimpleStreams ->
            Simplestreams_parser.get_index ~downloader ~sigchecker source
      ) sources
    ) in
  let index = remove_duplicates index in

  (* Now handle the remaining modes. *)
  let mode =
    match mode with
    | `List ->                          (* --list *)
      List_entries.list_entries ~list_format:cmdline.list_format ~sources index;
      exit 0

    | `Print_cache ->                   (* --print-cache *)
      (match cache with
      | Some cache ->
        let l = List.filter (
          fun (_, { Index.hidden = hidden }) ->
            hidden <> true
        ) index in
        let l = List.map (
          fun (name, { Index.revision = revision; arch = arch }) ->
            (name, arch, revision)
        ) l in
        Cache.print_item_status cache ~header:true l
      | None -> printf (f_"no cache directory\n")
      );
      exit 0

    | `Cache_all ->                     (* --cache-all-templates *)
      (match cache with
      | None ->
        error (f_"no cache directory")
      | Some _ ->
        List.iter (
          fun (name,
               { Index.revision = revision; file_uri = file_uri;
                 proxy = proxy }) ->
            let template = name, cmdline.arch, revision in
            message (f_"Downloading: %s") file_uri;
            let progress_bar = not (quiet ()) in
            ignore (Downloader.download downloader ~template ~progress_bar
                      ~proxy file_uri)
        ) index;
        exit 0
      );

    | (`Install|`Notes) as mode -> mode in

  (* Which os-version (ie. index entry)? *)
  let arg =
    (* Try to resolve the alias. *)
    try
      let item =
        List.find (
          fun (name, { Index.aliases = aliases }) ->
            match aliases with
            | None -> false
            | Some l -> List.mem cmdline.arg l
        ) index in
        fst item
    with Not_found -> cmdline.arg in
  let item =
    try List.find (
      fun (name, { Index.arch = a }) ->
        name = arg && cmdline.arch = normalize_arch a
    ) index
    with Not_found ->
      error (f_"cannot find os-version '%s' with architecture '%s'.\nUse --list to list available guest types.")
        arg cmdline.arch in
  let entry = snd item in
  let sigchecker = entry.Index.sigchecker in

  (match mode with
  | `Notes ->                           (* --notes *)
    let notes =
      Languages.find_notes (Languages.languages ()) entry.Index.notes in
    (match notes with
    | notes :: _ ->
      print_endline notes
    | [] ->
      printf (f_"There are no notes for %s\n") arg
    );
    exit 0

  | `Install ->
    () (* fall through to create the guest *)
  );

  (* --- If we get here, we want to create a guest. --- *)

  (* Warn if the user might be writing to a partition on a USB key. *)
  (match cmdline.output with
   | Some device when is_partition device ->
      if cmdline.warn_if_partition then
        warning (f_"output device (%s) is a partition.  If you are writing to a USB key or external drive then you probably need to write to the whole device, not to a partition.  If this warning is wrong then you can disable it with --no-warn-if-partition")
                device;
   | Some _ | None -> ()
  );

  (* Download the template, or it may be in the cache. *)
  let template =
    let template, delete_on_exit =
      let { Index.revision = revision; file_uri = file_uri;
            proxy = proxy } = entry in
      let template = arg, cmdline.arch, revision in
      message (f_"Downloading: %s") file_uri;
      let progress_bar = not (quiet ()) in
      Downloader.download downloader ~template ~progress_bar ~proxy
        file_uri in
    if delete_on_exit then unlink_on_exit template;
    template in

  (* Check the signature of the file. *)
  let () =
    match entry with
    (* New-style: Using a checksum. *)
    | { Index.checksums = Some csums } ->
      Checksums.verify_checksums csums template

    | { Index.checksums = None } ->
      (* Old-style: detached signature. *)
      let sigfile =
        match entry with
        | { Index.signature_uri = None } -> None
        | { Index.signature_uri = Some signature_uri } ->
          let sigfile, delete_on_exit =
            Downloader.download downloader signature_uri in
          if delete_on_exit then unlink_on_exit sigfile;
          Some sigfile in

      Sigchecker.verify_detached sigchecker template sigfile in

  (* For an explanation of the Planner, see:
   * http://rwmj.wordpress.com/2013/12/14/writing-a-planner-to-solve-a-tricky-programming-optimization-problem/
   *)

  (* Planner: Input tags. *)
  let itags =
    let { Index.size = size; format = format } = entry in
    let format_tag =
      match format with
      | None -> []
      | Some format -> [`Format, format] in
    let compression_tag =
      match detect_file_type template with
      | `XZ -> [ `XZ, "" ]
      | `GZip | `Tar | `Zip ->
        error (f_"input file (%s) has an unsupported type") template
      | `Unknown -> [] in
    [ `Template, ""; `Filename, template; `Size, Int64.to_string size ] @
      format_tag @ compression_tag in

  (* Planner: Goal. *)
  let output_filename, output_format =
    match cmdline.output, cmdline.format with
    | None, None -> sprintf "%s.img" arg, "raw"
    | None, Some "raw" -> sprintf "%s.img" arg, "raw"
    | None, Some format -> sprintf "%s.%s" arg format, format
    | Some output, None -> output, "raw"
    | Some output, Some format -> output, format in

  if is_char_device output_filename then
    error (f_"cannot output to a character device or /dev/null");

  let blockdev_getsize64 dev =
    let cmd = sprintf "blockdev --getsize64 %s" (quote dev) in
    let lines = external_command cmd in
    assert (List.length lines >= 1);
    Int64.of_string (List.hd lines)
  in
  let output_is_block_dev, blockdev_size =
    let b = is_block_device output_filename in
    let sz = if b then blockdev_getsize64 output_filename else 0L in
    b, sz in

  let output_size =
    let { Index.size = original_image_size } = entry in

    let size =
      match cmdline.size with
      | Some size -> size
      (* --size parameter missing, output to file: use original image size *)
      | None when not output_is_block_dev -> original_image_size
      (* --size parameter missing, block device: use block device size *)
      | None -> blockdev_size in

    if size < original_image_size then
      error (f_"images cannot be shrunk, the output size is too small for this image.  Requested size = %s, minimum size = %s")
        (human_size size) (human_size original_image_size)
    else if output_is_block_dev && output_format = "raw" && size > blockdev_size then
      error (f_"output size is too large for this block device.  Requested size = %s, output block device = %s, output block device size = %s")
        (human_size size) output_filename (human_size blockdev_size);
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

  let cache_dir = (open_guestfs ())#get_cachedir () in

  (* Planner: Transitions. *)
  let transitions itags =
    let is t = List.mem_assoc t itags in
    let is_not t = not (is t) in
    let remove = List.remove_assoc in
    let ret = ref [] in
    let tr task weight otags = push_front (task, weight, otags) ret in

    (* XXX Weights are not very smartly chosen.  At the moment I'm
     * using a range [0..100] where 0 = free and 100 = expensive.  We
     * could estimate weights better by looking at file sizes.
     *)

    (* Since the final plan won't run in parallel, we don't only need
     * to choose unique tempfiles per transition, so this is OK:
     *)
    let tempfile = Filename.temp_file ~temp_dir:cache_dir "vb" ".img" in
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
      else if output_size > old_size && is_not `Template
              && List.mem_assoc `Format itags then
        tr `Disk_resize 60 ((`Size, Int64.to_string output_size) :: itags);

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
  message (f_"Planning how to build this image");
  let plan =
    try plan ~max_depth:5 transitions itags goal
    with
      Failure "plan" ->
        error (f_"no plan could be found for making a disk image with\nthe required size, format etc. This is a bug in libguestfs!\nPlease file a bug, giving the command line arguments you used.");
  in

  (* Print out the plan. *)
  if verbose () then (
    let print_tags tags =
      (try
         let v = List.assoc `Filename tags in printf " +filename=%s" v
       with Not_found -> ());
      (try
         let v = List.assoc `Size tags in printf " +size=%s" v
       with Not_found -> ());
      (try
         let v = List.assoc `Format tags in printf " +format=%s" v
       with Not_found -> ());
      if List.mem_assoc `Template tags then printf " +template";
      if List.mem_assoc `XZ tags then printf " +xz"
    in
    let print_task = function
      | `Copy -> printf "cp"
      | `Rename -> printf "mv"
      | `Pxzcat -> printf "pxzcat"
      | `Virt_resize -> printf "virt-resize"
      | `Disk_resize -> printf "qemu-img resize"
      | `Convert -> printf "qemu-img convert"
    in

    iteri (
      fun i (itags, task, otags) ->
        printf "%d: itags:" i;
        print_tags itags;
        printf "\n";
        printf "%d: task : " i;
        print_task task;
        printf "\n";
        printf "%d: otags:" i;
        print_tags otags;
        printf "\n\n%!"
    ) plan
  );

  (* Delete the output file before we finish.  However don't delete it
   * if it's block device, or if --no-delete-on-failure is set.
   *)
  let delete_output_file =
    ref (cmdline.delete_on_failure && not output_is_block_dev) in
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
      message (f_"Copying");
      let cmd = [ "cp"; ifile; ofile ] in
      if run_command cmd <> 0 then exit 1

    | itags, `Rename, otags ->
      let ifile = List.assoc `Filename itags in
      let ofile = List.assoc `Filename otags in
      let cmd = [ "mv"; ifile; ofile ] in
      if run_command cmd <> 0 then exit 1

    | itags, `Pxzcat, otags ->
      let ifile = List.assoc `Filename itags in
      let ofile = List.assoc `Filename otags in
      message (f_"Uncompressing");
      Pxzcat.pxzcat ifile ofile

    | itags, `Virt_resize, otags ->
      let ifile = List.assoc `Filename itags in
      let iformat =
        try Some (List.assoc `Format itags) with Not_found -> None in
      let ofile = List.assoc `Filename otags in
      let osize = Int64.of_string (List.assoc `Size otags) in
      let osize = roundup64 osize 512L in
      let oformat = List.assoc `Format otags in
      let { Index.expand = expand; lvexpand = lvexpand } = entry in
      message (f_"Resizing (using virt-resize) to expand the disk to %s")
        (human_size osize);
      let preallocation = if oformat = "qcow2" then Some "metadata" else None in
      let () =
        let g = open_guestfs () in
        g#disk_create ?preallocation ofile oformat osize in
      let cmd = [ "virt-resize" ] @
        (if verbose () then [ "--verbose" ] else [ "--quiet" ]) @
        (if is_block_device ofile then [ "--no-sparse" ] else []) @
        (match iformat with
        | None -> []
        | Some iformat -> [ "--format"; iformat ]) @
        [ "--output-format"; oformat ] @
        (match expand with
        | None -> []
        | Some expand -> [ "--expand"; expand ]) @
        (match lvexpand with
        | None -> []
        | Some lvexpand -> [ "--lv-expand"; lvexpand ]) @
        [ "--unknown-filesystems"; "error"; ifile; ofile ] in
      if run_command cmd <> 0 then exit 1

    | itags, `Disk_resize, otags ->
      let ofile = List.assoc `Filename otags in
      let osize = Int64.of_string (List.assoc `Size otags) in
      let osize = roundup64 osize 512L in
      message (f_"Resizing container (but not filesystems) to expand the disk to %s")
        (human_size osize);
      let cmd = sprintf "qemu-img resize %s %Ld%s"
        (quote ofile) osize (if verbose () then "" else " >/dev/null") in
      if shell_command cmd <> 0 then exit 1

    | itags, `Convert, otags ->
      let ifile = List.assoc `Filename itags in
      let iformat =
        try Some (List.assoc `Format itags) with Not_found -> None in
      let ofile = List.assoc `Filename otags in
      let oformat = List.assoc `Format otags in
      (match iformat with
      | None -> message (f_"Converting to %s") oformat
      | Some f -> message (f_"Converting %s to %s") f oformat
      );
      let cmd = sprintf "qemu-img convert%s %s -O %s %s%s"
        (match iformat with
        | None -> ""
        | Some iformat -> sprintf " -f %s" (quote iformat))
        (quote ifile) (quote oformat) (quote (qemu_input_filename ofile))
        (if verbose () then "" else " >/dev/null 2>&1") in
      if shell_command cmd <> 0 then exit 1
  ) plan;

  (* Now mount the output disk so we can make changes. *)
  message (f_"Opening the new disk");
  let g =
    let g = open_guestfs () in

    may g#set_memsize cmdline.memsize;
    may g#set_smp cmdline.smp;
    g#set_network cmdline.network;

    (* Make sure to turn SELinux off to avoid awkward interactions
     * between the appliance kernel and applications/libraries interacting
     * with SELinux xattrs.
     *)
    g#set_selinux false;

    (* The output disk is being created, so use cache=unsafe here. *)
    g#add_drive_opts ~format:output_format ~cachemode:"unsafe" output_filename;

    (* Attach ISOs, if we have any. *)
    List.iter (
      fun (format, file) ->
        g#add_drive_opts ?format ~readonly:true file;
    ) cmdline.attach;

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
          with G.Error msg -> warning (f_"%s (ignored)") msg
      ) mps;
      root
    | _ ->
      error (f_"no guest operating systems or multiboot OS found in this disk image\nThis is a failure of the source repository.  Use -v for more information.")
  in

  Customize_run.run g root cmdline.ops;

  (* Collect some stats about the final output file.
   * Notes:
   * - These are virtual disk stats.
   * - Never fail here.
   *)
  let stats =
    if not (quiet ()) then (
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
          sprintf "%30s: %s" (s_"Output file") output_filename;
          sprintf "%30s: %s" (s_"Output size") (human_size output_size);
          sprintf "%30s: %s" (s_"Output format") output_format;
          sprintf "%30s: %s" (s_"Total usable space")
            (human_size total_bytes);
          sprintf "%30s: %s (%Ld%%)" (s_"Free space")
            (human_size free_bytes) free_percent;
        ] ^ "\n"
      )
    with
      _ -> None
    )
    else None in

  (* Unmount everything and we're done! *)
  message (f_"Finishing off");

  g#umount_all ();
  g#shutdown ();
  g#close ();

  (* Because we used cache=unsafe when writing the output file, the
   * file might not be committed to disk.  This is a problem if qemu is
   * immediately used afterwards with cache=none (which uses O_DIRECT
   * and therefore bypasses the host cache).  In general you should not
   * use cache=none.
   *)
  if cmdline.sync then
    Fsync.file output_filename;

  (* Now that we've finished the build, don't delete the output file on
   * exit.
   *)
  delete_output_file := false;

  (* Print the stats calculated above. *)
  Pervasives.flush Pervasives.stdout;
  Pervasives.flush Pervasives.stderr;

  may print_string stats

let () = run_main_and_handle_errors main
