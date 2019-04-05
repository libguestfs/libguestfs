(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

type remote_resource = {
  https_url : string;
  (** The full URL of the remote disk as an https link on the vCenter
      server.  It will have the general form
      [https://vcenter/folder/.../guest-flat.vmdk?dcPath=...&...] *)

  qemu_uri : string;
  (** The remote disk as a QEMU URI.  This opaque blob (usually a
      [json:] URL) can be passed to [qemu] or [qemu-img] as a backing
      file. *)

  session_cookie : string option;
  (** When creating the URLs above, the module contacts the vCenter
      server, logs in, and gets the session cookie, which can later
      be passed back to the server instead of having to log in each
      time (this is also more efficient since it avoids vCenter
      running out of authentication sessions).

      This can be [None] if the session cookie could not be read (but
      authentication was successful).  You can proceed without the
      session cookie in this case, but there is an unavoidable
      danger of running out of authentication sessions.  If the
      session cookie could not be read, this function prints a
      warning.

      If authentication {i failed} then the {!map_source} function
      would exit with an error, so [None] does not indicate auth
      failure. *)

  sslverify : bool;
  (** This is true except when the libvirt URI had [?no_verify=1] in
      the parameters. *)
}
(** The "remote resource" is the structure returned by the {!map_source}
    function. *)

val map_source : ?password_file:string -> string -> Xml.uri -> string -> string -> remote_resource
(** [map_source ?password_file dcPath uri server path]
    maps the [<source path=...>] string to a {!remote_resource}
    structure containing both an [https://] URL and a qemu URI,
    both pointing the guest disk.

    The input [path] comes from libvirt and will be something like:
    ["[datastore1] Fedora 20/Fedora 20.vmdk"]
    (including those literal spaces in the string).

    This checks that the disk exists and that authentication is
    correct, otherwise it will fail. *)
