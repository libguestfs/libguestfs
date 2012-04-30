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

open Utils
open Sysprep_operation
open Sysprep_gettext.Gettext

module G = Guestfs

let scriptdir = ref None
let set_scriptdir dir =
  if !scriptdir <> None then (
    eprintf (f_"virt-sysprep: --scriptdir cannot be used more than once\n");
    exit 1
  );
  scriptdir := Some dir

let scripts = ref []
let add_script script = scripts := script :: !scripts

let rec script_perform (g : Guestfs.guestfs) root =
  let scripts = List.rev !scripts in
  if scripts <> [] then (
    (* Create a temporary directory? *)
    let scriptdir, cleanup =
      match !scriptdir with
      | Some dir -> dir, false
      | None ->
        let tmpdir = Filename.temp_dir_name in
        let tmpdir = tmpdir // string_random8 () in
        mkdir tmpdir 0o755;
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
        eprintf (f_"virt-sysprep: script: failed (code %d)\n") i;
        false
      | WSIGNALED i
      | WSTOPPED i ->
        eprintf (f_"virt-sysprep: script: killed by signal (%d)\n") i;
        false in

    (* Remote temporary directory / mountpoint. *)
    if cleanup then rmdir scriptdir;

    if not ok then failwith (s_"script failed")
  );
  []

(* Run the scripts in the background and make sure they call
 * fusermount afterwards.
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
  count=10
  while ! fusermount -u %s >/dev/null 2>&1 && [ $count -gt 0 ]; do
    sleep 1
    ((count--))
  done
  if [ $count -eq 0 ]; then
    echo \"fusermount: failed to unmount directory\" %s >&2
    exit 1
  fi
  exit $status
}
trap cleanup INT TERM QUIT EXIT ERR\n"
      (Filename.quote mp) (Filename.quote mp) ^
      String.concat "\n" scripts in
  let args = [| sh; "-c"; cmd |] in

  let pid = fork () in
  if pid = 0 then ( (* child *)
    chdir mp;
    execv sh args
  );
  pid

let script_op = {
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
can choose a specific one by using the I<--scriptdir> parameter.");
  extra_args = [
    ("--scriptdir", Arg.String set_scriptdir, s_"dir" ^ " " ^ s_"Mount point on host"),
    s_"\
The mount point (an empty directory on the host) used when
the C<script> operation is enabled and one or more scripts
are specified using I<--script> parameter(s).

B<Note:> C<scriptdir> B<must> be an absolute path.

If I<--scriptdir> is not specified then a temporary mountpoint
will be created.";
    ("--script", Arg.String add_script, s_"script" ^ " " ^ s_"Script or program to run on guest"),
    s_"\
Run the named C<script> (a shell script or program) against the
guest.  The script can be any program on the host.  The script's
current directory will be the guest's root directory.

B<Note:> If the script is not on the $PATH, then you must give
the full absolute path to the script.";
  ];
  perform = script_perform;
}

let () = register_operation script_op
