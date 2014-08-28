(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** Functions for dealing with ESX. *)

open Xml
open Utils

open Printf

let esx_re = Str.regexp "^\\[\\(.*\\)\\] \\(.*\\)\\.vmdk$"

(* Map an ESX <source/> to a qemu URI using the cURL driver
 * in qemu.  The 'path' will be something like
 *
 *   "[datastore1] Fedora 20/Fedora 20.vmdk"
 *
 * including those literal spaces in the string.
 *
 * We want to convert that into the following URL:
 *   "https://user:password@server/folder/Fedora 20/Fedora 20-flat.vmdk" ^
 *     "?dcPath=ha-datacenter&dsName=datastore1"
 *
 * Note that the URL we create here is passed to qemu-img and is
 * ultimately parsed by curl_easy_setopt (CURLOPT_URL).
 *
 * XXX Old virt-v2v could also handle snapshots, ie:
 *
 *   "[datastore1] Fedora 20/Fedora 20-NNNNNN.vmdk"
 *
 * However this requires access to the server which we don't necessarily
 * have here.
 *)
let map_path_to_uri uri path format =
  if not (Str.string_match esx_re path 0) then
    path, format
  else (
    let datastore = Str.matched_group 1 path
    and vmdk = Str.matched_group 2 path in

    let user =
      match uri.uri_user with
      | None -> ""
      | Some user -> user ^ "@" (* No need to quote it, see RFC 2617. *) in
    let server =
      match uri.uri_server with
      | None -> assert false (* checked by caller *)
      | Some server -> server in
    let port =
      match uri.uri_port with
      | 443 -> ""
      | n when n >= 1 -> ":" ^ string_of_int n
      | _ -> "" in

    let qemu_uri =
      sprintf
        "https://%s%s%s/folder/%s-flat.vmdk?dcPath=ha-datacenter&dsName=%s"
        user server port vmdk (uri_quote datastore) in

    (* The libvirt ESX driver doesn't normally specify a format, but
     * the format of the -flat file is *always* raw, so force it here.
     *)
    qemu_uri, Some "raw"
  )
