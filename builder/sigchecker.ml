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

open Utils

open Printf
open Unix

type gpgkey_type =
  | No_Key
  | Fingerprint of string
  | KeyFile of string

type t = {
  verbose : bool;
  gpg : string;
  fingerprint : string;
  check_signature : bool;
  gpghome : string;
}

(* Import the specified key file. *)
let import_keyfile ~gpg ~gpghome ~verbose keyfile =
  let status_file = Filename.temp_file "vbstat" ".txt" in
  unlink_on_exit status_file;
  let cmd = sprintf "%s --homedir %s --status-file %s --import %s%s"
    gpg gpghome (quote status_file) (quote keyfile)
    (if verbose then "" else " >/dev/null 2>&1") in
  if verbose then printf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then
    error (f_"could not import public key\nUse the '-v' option and look for earlier error messages.");
  status_file

let rec create ~verbose ~gpg ~gpgkey ~check_signature =
  (* Create a temporary directory for gnupg. *)
  let tmpdir = Mkdtemp.temp_dir "vb.gpghome." "" in
  rmdir_on_exit tmpdir;
  (* Make sure we have no check_signature=true with no actual key. *)
  let check_signature, gpgkey =
    match check_signature, gpgkey with
    | true, No_Key -> false, No_Key
    | x, y -> x, y in
  let fingerprint =
    if check_signature then (
      (* Run gpg so it can setup its own home directory, failing if it
       * cannot.
       *)
      let cmd = sprintf "%s --homedir %s --list-keys%s"
        gpg tmpdir (if verbose then "" else " >/dev/null 2>&1") in
      if verbose then printf "%s\n%!" cmd;
      let r = Sys.command cmd in
      if r <> 0 then
        error (f_"GPG failure: could not run GPG the first time\nUse the '-v' option and look for earlier error messages.");
      match gpgkey with
      | No_Key ->
        assert false
      | KeyFile kf ->
        let status_file = import_keyfile gpg tmpdir verbose kf in
        let status = read_whole_file status_file in
        let status = string_nsplit "\n" status in
        let fingerprint = ref "" in
        List.iter (
          fun line ->
            let line = string_nsplit " " line in
            match line with
            | "[GNUPG:]" :: "IMPORT_OK" :: _ :: fp :: _ -> fingerprint := fp
            | _ -> ()
        ) status;
        !fingerprint
      | Fingerprint fp ->
        let filename = Filename.temp_file "vbpubkey" ".asc" in
        unlink_on_exit filename;
        let cmd = sprintf "%s --yes --armor --output %s --export %s%s"
          gpg (quote filename) (quote fp)
          (if verbose then "" else " >/dev/null 2>&1") in
        if verbose then printf "%s\n%!" cmd;
        let r = Sys.command cmd in
        if r <> 0 then
          error (f_"could not export public key\nUse the '-v' option and look for earlier error messages.");
        ignore (import_keyfile gpg tmpdir verbose filename);
        fp
    ) else
      "" in
  {
    verbose = verbose;
    gpg = gpg;
    fingerprint = fingerprint;
    check_signature = check_signature;
    gpghome = tmpdir;
  }

(* Compare two strings of hex digits ignoring whitespace and case. *)
and equal_fingerprints fp1 fp2 =
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
      error (f_"there is no detached signature file\nThis probably means the index file is missing a sig=... line.\nYou can use --no-check-signature to ignore this error, but that means\nyou are susceptible to man-in-the-middle attacks.\n")
    | Some sigfile ->
      let args = sprintf "%s %s" (quote sigfile) (quote filename) in
      do_verify t args
  )

and do_verify t args =
  let status_file = Filename.temp_file "vbstat" ".txt" in
  unlink_on_exit status_file;
  let cmd =
    sprintf "%s --homedir %s --verify%s --status-file %s %s"
        t.gpg t.gpghome
        (if t.verbose then "" else " -q --logger-file /dev/null")
        (quote status_file) args in
  if t.verbose then printf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then
    error (f_"GPG failure: could not verify digital signature of file\nTry:\n - Use the '-v' option and look for earlier error messages.\n - Delete the cache: virt-builder --delete-cache\n - Check no one has tampered with the website or your network!");

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

  if not (equal_fingerprints !fingerprint t.fingerprint) then
    error (f_"fingerprint of signature does not match the expected fingerprint!\n  found fingerprint: %s\n  expected fingerprint: %s")
      !fingerprint t.fingerprint

type csum_t = SHA512 of string

let verify_checksum t (SHA512 csum) filename =
  let csum_file = Filename.temp_file "vbcsum" ".txt" in
  unlink_on_exit csum_file;
  let cmd = sprintf "sha512sum %s | awk '{print $1}' > %s"
    (quote filename) (quote csum_file) in
  if t.verbose then printf "%s\n%!" cmd;
  let r = Sys.command cmd in
  if r <> 0 then
    error (f_"could not run sha512sum command to verify checksum");

  let csum_actual = read_whole_file csum_file in

  let csum_actual =
    let len = String.length csum_actual in
    if len > 0 && csum_actual.[len-1] = '\n' then
      String.sub csum_actual 0 (len-1)
    else
      csum_actual in

  if csum <> csum_actual then
    error (f_"checksum of template did not match the expected checksum!\n  found checksum: %s\n  expected checksum: %s\nTry:\n - Use the '-v' option and look for earlier error messages.\n - Delete the cache: virt-builder --delete-cache\n - Check no one has tampered with the website or your network!")
      csum_actual csum
