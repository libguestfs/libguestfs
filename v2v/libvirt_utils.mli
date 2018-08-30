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

(** This module provides helper methods on top of the [Libvirt]
    module. *)

val auth_for_password_file : ?password_file:string -> unit -> Libvirt.Connect.auth
(** [auth_for_password_file ?password_file ()] returns a
    {!Libvirt.Connect.auth} record to use when opening a new libvirt
    connection with {!Libvirt.Connect.connect_auth} or
    {!Libvirt.Connect.connect_auth_readonly}.  The record will
    authenticate using the password specified in the first line of
    [?password_file], if specified. *)

val get_domain : Libvirt.rw Libvirt.Connect.t -> string -> Libvirt.rw Libvirt.Domain.t
(** [get_domain conn dom] returns the libvirt domain with the
    specified [dom] name or UUID.  [conn] is the libvirt
    connection. *)

val get_pool : Libvirt.rw Libvirt.Connect.t -> string -> Libvirt.rw Libvirt.Pool.t
(** [get_pool conn pool] returns the libvirt pool with the
    specified [pool] name or UUID.  [conn] is the libvirt
    connection. *)

val get_volume : Libvirt.rw Libvirt.Pool.t -> string -> Libvirt.rw Libvirt.Volume.t
(** [get_volume pool vol] returns the libvirt volume with the
    specified [vol] name or UUID, as part of the pool [pool]. *)

val domain_exists : Libvirt.rw Libvirt.Connect.t -> string -> bool
(** [domain_exists conn dom] returns a boolean indicating if the
    the libvirt XML domain [dom] exists.  [conn] is the libvirt
    connection.
    [dom] may be a guest name, but not a UUID. *)

val libvirt_get_version : unit -> int * int * int
(** [libvirt_get_version] returns the triple [(major, minor, release)]
    version number of the libvirt library that we are linked against. *)
