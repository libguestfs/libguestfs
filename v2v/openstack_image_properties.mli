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

(** Convert metadata to a list of OpenStack image properties.

    These properties are suitable for use by Glance or Cinder.
    Note for Cinder there is a difference between properties and
    image properties (this module implements the latter). *)

val create : Types.source -> Types.target_buses -> Types.guestcaps -> Types.inspect -> Types.target_firmware -> (string * string) list
(** [create source target_buses guestcaps inspect target_firmware]
    translates the metadata into a list of image properties suitable
    for OpenStack.

    The returned list is a set of key=value pairs which can be passed
    to Glance (using [--property key=value]) or to Cinder.  For
    Cinder note that you must not use [--property] since that sets
    volume properties which are different from image properties.
    Instead use [openstack volume set --image-property key=value ...]. *)
