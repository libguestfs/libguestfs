(* virt-sysprep
 * Copyright (C) 2012-2013 Red Hat Inc.
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
open Printf

type password_crypto = [`MD5 | `SHA256 | `SHA512 ]

type password_map = (string, string) Hashtbl.t

let password_crypto_of_string ~prog = function
  | "md5" -> `MD5
  | "sha256" -> `SHA256
  | "sha512" -> `SHA512
  | arg ->
    eprintf (f_"%s: password-crypto: unknown algorithm %s, use \"md5\", \"sha256\" or \"sha512\".\n")
      prog arg;
    exit 1

let rec get_password ~prog arg =
  let i =
    try String.index arg ':'
    with Not_found ->
      eprintf (f_"%s: invalid password format; see the man page.\n") prog;
      exit 1 in
  let key, value =
    let len = String.length arg in
    String.sub arg 0 i, String.sub arg (i+1) (len-(i+1)) in

  match key with
  | "file" -> read_password_from_file value
  | "password" -> value
  | _ ->
    eprintf (f_"%s: password format, \"%s:...\" is not recognized; see the man page.\n") prog key;
    exit 1

and read_password_from_file filename =
  let chan = open_in filename in
  let password = input_line chan in
  close_in chan;
  password

(* Permissible characters in a salt. *)
let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./"
let nr_chars = String.length chars

let rec set_linux_passwords ~prog ?password_crypto g root passwords =
  let crypto =
    match password_crypto with
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
  (* In virt-sysprep /.autorelabel will label it correctly. *)
  g#chmod 0 "/etc/shadow"

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

(* glibc 2.7 was released in Oct 2007.  Approximately, all guests that
 * precede this date only support md5, whereas all guests after this
 * date can support sha512.
 *)
and default_crypto g root =
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
