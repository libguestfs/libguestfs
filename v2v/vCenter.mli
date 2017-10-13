(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** Functions for dealing with VMware vCenter. *)

val get_session_cookie : string option -> string -> Xml.uri -> bool -> string -> string option
(** [get_session_cookie password scheme uri sslverify url]
    contacts the vCenter server, logs in, and gets the session cookie,
    which can later be passed back to the server instead of having to
    log in each time (this is also more efficient since it avoids
    vCenter running out of authentication sessions).

    Returns [None] if the session cookie could not be read (but
    authentication was successful).  You can proceed without the
    session cookie in this case, but there is an unavoidable
    danger of running out of authentication sessions.  If the
    session cookie could not be read, this function prints a
    warning.

    The session cookie is memoized so you can call this function as
    often as you want, and only a single log in is made. *)

val map_source_to_uri : int option -> string -> string option -> Xml.uri -> string -> string -> string -> string
(** [map_source_to_uri readahead dcPath password uri scheme server path]
    maps the [<source path=...>] string to a qemu URI.

    The [path] will be something like:

    ["[datastore1] Fedora 20/Fedora 20.vmdk"]

    including those literal spaces in the string. *)

val map_source_to_https : string -> Xml.uri -> string -> string -> string * bool
(** [map_source_to_https dcPath uri server path] is the same as
    {!map_source_to_uri} but it produces a regular [https://...] URL.
    The returned boolean is whether TLS certificate verification
    should be done. *)
