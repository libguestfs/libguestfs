(* Bindings for visitor function.
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

(** Bindings for the virt-ls visitor function used to recursively
    visit every file and directory in a filesystem. *)

type visitor_function = string -> string option -> Guestfs.statns -> Guestfs.xattr array -> unit
(** The visitor function is a callback called once for every directory
    and every file.

    For the root directory, [visitor_function dir None statns xattrs] is
    called.  [statns] is the stat of the root directory and the
    array [xattrs] contains extended attributes.

    For all other directories and files,
    [visitor_function dir (Some name) statns xattrs] is called, where
    [dir] is the parent directory path and [name] is the filename
    (which might also be a directory).  [statns] is the stat of [name]
    and the array [xattrs] contains extended attributes.

    The visitor callback may raise an exception, which will cause
    the whole visit to fail with an error (raising the same exception). *)

val visit : Guestfs.t -> string -> visitor_function -> unit
(** [visit g dir f] calls the [visitor_function f] once for
    every directory and every file.

    If the visitor function raises an exception, then the whole visit
    stops and raises the same exception.

    Also other errors can happen, and those will cause a [Failure
    "visit"] exception to be raised.  (Because of the implementation
    of the underlying function, the real error is printed
    unconditionally to stderr).

    If the visit function returns normally you can assume there
    was no error. *)

val full_path : string -> string option -> string
(** This can be called with the [dir] and [name] parameters from
    [visitor_function] to return the full canonical path. *)

val is_reg : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a regular file. *)
val is_dir : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a directory. *)
val is_chr : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a character device. *)
val is_blk : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a block device. *)
val is_fifo : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a FIFO. *)
val is_lnk : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a symbolic link. *)
val is_sock : int64 -> bool
(** Returns true if [G.statns.st_mode] represents a Unix domain socket. *)
