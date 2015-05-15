(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

open Sysprep_operation

module G = Guestfs

let scriptdir = ref None
let set_scriptdir dir =
  if !scriptdir <> None then
    error (f_"--scriptdir cannot be used more than once");
  scriptdir := Some dir

let scripts = ref []
let add_script script = scripts := script :: !scripts

let rec script_perform ~quiet (g : Guestfs.guestfs) root side_effects =
  let scripts = List.rev !scripts in
  if scripts <> [] then (
    (* Create a temporary directory? *)
    let scriptdir, cleanup =
      match !scriptdir with
      | Some dir -> dir, false
      | None ->
        let tmpdir = Mkdtemp.temp_dir "virt-sysprep." "" in
        tmpdir, true in

    (* Mount the directory locally. *)
    g#mount_local scriptdir;

    (* Run the script(s)/program(s). *)
    let pid = run_scripts scriptdir scripts in

    (* Run FUSE. *)
    g#mount_local_run ();

    let ok =
      match snd (waitpid [] pid) with
      | WEXITED 0 -> true
      | WEXITED i ->
        warning (f_"script: failed (code %d)") i;
        false
      | WSIGNALED i
      | WSTOPPED i ->
        warning (f_"script: killed by signal (%d)") i;
        false in

    (* Remote temporary directory / mountpoint. *)
    if cleanup then rmdir scriptdir;

    if not ok then failwith (s_"script failed")
  )

(* Run the scripts in the background and make sure they call
 * guestunmount afterwards.
 *)
and run_scripts mp scripts =
  let sh = "/bin/bash" in
  let cmd =
    sprintf "\
set -e
#set -x
cleanup ()
{
  status=$?
  cd /
  guestunmount %s ||:
  exit $status
}
trap cleanup INT TERM QUIT EXIT ERR\n"
      (Filename.quote mp) ^
      String.concat "\n" scripts in
  let args = [| sh; "-c"; cmd |] in

  let pid = fork () in
  if pid = 0 then ( (* child *)
    chdir mp;
    execv sh args
  );
  pid

let op = {
  defaults with
    name = "script";
    enabled_by_default = true;
    heading = s_"Run arbitrary scripts against the guest";
    pod_description = Some (s_"\
The C<script> module lets you run arbitrary shell scripts or programs
against the guest.

Note this feature requires FUSE support.  You may have to enable
this in your host, for example by adding the current user to the
C<fuse> group, or by loading a kernel module.

Use one or more I<--script> parameters to specify scripts or programs
that will be run against the guest.

The script or program is run with its current directory being the
guest's root directory, so relative paths should be used.  For
example: C<rm etc/resolv.conf> in the script would remove a Linux
guest's DNS configuration file, but C<rm /etc/resolv.conf> would
(try to) remove the host's file.

Normally a temporary mount point for the guest is used, but you
can choose a specific one by using the I<--scriptdir> parameter.

B<Note:> This is different from I<--firstboot> scripts (which run
in the context of the guest when it is booting first time).
I<--script> scripts run on the host, not in the guest.");
    extra_args = [
      { extra_argspec = "--scriptdir", Arg.String set_scriptdir, s_"dir" ^ " " ^ s_"Mount point on host";
        extra_pod_argval = Some "SCRIPTDIR";
        extra_pod_description = s_"\
The mount point (an empty directory on the host) used when
the C<script> operation is enabled and one or more scripts
are specified using I<--script> parameter(s).

B<Note:> C<SCRIPTDIR> B<must> be an absolute path.

If I<--scriptdir> is not specified then a temporary mountpoint
will be created."
      };

      { extra_argspec = "--script", Arg.String add_script, s_"script" ^ " " ^ s_"Script or program to run on guest";
        extra_pod_argval = Some "SCRIPT";
        extra_pod_description = s_"\
Run the named C<SCRIPT> (a shell script or program) against the
guest.  The script can be any program on the host.  The script's
current directory will be the guest's root directory.

B<Note:> If the script is not on the $PATH, then you must give
the full absolute path to the script.";
      }
    ];
    perform_on_filesystems = Some script_perform;
}

let () = register_operation op
