(* virt-customize
 * Copyright (C) 2012-2015 Red Hat Inc.
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

val add_firstboot_script : Guestfs.guestfs -> string -> int -> string -> unit
  (** [add_firstboot_script g root idx content] adds a firstboot
      script called [shortname] containing [content].

      NB. [content] is the contents of the script, {b not} a filename.

      The scripts run in index ([idx]) order.

      For Linux guests using SELinux you should make sure the
      filesystem is relabelled after calling this. *)
