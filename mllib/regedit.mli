(* virt-v2v
 * Copyright (C) 2014 Red Hat Inc.
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

(** A simple registry editor.

    This uses the libguestfs hivex bindings to implement a simple
    registry editor in the style of [regedit] / [hivexregedit].  We have
    to write this because the [Win::Hivex::Regedit] APIs are Perl-only.

    It has a large number of limitations compared to
    [Win::Hivex::Regedit].  It's just enough code to allow us to
    implement virt-v2v and firstboot functionality, and no more.  In
    particular it can only add keys, not delete or edit them. *)

type regedits = regedit list
(** A list of registry "edits" (although only adding keys is supported). *)

and regedit = regkeypath * regvalues
(** A single key ([regkeypath]) is added, with a list of values for that key. *)

and regkeypath = string list
(** Path to the new key, starting from the root node.  New path elements
    are created as required. *)

and regvalues = regvalue list

and regvalue = string * regtype

and regtype =
| REG_NONE
| REG_SZ of string                      (** String. *)
| REG_EXPAND_SZ of string               (** String with %env% *)
| REG_BINARY of string                  (** Blob of binary data *)
| REG_DWORD of int32                    (** Little endian 32 bit integer *)
| REG_MULTI_SZ of string list           (** List of strings *)
(* There are more types in the Registry, but we don't support them here... *)
(** Registry value type and data.

    Note that strings are automatically converted from UTF-8 to
    UTF-16LE, and integers are automatically packed and
    byte-swapped. *)

val reg_import : Guestfs.guestfs -> int64 -> regedits -> unit
(** Import the edits in [regedits] into the currently opened hive. *)

val encode_utf16le : string -> string
(** Helper: Take a 7 bit ASCII string and encode it as UTF-16LE. *)

val decode_utf16le : prog:string -> string -> string
(** Helper: Take a UTF-16LE string and decode it to UTF-8. *)
