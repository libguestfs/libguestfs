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
open Common_utils

open Printf

(* Implement the --edit option.
 *
 * Code copied from virt-edit.
 *)
let rec edit_file ~debug (g : Guestfs.guestfs) file expr =
  let file_old = file ^ "~" in
  g#rename file file_old;

  (* Download the file to a temporary. *)
  let tmpfile = Filename.temp_file "vbedit" "" in
  unlink_on_exit tmpfile;
  g#download file_old tmpfile;

  do_perl_edit ~debug g tmpfile expr;

  (* Upload the file.  Unlike virt-edit we can afford to fail here
   * so we don't need the temporary upload file.
   *)
  g#upload tmpfile file;

  (* However like virt-edit we do need to copy attributes. *)
  copy_attributes g file_old file;
  g#rm file_old

and do_perl_edit ~debug g file expr =
  (* Pass the expression to Perl via the environment.  This sidesteps
   * any quoting problems with the already complex Perl command line.
   *)
  Unix.putenv "virt_edit_expr" expr;

  (* Call out to a canned Perl script. *)
  let cmd = sprintf "\
    perl -e '
      $lineno = 0;
      $expr = $ENV{virt_edit_expr};
      while (<STDIN>) {
        $lineno++;
        eval $expr;
        die if $@;
        print STDOUT $_ or die \"print: $!\";
      }
      close STDOUT or die \"close: $!\";
    ' < %s > %s.out" file file in

  if debug then
    eprintf "%s\n%!" cmd;

  let r = Sys.command cmd in
  if r <> 0 then (
    eprintf (f_"virt-builder: error: could not evaluate Perl expression '%s'\n")
      expr;
    exit 1
  );

  Unix.rename (file ^ ".out") file

and copy_attributes g src dest =
  let has_linuxxattrs = g#feature_available [|"linuxxattrs"|] in

  (* Get the mode. *)
  let stat = g#stat src in

  (* Get the SELinux context.  XXX Should we copy over other extended
   * attributes too?
   *)
  let selinux_context =
    if has_linuxxattrs then (
      try Some (g#getxattr src "security.selinux") with _ -> None
    ) else None in

  (* Set the permissions (inc. sticky and set*id bits), UID, GID. *)
  let mode = Int64.to_int stat.G.mode
  and uid = Int64.to_int stat.G.uid and gid = Int64.to_int stat.G.gid in
  g#chmod (mode land 0o7777) dest;
  g#chown uid gid dest;

  (* Set the SELinux context. *)
  match selinux_context with
  | None -> ()
  | Some selinux_context ->
    g#setxattr "security.selinux"
      selinux_context (String.length selinux_context) dest
