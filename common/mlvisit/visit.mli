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

exception Failure

val visit : Guestfs.t -> string -> visitor_function -> unit
(** [visit g dir f] calls the [visitor_function f] once for
    every directory and every file.

    If the visitor function raises an exception, then the whole visit
    stops and raises the same exception.

    Also other errors can happen, and those will cause a {!Failure}
    exception to be raised.  (Because of the implementation
    of the underlying function, the real error is printed
    unconditionally to stderr).

    If the visit function returns normally you can assume there
    was no error. *)
