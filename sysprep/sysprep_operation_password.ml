(* virt-sysprep
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

open Printf

open Sysprep_operation
open Common_gettext.Gettext
open Password

module G = Guestfs

let passwords = Hashtbl.create 13

let rec set_root_password arg =
  set_password "root" arg

and set_user_password arg =
  let i =
    try String.index arg ':'
    with Not_found ->
      eprintf (f_"virt-sysprep: password: invalid --password format; see the man page.\n");
      exit 1 in
  let len = String.length arg in
  set_password (String.sub arg 0 i) (String.sub arg (i+1) (len-(i+1)))

and set_password user arg =
  let pw = parse_selector ~prog arg in

  if Hashtbl.mem passwords user then (
    eprintf (f_"virt-sysprep: password: multiple --root-password/--password options set the password for user '%s' twice.\n") user;
    exit 1
  );

  Hashtbl.replace passwords user pw

let password_crypto : password_crypto option ref = ref None

let set_password_crypto arg =
  password_crypto := Some (password_crypto_of_string ~prog arg)

let password_perform g root =
  if Hashtbl.length passwords > 0 then (
    let typ = g#inspect_get_type root in
    match typ with
    | "linux" ->
      let password_crypto = !password_crypto in
      set_linux_passwords ~prog ?password_crypto g root passwords;
      [ `Created_files ]
    | _ ->
      eprintf (f_"virt-sysprep: cannot set passwords for %s guests.\n") typ;
      exit 1
  )
  else []

let op = {
  defaults with
    name = "password";

    (* enabled_by_default because we only do anything if the
     * --password or --root-password parameter is used.
     *)
    enabled_by_default = true;

    heading = s_"Set root or user password";
    pod_description = Some (s_"\
Set root or another user's password.

Use the I<--root-password> option to specify a replacement root
password for the guest.  You can only use this option once.

Use the I<--password> option to specify replacement user password(s).
You can use this option as many times as you want.

Use I<--password-crypto> to change the password encryption used.

See L</OPTIONS> above for details of these options.

This operation is enabled by default, but it only does something
if there is at least one I<--root-password> or I<--password>
argument given.");

    pod_notes = Some (s_"\
Currently this only works for glibc-based Linux guests that
use shadow passwords.");

    extra_args = [
      { extra_argspec = "--root-password", Arg.String set_root_password, s_"..." ^ " " ^ s_"set root password (see man page)";
        extra_pod_argval = Some "SELECTOR";
        extra_pod_description = s_"\
Set the root password.  See I<--password> above for the format
of C<SELECTOR>."
      };

      { extra_argspec = "--password", Arg.String set_user_password, s_"..." ^ " " ^ s_"set user password (see man page)";
        extra_pod_argval = Some "USERNAME:SELECTOR";
        extra_pod_description = s_"\
Set a user password.  The user must exist already (this option
does I<not> create users).

The I<--password> option takes C<USERNAME:SELECTOR>.  The
I<--root-password> option takes just the C<SELECTOR>.  The
format of the C<SELECTOR> is described below:

=over 4

=item B<--password USERNAME:file:FILENAME>

=item B<--root-password file:FILENAME>

Read the password from C<FILENAME>.  The whole
first line of this file is the replacement password.
Any other lines are ignored.  You should create the file
with mode 0600 to ensure no one else can read it.

=item B<--password USERNAME:password:PASSWORD>

=item B<--root-password password:PASSWORD>

Set the password to the literal string C<PASSWORD>.

B<Note: this is not secure> since any user on the same machine
can see the cleartext password using L<ps(1)>.

=back"
      };

      { extra_argspec = "--password-crypto", Arg.String set_password_crypto, s_"md5|sha256|sha512" ^ " " ^ s_"set password crypto";
        extra_pod_argval = Some "md5|sha256|sha512";
        extra_pod_description = s_"\
Set the password encryption to C<md5>, C<sha256> or C<sha512>.

C<sha256> and C<sha512> require glibc E<ge> 2.7
(check L<crypt(3)> inside the guest).

C<md5> will work with relatively old Linux guests (eg. RHEL 3), but
is not secure against modern attacks.

The default is C<sha512> unless libguestfs detects an old guest
that didn't have support for SHA-512, in which case it will use C<md5>.
You can override libguestfs by specifying this option."
      }
    ];

    perform_on_filesystems = Some password_perform;
}

let () = register_operation op
