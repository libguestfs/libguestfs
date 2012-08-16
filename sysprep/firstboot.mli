(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

val add_firstboot_script : Guestfs.guestfs -> string -> string -> string -> unit
  (** [add_firstboot_script g root id content] adds a firstboot
      script called [shortname] containing [content].

      NB. [content] is the contents of the script, {b not} a filename.

      [id] should be a short name containing only 7 bit ASCII [-a-z0-9].

      You should make sure the filesystem is relabelled after calling this. *)
