(* virt-customize
 * Copyright (C) 2014 Red Hat Inc.
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

open Unix
open Printf

open Common_gettext.Gettext
open Common_utils

open Customize_cmdline
open Password

let quote = Filename.quote

let run ~prog ~verbose ~quiet (g : Guestfs.guestfs) root (ops : ops) =
  (* Timestamped messages in ordinary, non-debug non-quiet mode. *)
  let msg fs = make_message_function ~quiet fs in

  (* Is the host_cpu compatible with the guest arch?  ie. Can we
   * run commands in this guest?
   *)
  let guest_arch = g#inspect_get_arch root in
  let guest_arch_compatible = guest_arch_compatible guest_arch in

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
    if not guest_arch_compatible then
      error ~prog (f_"host cpu (%s) and guest arch (%s) are not compatible, so you cannot use command line options that involve running commands in the guest.  Use --firstboot scripts instead.")
            Config.host_cpu guest_arch;

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

    if verbose then eprintf "running command:\n%s\n%!" cmd;
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

  (* Set the random seed. *)
  msg (f_"Setting a random seed");
  if not (Random_seed.set_random_seed g root) then
    warning ~prog (f_"random seed could not be set for this type of guest");

  (* Used for numbering firstboot commands. *)
  let i = ref 0 in

  (* Store the passwords and set them all at the end. *)
  let passwords = Hashtbl.create 13 in
  let set_password user pw =
    if Hashtbl.mem passwords user then (
      eprintf (f_"%s: error: multiple --root-password/--password options set the password for user '%s' twice.\n")
        prog user;
      exit 1
    );
    Hashtbl.replace passwords user pw
  in

  (* Perform the remaining customizations in command-line order. *)
  List.iter (
    function
    | `Chmod (mode, path) ->
      msg (f_"Changing permissions of %s to %s") path mode;
      (* If the mode string is octal, add the OCaml prefix for octal values
       * so it is properly converted as octal integer.
       *)
      let mode = if string_prefix mode "0" then "0o" ^ mode else mode in
      g#chmod (int_of_string mode) path

    | `Command cmd ->
      msg (f_"Running: %s") cmd;
      do_run ~display:cmd cmd

    | `Delete path ->
      msg (f_"Deleting: %s") path;
      g#rm_rf path

    | `Edit (path, expr) ->
      msg (f_"Editing: %s") path;

      if not (g#is_file path) then (
        eprintf (f_"%s: error: %s is not a regular file in the guest\n")
          prog path;
        exit 1
      );

      Perl_edit.edit_file ~verbose g#ocaml_handle path expr

    | `FirstbootCommand cmd ->
      incr i;
      msg (f_"Installing firstboot command: [%d] %s") !i cmd;
      Firstboot.add_firstboot_script ~prog g root !i cmd

    | `FirstbootPackages pkgs ->
      incr i;
      msg (f_"Installing firstboot packages: [%d] %s") !i
        (String.concat " " pkgs);
      let cmd = guest_install_command pkgs in
      Firstboot.add_firstboot_script ~prog g root !i cmd

    | `FirstbootScript script ->
      incr i;
      msg (f_"Installing firstboot script: [%d] %s") !i script;
      let cmd = read_whole_file script in
      Firstboot.add_firstboot_script ~prog g root !i cmd

    | `Hostname hostname ->
      msg (f_"Setting the hostname: %s") hostname;
      if not (Hostname.set_hostname g root hostname) then
        warning ~prog (f_"hostname could not be set for this type of guest")

    | `InstallPackages pkgs ->
      msg (f_"Installing packages: %s") (String.concat " " pkgs);
      let cmd = guest_install_command pkgs in
      do_run ~display:cmd cmd

    | `Link (target, links) ->
      List.iter (
        fun link ->
          msg (f_"Linking: %s -> %s") link target;
          g#ln_sf target link
      ) links

    | `Mkdir dir ->
      msg (f_"Making directory: %s") dir;
      g#mkdir_p dir

    | `Password (user, pw) ->
      set_password user pw

    | `RootPassword pw ->
      set_password "root" pw

    | `Script script ->
      msg (f_"Running: %s") script;
      let cmd = read_whole_file script in
      do_run ~display:script cmd

    | `Scrub path ->
      msg (f_"Scrubbing: %s") path;
      g#scrub_file path

    | `Timezone tz ->
      msg (f_"Setting the timezone: %s") tz;
      if not (Timezone.set_timezone ~prog g root tz) then
        warning ~prog (f_"timezone could not be set for this type of guest")

    | `Update ->
      msg (f_"Updating core packages");
      let cmd = guest_update_command () in
      do_run ~display:cmd cmd

    | `Upload (path, dest) ->
      msg (f_"Uploading: %s to %s") path dest;
      let dest =
        if g#is_dir ~followsymlinks:true dest then
          dest ^ "/" ^ Filename.basename path
        else
          dest in
      (* Do the file upload. *)
      g#upload path dest;

      (* Copy (some of) the permissions from the local file to the
       * uploaded file.
       *)
      let statbuf = stat path in
      let perms = statbuf.st_perm land 0o7777 (* sticky & set*id *) in
      g#chmod perms dest;
      let uid, gid = statbuf.st_uid, statbuf.st_gid in
      g#chown uid gid dest

    | `Write (path, content) ->
      msg (f_"Writing: %s") path;
      g#write path content
  ) ops.ops;

  (* Set all the passwords at the end. *)
  if Hashtbl.length passwords > 0 then (
    match g#inspect_get_type root with
    | "linux" ->
      msg (f_"Setting passwords");
      let password_crypto = ops.flags.password_crypto in
      set_linux_passwords ~prog ?password_crypto g root passwords

    | _ ->
      warning ~prog (f_"passwords could not be set for this type of guest")
  );

  if ops.flags.selinux_relabel then (
    msg (f_"SELinux relabelling");
    if guest_arch_compatible then (
      let cmd = sprintf "
        if load_policy && fixfiles restore; then
          rm -f /.autorelabel
        else
          touch /.autorelabel
          echo '%s: SELinux relabelling failed, will relabel at boot instead.'
        fi
      " prog in
      do_run ~display:"load_policy && fixfiles restore" cmd
    ) else (
      g#touch "/.autorelabel"
    )
  );

  (* Clean up the log file:
   *
   * If debugging, dump out the log file.
   * Then if asked, scrub the log file.
   *)
  if verbose then debug_logfile ();
  if ops.flags.scrub_logfile && g#exists logfile then (
    msg (f_"Scrubbing the log file");

    (* Try various methods with decreasing complexity. *)
    try g#scrub_file logfile
    with _ -> g#rm_f logfile
  );

  (* Kill any daemons (eg. started by newly installed packages) using
   * the sysroot.
   * XXX How to make this nicer?
   * XXX fuser returns an error if it doesn't kill any processes, which
   * is not very useful.
   *)
  (try ignore (g#debug "sh" [| "fuser"; "-k"; "/sysroot" |])
   with exn ->
     if verbose then
       eprintf (f_"%s: %s (ignored)\n") prog (Printexc.to_string exn)
  );
  g#ping_daemon () (* tiny delay after kill *)
