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
open Unix

let quote = Filename.quote

(* These are the public key and fingerprint belonging to
 * Richard W.M. Jones who signs the templates on
 * http://libguestfs.org/download/builder.
 *)
let default_fingerprint = "F777 4FB1 AD07 4A7E 8C87 67EA 9173 8F73 E1B7 68A0"
let default_pubkey = "\
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.14 (GNU/Linux)

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
=neBW
-----END PGP PUBLIC KEY BLOCK-----
"
let key_imported = ref false

type t = {
  debug : bool;
  gpg : string;
  fingerprint : string;
  check_signature : bool;
}

let create ~debug ~gpg ~fingerprint ~check_signature =
  {
    debug = debug;
    gpg = gpg;
    fingerprint = fingerprint;
    check_signature = check_signature;
  }

(* Compare two strings of hex digits ignoring whitespace and case. *)
let rec equal_fingerprints fp1 fp2 =
  let len1 = String.length fp1 and len2 = String.length fp2 in
  let rec loop i j =
    if i = len1 && j = len2 then true (* match! *)
    else if i = len1 || j = len2 then false (* no match - different lengths *)
    else (
      let x1 = getxdigit fp1.[i] and x2 = getxdigit fp2.[j] in
      match x1, x2 with
      | Some x1, Some x2 when x1 = x2 -> loop (i+1) (j+1)
      | Some x1, Some x2 -> false (* no match - different content *)
      | Some _, None -> loop i (j+1)
      | None, Some _ -> loop (i+1) j
      | None, None -> loop (i+1) (j+1)
    )
  in
  loop 0 0

and getxdigit = function
  | '0'..'9' as c -> Some (Char.code c - Char.code '0')
  | 'a'..'f' as c -> Some (Char.code c - Char.code 'a')
  | 'A'..'F' as c -> Some (Char.code c - Char.code 'A')
  | _ -> None

let rec verify t filename =
  if t.check_signature then (
    let args = quote filename in
    do_verify t args
  )

and verify_detached t filename sigfile =
  if t.check_signature then (
    match sigfile with
    | None ->
      eprintf (f_"virt-builder: error: there is no detached signature file\nThis probably means the index file is missing a sig=... line.\nYou can use --no-check-signature to ignore this error, but that means\nyou are susceptible to man-in-the-middle attacks.\n");
      exit 1
    | Some sigfile ->
      let args = sprintf "%s %s" (quote sigfile) (quote filename) in
      do_verify t args
  )

and do_verify t args =
  import_key t;

  let status_file = Filename.temp_file "vbstat" ".txt" in
  unlink_on_exit status_file;
  let cmd =
    sprintf "%s --verify%s --status-file %s %s"
        t.gpg (if t.debug then "" else " -q --logger-file /dev/null")
        (quote status_file) args in
  if t.debug then eprintf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then (
    eprintf (f_"virt-builder: error: GPG failure: could not verify digital signature of file\nTry:\n - Use the '-v' option and look for earlier error messages.\n - Delete the cache: virt-builder --delete-cache\n - Check no one has tampered with the website or your network!\n");
    exit 1
  );

  (* Check the fingerprint is who it should be. *)
  let status = read_whole_file status_file in

  let status = string_nsplit "\n" status in
  let fingerprint = ref "" in
  List.iter (
    fun line ->
      let line = string_nsplit " " line in
      match line with
      | "[GNUPG:]" :: "VALIDSIG" :: fp :: _ -> fingerprint := fp
      | _ -> ()
  ) status;

  if not (equal_fingerprints !fingerprint t.fingerprint) then (
    eprintf (f_"virt-builder: error: fingerprint of signature does not match the expected fingerprint!\n  found fingerprint: %s\n  expected fingerprint: %s\n")
      !fingerprint t.fingerprint;
    exit 1
  )

(* Import the default public key. *)
and import_key t =
  if not !key_imported then (
    let filename, chan = Filename.open_temp_file "vbpubkey" ".asc" in
    unlink_on_exit filename;
    output_string chan default_pubkey;
    close_out chan;

    let cmd = sprintf "%s --import %s%s"
      t.gpg (quote filename)
      (if t.debug then "" else " >/dev/null 2>&1") in
    let r = Sys.command cmd in
    if r <> 0 then (
      eprintf (f_"virt-builder: error: could not import public key\nUse the '-v' option and look for earlier error messages.\n");
      exit 1
    );
    key_imported := true
  )

type csum_t = SHA512 of string

let verify_checksum t (SHA512 csum) filename =
  let csum_file = Filename.temp_file "vbcsum" ".txt" in
  unlink_on_exit csum_file;
  let cmd = sprintf "sha512sum %s | awk '{print $1}' > %s"
    (quote filename) (quote csum_file) in
  if t.debug then eprintf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then (
    eprintf (f_"virt-builder: error: could not run sha512sum command to verify checksum\n");
    exit 1
  );

  let csum_actual = read_whole_file csum_file in

  let csum_actual =
    let len = String.length csum_actual in
    if len > 0 && csum_actual.[len-1] = '\n' then
      String.sub csum_actual 0 (len-1)
    else
      csum_actual in

  if csum <> csum_actual then (
    eprintf (f_"virt-builder: error: checksum of template did not match the expected checksum!\n  found checksum: %s\n  expected checksum: %s\nTry:\n - Use the '-v' option and look for earlier error messages.\n - Delete the cache: virt-builder --delete-cache\n - Check no one has tampered with the website or your network!\n")
      csum_actual csum;
    exit 1
  )
