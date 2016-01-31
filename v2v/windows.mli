(* virt-v2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

(** Common Windows functions. *)

val detect_antivirus : Types.inspect -> bool
(** Return [true] if anti-virus (AV) software was detected in
    this Windows guest. *)

val with_hive_readonly : Guestfs.guestfs -> string -> (int64 -> 'a) -> 'a
val with_hive_write : Guestfs.guestfs -> string -> (int64 -> 'a) -> 'a
(** These are wrappers that handle opening and closing the hive
    properly around a function [f].

    [with_hive_readonly] opens the hive for read-only (attempts
    to write will throw an error).  [with_hive_write] opens the
    hive for writes, and commits the changes at the end if there
    were no errors. *)

val get_node : Guestfs.guestfs -> int64 -> string list -> int64 option
(** [get_node g root path] starts at the [root] node of the hive (it does
    not need to be the actual hive root), and searches down the [path].
    It returns [Some node] of the final node if found, or [None] if
    not found. *)
