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

let get_index ~downloader ~sigchecker
  { Sources.uri = uri; proxy = proxy } =
  let corrupt_file () =
    error (f_"The index file downloaded from '%s' is corrupt.\nYou need to ask the supplier of this file to fix it and upload a fixed version.") uri
  in

  let rec get_index () =
    (* Get the index page. *)
    let tmpfile, delete_tmpfile = Downloader.download downloader ~proxy uri in

    (* Check index file signature (also verifies it was fully
     * downloaded and not corrupted in transit).
     *)
    Sigchecker.verify sigchecker tmpfile;

    (* Try parsing the file. *)
    let sections = Ini_reader.read_ini tmpfile in
    if delete_tmpfile then
      (try Unix.unlink tmpfile with _ -> ());

    (* Check for repeated os-version+arch combination. *)
    let name_arch_map = List.map (
      fun (n, fields) ->
        let rec find_arch = function
          | ("arch", None, value) :: y -> value
          | _ :: y -> find_arch y
          | [] -> ""
        in
        n, (find_arch fields)
    ) sections in
    let nseen = Hashtbl.create 13 in
    List.iter (
      fun (n, arch) ->
        let id = n, arch in
        if Hashtbl.mem nseen id then (
          eprintf (f_"%s: index is corrupt: os-version '%s' with architecture '%s' appears two or more times\n") prog n arch;
          corrupt_file ()
        );
        Hashtbl.add nseen id true
    ) name_arch_map;

    (* Check for repeated fields. *)
    List.iter (
      fun (n, fields) ->
        let fseen = Hashtbl.create 13 in
        List.iter (
          fun (field, subkey, _) ->
            let hashkey = (field, subkey) in
            if Hashtbl.mem fseen hashkey then (
              (match subkey with
              | Some value ->
                eprintf (f_"%s: index is corrupt: %s: field '%s[%s]' appears two or more times\n") prog n field value
              | None ->
                eprintf (f_"%s: index is corrupt: %s: field '%s' appears two or more times\n") prog n field);
              corrupt_file ()
            );
            Hashtbl.add fseen hashkey true
        ) fields
    ) sections;

    (* Turn the sections into the final index. *)
    let entries =
      List.map (
        fun (n, fields) ->
          let fields = List.map (fun (k, sk, v) -> (k, sk), v) fields in
          let printable_name =
            try Some (List.assoc ("name", None) fields) with Not_found -> None in
          let osinfo =
            try Some (List.assoc ("osinfo", None) fields) with Not_found -> None in
          let file_uri =
            try make_absolute_uri (List.assoc ("file", None) fields)
            with Not_found ->
              eprintf (f_"%s: no 'file' (URI) entry for '%s'\n") prog n;
            corrupt_file () in
          let arch =
            try List.assoc ("arch", None) fields
            with Not_found ->
              eprintf (f_"%s: no 'arch' entry for '%s'\n") prog n;
            corrupt_file () in
          let signature_uri =
            try Some (make_absolute_uri (List.assoc ("sig", None) fields))
            with Not_found -> None in
          let checksum_sha512 =
            try Some (List.assoc ("checksum", Some "sha512") fields)
            with Not_found ->
              try Some (List.assoc ("checksum", None) fields)
              with Not_found -> None in
          let revision =
            try Rev_int (int_of_string (List.assoc ("revision", None) fields))
            with
            | Not_found -> Rev_int 1
            | Failure "int_of_string" ->
              eprintf (f_"%s: cannot parse 'revision' field for '%s'\n") prog n;
              corrupt_file () in
          let format =
            try Some (List.assoc ("format", None) fields) with Not_found -> None in
          let size =
            try Int64.of_string (List.assoc ("size", None) fields)
            with
            | Not_found ->
              eprintf (f_"%s: no 'size' field for '%s'\n") prog n;
              corrupt_file ()
            | Failure "int_of_string" ->
              eprintf (f_"%s: cannot parse 'size' field for '%s'\n") prog n;
              corrupt_file () in
          let compressed_size =
            try Some (Int64.of_string (List.assoc ("compressed_size", None) fields))
            with
            | Not_found ->
              None
            | Failure "int_of_string" ->
              eprintf (f_"%s: cannot parse 'compressed_size' field for '%s'\n")
                prog n;
              corrupt_file () in
          let expand =
            try Some (List.assoc ("expand", None) fields) with Not_found -> None in
          let lvexpand =
            try Some (List.assoc ("lvexpand", None) fields) with Not_found -> None in
          let notes =
            let rec loop = function
              | [] -> []
              | (("notes", subkey), value) :: xs ->
                let subkey = match subkey with
                | None -> ""
                | Some v -> v in
                (subkey, value) :: loop xs
              | _ :: xs -> loop xs in
            List.sort (
              fun (k1, _) (k2, _) ->
                String.compare k1 k2
            ) (loop fields) in
          let hidden =
            try bool_of_string (List.assoc ("hidden", None) fields)
            with
            | Not_found -> false
            | Failure "bool_of_string" ->
              eprintf (f_"%s: cannot parse 'hidden' field for '%s'\n")
                prog n;
              corrupt_file () in
          let aliases =
            let l =
              try string_nsplit " " (List.assoc ("aliases", None) fields)
              with Not_found -> [] in
            match l with
            | [] -> None
            | l -> Some l in

          let checksums =
            match checksum_sha512 with
            | Some c -> Some [Checksums.SHA512 c]
            | None -> None in

          let entry = { Index.printable_name = printable_name;
                        osinfo = osinfo;
                        file_uri = file_uri;
                        arch = arch;
                        signature_uri = signature_uri;
                        checksums = checksums;
                        revision = revision;
                        format = format;
                        size = size;
                        compressed_size = compressed_size;
                        expand = expand;
                        lvexpand = lvexpand;
                        notes = notes;
                        hidden = hidden;
                        aliases = aliases;
                        proxy = proxy;
                        sigchecker = sigchecker } in
          n, entry
      ) sections in

    if verbose () then (
      printf "index file (%s) after parsing (C parser):\n" uri;
      List.iter (Index.print_entry Pervasives.stdout) entries
    );

    entries

  (* Verify same-origin policy for the file= and sig= fields. *)
  and make_absolute_uri path =
    if String.length path = 0 then (
      eprintf (f_"%s: zero length path in the index file\n") prog;
      corrupt_file ()
    )
    else if string_find path "://" >= 0 then (
      eprintf (f_"%s: cannot use a URI ('%s') in the index file\n") prog path;
      corrupt_file ()
    )
    else if path.[0] = '/' then (
      eprintf (f_"%s: you must use relative paths (not '%s') in the index file\n") prog path;
      corrupt_file ()
    )
    else (
      (* Construct the URI. *)
      try
        let i = String.rindex uri '/' in
        String.sub uri 0 (i+1) ^ path
      with
        Not_found -> uri // path
    )
  in

  get_index ()
