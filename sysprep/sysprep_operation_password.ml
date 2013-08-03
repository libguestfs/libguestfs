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

module G = Guestfs

(* glibc 2.7 was released in Oct 2007.  Approximately, all guests that
 * precede this date only support md5, whereas all guests after this
 * date can support sha512.
 *)
let default_crypto g root =
  let distro = g#inspect_get_distro root in
  let major = g#inspect_get_major_version root in
  match distro, major with
  | ("rhel"|"centos"|"scientificlinux"|"redhat-based"), v when v >= 6 ->
    `SHA512
  | ("rhel"|"centos"|"scientificlinux"|"redhat-based"), _ ->
    `MD5 (* RHEL 5 does not appear to support SHA512, according to crypt(3) *)

  | "fedora", v when v >= 9 -> `SHA512
  | "fedora", _ -> `MD5

  | "debian", v when v >= 5 -> `SHA512
  | "debian", _ -> `MD5

  | _, _ ->
    eprintf (f_"\
virt-sysprep: password: warning: using insecure md5 password encryption for
guest of type %s version %d.
If this is incorrect, use --password-crypto option and file a bug.\n")
      distro major;
    `MD5

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
  let i =
    try String.index arg ':'
    with Not_found ->
      eprintf (f_"virt-sysprep: password: invalid --root-password/--password format; see the man page.\n");
      exit 1 in
  let key, value =
    let len = String.length arg in
    String.sub arg 0 i, String.sub arg (i+1) (len-(i+1)) in

  let password =
    match key with
    | "file" -> read_password_from_file value
    | "password" -> value
    | _ ->
      eprintf (f_"virt-sysprep: password: invalid --root-password/--password format, \"%s:...\" is not recognized; see the man page.\n") key;
      exit 1 in

  if Hashtbl.mem passwords user then (
    eprintf (f_"virt-sysprep: password: multiple --root-password/--password options set the password for user '%s' twice.\n") user;
    exit 1
  );

  Hashtbl.replace passwords user password

and read_password_from_file filename =
  let chan = open_in filename in
  let password = input_line chan in
  close_in chan;
  password

let password_crypto : [`MD5 | `SHA256 | `SHA512 ] option ref = ref None

let set_password_crypto = function
  | "md5" -> password_crypto := Some `MD5
  | "sha256" -> password_crypto := Some `SHA256
  | "sha512" -> password_crypto := Some `SHA512
  | arg ->
    eprintf (f_"virt-sysprep: password-crypto: unknown algorithm %s, use \"md5\", \"sha256\" or \"sha512\".\n") arg;
    exit 1

(* Permissible characters in a salt. *)
let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./"
let nr_chars = String.length chars

let rec password_perform g root =
  if Hashtbl.length passwords > 0 then (
    let typ = g#inspect_get_type root in
    match typ with
    | "linux" ->
      set_linux_passwords g root;
      [ `Created_files ]
    | _ ->
      eprintf (f_"virt-sysprep: cannot set passwords for %s guests.\n") typ;
      exit 1
  )
  else []

and set_linux_passwords g root =
  let crypto =
    match !password_crypto with
    | None -> default_crypto g root
    | Some c -> c in

  (* XXX Would like to use Augeas here, but Augeas doesn't support
   * /etc/shadow (as of 1.1.0).
   *)

  let shadow = Array.to_list (g#read_lines "/etc/shadow") in
  let shadow =
    List.map (
      fun line ->
        try
          (* Each line is: "user:password:..."
           * 'i' points to the first colon, 'j' to the second colon.
           *)
          let i = String.index line ':' in
          let user = String.sub line 0 i in
          let password = Hashtbl.find passwords user in
          let j = String.index_from line (i+1) ':' in
          let rest = String.sub line j (String.length line - j) in
          user ^ ":" ^ encrypt password crypto ^ rest
        with Not_found -> line
    ) shadow in

  g#write "/etc/shadow" (String.concat "\n" shadow ^ "\n");
  g#chmod 0 "/etc/shadow" (* ... and /.autorelabel will label it correctly. *)

(* Encrypt each password.  Use glibc (on the host).  See:
 * https://rwmj.wordpress.com/2013/07/09/setting-the-root-or-other-passwords-in-a-linux-guest/
 *)
and encrypt password crypto =
  (* Get random characters from the set [A-Za-z0-9./] *)
  let salt =
    let chan = open_in "/dev/urandom" in
    let buf = String.create 16 in
    for i = 0 to 15 do
      buf.[i] <- chars.[Char.code (input_char chan) mod nr_chars]
    done;
    close_in chan;
    buf in
  let salt =
    (match crypto with
    | `MD5 -> "$1$"
    | `SHA256 -> "$5$"
    | `SHA512 -> "$6$") ^ salt ^ "$" in
  let r = Crypt.crypt password salt in
  (*printf "password: encrypt %s with salt %s -> %s\n" password salt r;*)
  r

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
      ("--root-password", Arg.String set_root_password,
       s_"..." ^ " " ^ s_"set root password (see man page)"),
      s_"\
Set the root password.  The following formats may be used
for this option:

=over 4

=item B<--root-password file:FILENAME>

Read the root password from C<FILENAME>.  The whole
first line of this file is the replacement password.
Any other lines are ignored.  You should create the file
with mode 0600 to ensure no one else can read it.

=item B<--root-password password:PASSWORD>

Set the root password to the literal string C<PASSWORD>.

B<Note: this is not secure> since any user on the same machine
can see the cleartext password using L<ps(1)>.

=back";

      ("--password", Arg.String set_user_password,
       s_"..." ^ " " ^ s_"set user password (see man page)"),
      s_"\
Set a user password.  The user must exist already (this option
does I<not> create users).  The following formats may be used
for this option:

=over 4

=item B<--password USERNAME:file:FILENAME>

Change the password for C<USERNAME>.
Read the password from C<FILENAME>.  The whole
first line of this file is the replacement password.
Any other lines are ignored.  You should create the file
with mode 0600 to ensure no one else can read it.

=item B<--password USERNAME:password:PASSWORD>

Change the password for C<USERNAME>.
Set the password to the literal string C<PASSWORD>.

B<Note: this is not secure> since any user on the same machine
can see the cleartext password using L<ps(1)>.

=back";

      ("--password-crypto", Arg.String set_password_crypto,
       s_"md5|sha256|sha512" ^ " " ^ s_"set password crypto"),
      s_"\
Set the password encryption to C<md5>, C<sha256> or C<sha512>.

C<sha256> and C<sha512> require glibc E<ge> 2.7
(check L<crypt(3)> inside the guest).

C<md5> will work with relatively old Linux guests (eg. RHEL 3), but
is not secure against modern attacks.

The default is C<sha512> unless libguestfs detects an old guest
that didn't have support for SHA-512, in which case it will use C<md5>.
You can override libguestfs by specifying this option.";

    ];

    perform_on_filesystems = Some password_perform;
}

let () = register_operation op
