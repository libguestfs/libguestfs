(* virt-builder
 * Copyright (C) 2015 Red Hat Inc.
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

open Yajl
open Utils

open Printf

let ensure_trailing_slash str =
  if String.length str > 0 && str.[String.length str - 1] <> '/' then str ^ "/"
  else str

let object_find_optional key = function
  | Yajl_object o ->
    (match List.filter (fun (k, _) -> k = key) (Array.to_list o) with
    | [(k, v)] -> Some v
    | [] -> None
    | _ -> error (f_"more than value for the key '%s'") key)
  | _ -> error (f_"the value of the key '%s' is not an object") key

let object_find key yv =
  match object_find_optional key yv with
  | None -> error (f_"missing value for the key '%s'") key
  | Some v -> v

let object_get_string key yv =
  match object_find key yv with
  | Yajl_string s -> s
  | _ -> error (f_"the value for the key '%s' is not a string") key

let object_find_object key yv =
  match object_find key yv with
  | Yajl_object _ as o -> o
  | _ -> error (f_"the value for the key '%s' is not an object") key

let object_find_objects fn = function
  | Yajl_object o -> filter_map fn (Array.to_list o)
  | _ -> error (f_"the value is not an object")

let object_get_object key yv =
  match object_find_object key yv with
  | Yajl_object o -> o
  | _ -> assert false (* object_find_object already errors out. *)

let object_get_number key yv =
  match object_find key yv with
  | Yajl_number n -> n
  | Yajl_double d -> Int64.of_float d
  | _ -> error (f_"the value for the key '%s' is not an integer") key

let objects_get_string key yvs =
  let rec loop = function
    | [] -> None
    | x :: xs ->
      (match object_find_optional key x with
      | Some (Yajl_string s) -> Some s
      | Some _ -> error (f_"the value for key '%s' is not a string as expected") key
      | None -> loop xs
      )
  in
  match loop yvs with
  | Some s -> s
  | None -> error (f_"the key '%s' was not found in a list of objects") key

let get_index ~downloader ~sigchecker
  { Sources.uri = uri; proxy = proxy } =

  let uri = ensure_trailing_slash uri in

  let download_and_parse uri =
    let tmpfile, delete_tmpfile = Downloader.download downloader ~proxy uri in
    if delete_tmpfile then
      unlink_on_exit tmpfile;
    let file =
      if Sigchecker.verifying_signatures sigchecker then (
        let tmpunsigned =
          Sigchecker.verify_and_remove_signature sigchecker tmpfile in
        match tmpunsigned with
        | None -> assert false (* only when not verifying signatures *)
        | Some f -> f
      ) else
        tmpfile in
    yajl_tree_parse (read_whole_file file) in

  let downloads =
    let uri_index =
      if Sigchecker.verifying_signatures sigchecker then
        uri ^ "streams/v1/index.sjson"
      else
        uri ^ "streams/v1/index.json" in
    let tree = download_and_parse uri_index in

    let format = object_get_string "format" tree in
    if format <> "index:1.0" then
      error (f_"%s is not a Simple Streams (index) v1.0 JSON file (format: %s)")
        uri format;

    let index = Array.to_list (object_get_object "index" tree) in
    filter_map (
      fun (_, desc) ->
        let format = object_get_string "format" desc in
        let datatype = object_get_string "datatype" desc in
        match format, datatype with
        | "products:1.0", "image-downloads" ->
          Some (object_get_string "path" desc)
        | _ -> None
    ) index in

  let scan_product_list path =
    let tree = download_and_parse (uri ^ path) in

    let format = object_get_string "format" tree in
    if format <> "products:1.0" then
      error (f_"%s is not a Simple Streams (products) v1.0 JSON file (format: %s)")
        uri format;

    let products_node = object_get_object "products" tree in

    let products = Array.to_list products_node in
    filter_map (
      fun (prod, prod_desc) ->
        let arch = object_get_string "arch" prod_desc in
        let prods = Array.to_list (object_get_object "versions" prod_desc) in
        let prods = filter_map (
          fun (rel, rel_desc) ->
            let pubname = objects_get_string "pubname" [rel_desc; prod_desc] in
            let items = object_find_object "items" rel_desc in
            let disk_items = object_find_objects (
              function
              | (("disk.img"|"disk1.img"), v) -> Some v
              | _ -> None
            ) items in
            (match disk_items with
            | [] -> None
            | disk_item :: _ ->
              let printable_name = Some pubname in
              let file_uri = uri ^ (object_get_string "path" disk_item) in
              let checksums =
                let checksums = object_find_objects (
                  function
                  (* Since this catches all the keys, and not just
                   * the ones related to checksums, explicitly filter
                   * the supported checksums.
                   *)
                  | ("sha256"|"sha512" as t, Yajl_string c) ->
                    Some (Checksums.of_string t c)
                  | _ -> None
                ) disk_item in
                match checksums with
                | [] -> None
                | x -> Some x in
              let revision = Rev_string rel in
              let size = object_get_number "size" disk_item in
              let aliases = Some [pubname;] in

              let entry = { Index.printable_name = printable_name;
                            osinfo = None;
                            file_uri = file_uri;
                            arch = arch;
                            signature_uri = None;
                            checksums = checksums;
                            revision = revision;
                            format = None;
                            size = size;
                            compressed_size = None;
                            expand = None;
                            lvexpand = None;
                            notes = [];
                            hidden = false;
                            aliases = aliases;
                            sigchecker = sigchecker;
                            proxy = proxy; } in
              Some (rel, (prod, entry))
            )
        ) prods in
        (* Select the disk image with the bigger version (i.e. usually
         * the most recent one. *)
        let reverse_revision_compare (rev1, _) (rev2, _) = compare rev2 rev1 in
        let prods = List.sort reverse_revision_compare prods in
        match prods with
        | [] -> None
        | (_, entry) :: _ -> Some entry
    ) products in

  let entries = List.flatten (List.map scan_product_list downloads) in
  if verbose () then (
    printf "simplestreams tree (%s) after parsing:\n" uri;
    List.iter (Index.print_entry Pervasives.stdout) entries
  );
  entries
