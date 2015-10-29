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

open Customize_utils
open Customize_cmdline
open Password

let run (g : Guestfs.guestfs) root (ops : ops) =
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
    try g#download logfile "/dev/stderr"
    with exn ->
      warning (f_"log file %s: %s (ignored)") logfile (Printexc.to_string exn) in

  (* Useful wrapper for scripts. *)
  let do_run ~display cmd =
    if not guest_arch_compatible then
      error (f_"host cpu (%s) and guest arch (%s) are not compatible, so you cannot use command line options that involve running commands in the guest.  Use --firstboot scripts instead.")
            Guestfs_config.host_cpu guest_arch;

    (* Add a prologue to the scripts:
     * - Pass environment variables through from the host.
     * - Send stdout and stderr to a log file so we capture all output
     *   in error messages.
     * - Use setarch when running x86_64 host + i686 guest.
     * Also catch errors and dump the log file completely on error.
     *)
    let env_vars =
      filter_map (
        fun name ->
          try Some (sprintf "export %s=%s" name (quote (Sys.getenv name)))
          with Not_found -> None
      ) [ "http_proxy"; "https_proxy"; "ftp_proxy"; "no_proxy" ] in
    let env_vars = String.concat "\n" env_vars ^ "\n" in

    let cmd =
      match Guestfs_config.host_cpu, guest_arch with
      | "x86_64", ("i386"|"i486"|"i586"|"i686") ->
        sprintf "setarch i686 <<\"__EOCMD\"
