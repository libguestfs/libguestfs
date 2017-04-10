(* virt-v2v
 * Copyright (C) 2017 Red Hat Inc.
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

(** A simple parser for VMware [.vmx] files. *)

type t

val parse_file : string -> t
(** [parse_file filename] parses a VMX file. *)

val parse_string : string -> t
(** [parse_string s] parses VMX from a string. *)

val get_string : t -> string list -> string option
(** Find a key and return it as a string.  If not present, returns [None].

    Note that if [namespace.present = "FALSE"] is found in the file
    then all keys in [namespace] and below it are ignored.  This
    applies to all [get_*] functions. *)

val get_int64 : t -> string list -> int64 option
(** Find a key and return it as an [int64].
    If not present, returns [None].

    Raises [Failure _] if the key is present but was not parseable
    as an integer. *)

val get_int : t -> string list -> int option
(** Find a key and return it as an [int].
    If not present, returns [None].

    Raises [Failure _] if the key is present but was not parseable
    as an integer. *)

val get_bool : t -> string list -> bool option
(** Find a key and return it as a boolean.

    You cannot return [namespace.present = "FALSE"] booleans this way.
    They are processed by the parser and the namespace and anything
    below it are removed from the tree.

    Raises [Failure _] if the key is present but was not parseable
    as a boolean. *)

val namespace_present : t -> string list -> bool
(** Returns true iff the namespace ({b note:} not key) is present. *)

val select_namespaces : (string list -> bool) -> t -> t
(** Filter the VMX file, selecting exactly namespaces (and their
    keys) matching the predicate.  The predicate is a function which
    is called on each {i namespace} path ({b note:} not on
    namespace + key paths).  If the predicate matches a
    namespace, then all sub-namespaces under that namespace are
    selected implicitly. *)

val map : (string list -> string option -> 'a) -> t -> 'a list
(** Map all the entries in the VMX file into a list using the
    map function.  The map function takes two arguments.  The
    first is the path to the namespace or key, and the second
    is the key value (or [None] if the path refers to a namespace). *)

val equal : t -> t -> bool
(** Compare two VMX files for equality.  This is mainly used for
    testing the parser. *)

val empty : t
(** An empty VMX file. *)

val print : out_channel -> int -> t -> unit
(** [print chan indent] prints the VMX file to the output channel.
    [indent] is the indentation applied to each line of output. *)

val to_string : int -> t -> string
(** Same as {!print} but it creates a printable (multiline) string. *)
