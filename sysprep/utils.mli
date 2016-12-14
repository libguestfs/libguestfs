(* virt-sysprep
 * Copyright (C) 2016 Red Hat Inc.
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

(** Utility functions. *)

val pod_of_list : ?style:[`Verbatim|`Star|`Dash|`Dot] -> string list -> string
(** Convert a list of items to something which can be
    added to POD documentation.

    The optional [?style] parameter can be: [`Verbatim] meaning
    use a space-indented (verbatim) block.  [`Star], [`Dash] or [`Dot]
    meaning use a real list with [*], [-] or [·].  The default
    style is [·] ([`Dot]). *)