%s
__EOCMD
" cmd
      | _ -> cmd in

    let cmd = sprintf "\
exec >>%s 2>&1
%s
%s
" (quote logfile) env_vars cmd in

    if verbose () then printf "running command:\n%s\n%!" cmd;
    try ignore (g#sh cmd)
    with
      Guestfs.Error msg ->
        debug_logfile ();
        error (f_"%s: command exited with an error") display
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
    | "dnf" ->
      sprintf "dnf -y install %s" quoted_args
    | "pisi" ->
      sprintf "pisi it %s" quoted_args
    | "pacman" ->
      sprintf "pacman -S %s" quoted_args
    | "urpmi" ->
      sprintf "urpmi %s" quoted_args
    | "yum" ->
      sprintf "yum -y install %s" quoted_args
    | "zypper" ->
      sprintf "zypper -n in -l %s" quoted_args
    | "unknown" ->
      error (f_"--install is not supported for this guest operating system")
    | pm ->
      error (f_"sorry, don't know how to use --install with the '%s' package manager") pm

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
    | "dnf" ->
      sprintf "dnf -y --best upgrade"
    | "pisi" ->
      sprintf "pisi upgrade"
    | "pacman" ->
      sprintf "pacman -Su"
    | "urpmi" ->
      sprintf "urpmi --auto-select"
    | "yum" ->
      sprintf "yum -y update"
    | "zypper" ->
      sprintf "zypper -n update -l"
    | "unknown" ->
      error (f_"--update is not supported for this guest operating system")
    | pm ->
      error (f_"sorry, don't know how to use --update with the '%s' package manager") pm
  in

  (* Set the random seed. *)
  message (f_"Setting a random seed");
  if not (Random_seed.set_random_seed g root) then
    warning (f_"random seed could not be set for this type of guest");

  (* Store the passwords and set them all at the end. *)
  let passwords = Hashtbl.create 13 in
  let set_password user pw =
    if Hashtbl.mem passwords user then
      error (f_"multiple --root-password/--password options set the password for user '%s' twice") user;
    Hashtbl.replace passwords user pw
  in

  (* Perform the remaining customizations in command-line order. *)
  List.iter (
    function
    | `Chmod (mode, path) ->
      message (f_"Changing permissions of %s to %s") path mode;
      (* If the mode string is octal, add the OCaml prefix for octal values
       * so it is properly converted as octal integer.
       *)
      let mode = if String.is_prefix mode "0" then "0o" ^ mode else mode in
      g#chmod (int_of_string mode) path

    | `Command cmd ->
      message (f_"Running: %s") cmd;
      do_run ~display:cmd cmd

    | `CommandsFromFile _ ->
      (* Nothing to do, the files with customize commands are already
       * read when their arguments are met. *)
      ()

    | `Copy (src, dest) ->
      message (f_"Copying (in image): %s to %s") src dest;
      g#cp_a src dest

    | `CopyIn (localpath, remotedir) ->
      message (f_"Copying: %s to %s") localpath remotedir;
      g#copy_in localpath remotedir

    | `Delete path ->
      message (f_"Deleting: %s") path;
      g#rm_rf path

    | `Edit (path, expr) ->
      message (f_"Editing: %s") path;

      if not (g#is_file path) then
        error (f_"%s is not a regular file in the guest") path;

      Perl_edit.edit_file g#ocaml_handle path expr

    | `FirstbootCommand cmd ->
      message (f_"Installing firstboot command: %s") cmd;
      Firstboot.add_firstboot_script g root cmd cmd

    | `FirstbootPackages pkgs ->
      message (f_"Installing firstboot packages: %s")
        (String.concat " " pkgs);
      let cmd = guest_install_command pkgs in
      let name = String.concat " " ("install" :: pkgs) in
      Firstboot.add_firstboot_script g root name cmd

    | `FirstbootScript script ->
      message (f_"Installing firstboot script: %s") script;
      let cmd = read_whole_file script in
      Firstboot.add_firstboot_script g root script cmd

    | `Hostname hostname ->
      message (f_"Setting the hostname: %s") hostname;
      if not (Hostname.set_hostname g root hostname) then
        warning (f_"hostname could not be set for this type of guest")

    | `InstallPackages pkgs ->
      message (f_"Installing packages: %s") (String.concat " " pkgs);
      let cmd = guest_install_command pkgs in
      do_run ~display:cmd cmd

    | `Link (target, links) ->
      List.iter (
        fun link ->
          message (f_"Linking: %s -> %s") link target;
          g#ln_sf target link
      ) links

    | `Mkdir dir ->
      message (f_"Making directory: %s") dir;
      g#mkdir_p dir

    | `Move (src, dest) ->
      message (f_"Moving: %s -> %s") src dest;
      g#mv src dest

    | `Password (user, pw) ->
      set_password user pw

    | `RootPassword pw ->
      set_password "root" pw

    | `Script script ->
      message (f_"Running: %s") script;
      let cmd = read_whole_file script in
      do_run ~display:script cmd

    | `Scrub path ->
      message (f_"Scrubbing: %s") path;
      g#scrub_file path

    | `SMAttach pool ->
      (match pool with
      | Subscription_manager.PoolAuto ->
        message (f_"Attaching to compatible subscriptions");
        let cmd = "subscription-manager attach --auto" in
        do_run ~display:cmd cmd
      | Subscription_manager.PoolId id ->
        message (f_"Attaching to the pool %s") id;
        let cmd = sprintf "subscription-manager attach --pool=%s" (quote id) in
        do_run ~display:cmd cmd
      )

    | `SMRegister ->
      message (f_"Registering with subscription-manager");
      let creds =
        match ops.flags.sm_credentials with
        | None ->
          error (f_"subscription-manager credentials required for --sm-register")
        | Some c -> c in
      let cmd = sprintf "subscription-manager register --username=%s --password=%s"
                  (quote creds.Subscription_manager.sm_username)
                  (quote creds.Subscription_manager.sm_password) in
      do_run ~display:"subscription-manager register" cmd

    | `SMRemove ->
      message (f_"Removing all the subscriptions");
      let cmd = "subscription-manager remove --all" in
      do_run ~display:cmd cmd

    | `SMUnregister ->
      message (f_"Unregistering with subscription-manager");
      let cmd = "subscription-manager unregister" in
      do_run ~display:cmd cmd

    | `SSHInject (user, selector) ->
      (match g#inspect_get_type root with
      | "linux" | "freebsd" | "netbsd" | "openbsd" | "hurd" ->
        message (f_"SSH key inject: %s") user;
        Ssh_key.do_ssh_inject_unix g user selector
      | _ ->
        warning (f_"SSH key could be injected for this type of guest"))

    | `Truncate path ->
      message (f_"Truncating: %s") path;
      g#truncate path

    | `TruncateRecursive path ->
      message (f_"Recursively truncating: %s") path;
      truncate_recursive g path

    | `Timezone tz ->
      message (f_"Setting the timezone: %s") tz;
      if not (Timezone.set_timezone g root tz) then
        warning (f_"timezone could not be set for this type of guest")

    | `Touch path ->
      message (f_"Running touch: %s") path;
      g#touch path

    | `Update ->
      message (f_"Updating core packages");
      let cmd = guest_update_command () in
      do_run ~display:cmd cmd

    | `Upload (path, dest) ->
      message (f_"Uploading: %s to %s") path dest;
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
      let chown () =
        try g#chown uid gid dest
        with Guestfs.Error m as e ->
          if g#last_errno () = Guestfs.Errno.errno_EPERM
          then warning "%s" m
          else raise e in
      chown ()

    | `Write (path, content) ->
      message (f_"Writing: %s") path;
      g#write path content
  ) ops.ops;

  (* Set all the passwords at the end. *)
  if Hashtbl.length passwords > 0 then (
    match g#inspect_get_type root with
    | "linux" ->
      message (f_"Setting passwords");
      let password_crypto = ops.flags.password_crypto in
      set_linux_passwords ?password_crypto g root passwords

    | _ ->
      warning (f_"passwords could not be set for this type of guest")
  );

  if ops.flags.selinux_relabel then (
    message (f_"SELinux relabelling");
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
  if verbose () then debug_logfile ();
  if ops.flags.scrub_logfile && g#exists logfile then (
    message (f_"Scrubbing the log file");

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
     if verbose () then
       printf (f_"%s: %s (ignored)\n") prog (Printexc.to_string exn)
  );
  g#ping_daemon () (* tiny delay after kill *)
