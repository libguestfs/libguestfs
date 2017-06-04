(** Augeas OCaml bindings *)
(* Copyright (C) 2008 Red Hat Inc., Richard W.M. Jones
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *
 * $Id: augeas.mli,v 1.2 2008/05/06 10:48:20 rjones Exp $
 *)

type t
  (** Augeas library handle. *)

exception Error of string
  (** This exception is thrown when the underlying Augeas library
      returns an error. *)

type flag =
  | AugSaveBackup			(** Rename original with .augsave *)
  | AugSaveNewFile			(** Save changes to .augnew *)
  | AugTypeCheck			(** Type-check lenses *)
  | AugNoStdinc
  | AugSaveNoop
  | AugNoLoad
  (** Flags passed to the {!create} function. *)

type path = string
  (** A path expression.

      Note in future we may replace this with a type-safe path constructor. *)

type value = string
  (** A value. *)

val create : string -> string option -> flag list -> t
  (** [create root loadpath flags] creates an Augeas handle.

      [root] is a file system path describing the location
      of the configuration files.

      [loadpath] is an optional colon-separated list of directories
      which are searched for schema definitions.

      [flags] is a list of flags. *)

val close : t -> unit
  (** [close handle] closes the handle.

      You don't need to close handles explicitly with this function:
      they will be finalized eventually by the garbage collector.
      However calling this function frees up any resources used by the
      underlying Augeas library immediately.

      Do not use the handle after closing it. *)

val get : t -> path -> value option
  (** [get t path] returns the value at [path], or [None] if there
      is no value. *)

val exists : t -> path -> bool
  (** [exists t path] returns true iff there is a value at [path]. *)

val insert : t -> ?before:bool -> path -> string -> unit
  (** [insert t ?before path label] inserts [label] as a sibling
      of [path].  By default it is inserted after [path], unless
      [~before:true] is specified. *)

val rm : t -> path -> int
  (** [rm t path] removes all nodes matching [path].

      Returns the number of nodes removed (which may be 0). *)

val matches : t -> path -> path list
  (** [matches t path] returns a list of path expressions
      of all nodes matching [path]. *)

val count_matches : t -> path -> int
  (** [count_matches t path] counts the number of nodes matching
      [path] but does not return them (see {!matches}). *)

val save : t -> unit
  (** [save t] saves all pending changes to disk. *)

val load : t -> unit
  (** [load t] loads files into the tree. *)
