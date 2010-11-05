(* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

(** In which versions were calls added to the API?

    See [src/api-support] directory for more details. *)

val load_api_versions : string -> unit
(** Load the data from the named file. *)

val lookup_api_version : string -> string option
(** [lookup_api_version c_api] looks up the version that the C API call
    (which must be the full C name, eg. ["guestfs_launch"]) was
    added.  This returns the version string, eg. [Some "0.3"], or
    [None] if no version could be found. *)
