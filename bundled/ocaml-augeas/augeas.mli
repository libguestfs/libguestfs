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

type flag =
  | AugSaveBackup			(** Rename original with .augsave *)
  | AugSaveNewFile			(** Save changes to .augnew *)
  | AugTypeCheck			(** Type-check lenses *)
  | AugNoStdinc
  | AugSaveNoop
  | AugNoLoad
  | AugNoModlAutoload
  | AugEnableSpan
  | AugNoErrClose
  | AugTraceModuleLoading
  (** Flags passed to the {!create} function. *)

type error_code =
  | AugErrInternal		(** Internal error (bug) *)
  | AugErrPathX			(** Invalid path expression *)
  | AugErrNoMatch		(** No match for path expression *)
  | AugErrMMatch		(** Too many matches for path expression *)
  | AugErrSyntax		(** Syntax error in lens file *)
  | AugErrNoLens		(** Lens lookup failed *)
  | AugErrMXfm			(** Multiple transforms *)
  | AugErrNoSpan		(** No span for this node *)
  | AugErrMvDesc		(** Cannot move node into its descendant *)
  | AugErrCmdRun		(** Failed to execute command *)
  | AugErrBadArg		(** Invalid argument in funcion call *)
  | AugErrLabel			(** Invalid label *)
  | AugErrCpDesc		(** Cannot copy node into its descendant *)
  | AugErrUnknown of int
  (** Possible error codes. *)

type transform_mode =
  | Include
  | Exclude
  (** The operation mode for the {!transform} function. *)

exception Error of error_code * string * string * string * string
  (** This exception is thrown when the underlying Augeas library
      returns an error.  The tuple represents:
      - the Augeas error code
      - the ocaml-augeas error string
      - the Augeas error message
      - the human-readable explanation of the Augeas error, if available
      - a string with details of the Augeas error
   *)

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

val defnode : t -> string -> string -> string option -> int * bool
  (** [defnode t name expr value] defines [name] whose value is the
      result of evaluating [expr], which is a nodeset. *)

val defvar : t -> string -> string option -> int option
  (** [defvar t name expr] defines [name] whose value is the result
      of evaluating [expr], replacing the old value if existing.
      [None] as [expr] removes the variable [name]. *)

val get : t -> path -> value option
  (** [get t path] returns the value at [path], or [None] if there
      is no value. *)

val exists : t -> path -> bool
  (** [exists t path] returns true iff there is a value at [path]. *)

val insert : t -> ?before:bool -> path -> string -> unit
  (** [insert t ?before path label] inserts [label] as a sibling
      of [path].  By default it is inserted after [path], unless
      [~before:true] is specified. *)

val label : t -> path -> string option
  (** [label t path] gets the label of [path].

      Returns [Some value] when [path] matches only one node, and
      that has an associated label. *)

val rm : t -> path -> int
  (** [rm t path] removes all nodes matching [path].

      Returns the number of nodes removed (which may be 0). *)

val matches : t -> path -> path list
  (** [matches t path] returns a list of path expressions
      of all nodes matching [path]. *)

val mv : t -> path -> path -> unit
  (** [mv t src dest] moves a node. *)

val count_matches : t -> path -> int
  (** [count_matches t path] counts the number of nodes matching
      [path] but does not return them (see {!matches}). *)

val save : t -> unit
  (** [save t] saves all pending changes to disk. *)

val load : t -> unit
  (** [load t] loads files into the tree. *)

val set : t -> path -> value option -> unit
  (** [set t path] sets [value] as new value at [path]. *)

val setm : t -> path -> string option -> value option -> int
  (** [setm t base sub value] sets [value] as new value for all the
      nodes under [base] that match [sub] (or all, if [sub] is
      [None]).

      Returns the number of nodes modified. *)

val transform : t -> string -> string -> transform_mode -> unit
  (** [transform t lens file mode] adds or removes (depending on
      [mode]) the transformation of the specified [lens] for [file]. *)

val source : t -> path -> path option
  (** [source t path] returns the path to the node representing the
      file to which [path] belongs, or [None] if [path] does not
      represent any file. *)
