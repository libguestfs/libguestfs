(* Augeas OCaml bindings
 * Copyright (C) 2008 Red Hat Inc., Richard W.M. Jones
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
 * $Id: augeas.ml,v 1.2 2008/05/06 10:48:20 rjones Exp $
 *)

type t

type flag =
  | AugSaveBackup
  | AugSaveNewFile
  | AugTypeCheck
  | AugNoStdinc
  | AugSaveNoop
  | AugNoLoad
  | AugNoModlAutoload
  | AugEnableSpan
  | AugNoErrClose
  | AugTraceModuleLoading

type error_code =
  | AugErrInternal
  | AugErrPathX
  | AugErrNoMatch
  | AugErrMMatch
  | AugErrSyntax
  | AugErrNoLens
  | AugErrMXfm
  | AugErrNoSpan
  | AugErrMvDesc
  | AugErrCmdRun
  | AugErrBadArg
  | AugErrLabel
  | AugErrCpDesc
  | AugErrUnknown of int

type transform_mode =
  | Include
  | Exclude

exception Error of error_code * string * string * string * string

type path = string

type value = string

external create : string -> string option -> flag list -> t
  = "ocaml_augeas_create"
external close : t -> unit
  = "ocaml_augeas_close"
external defnode : t -> string -> string -> string option -> int * bool
  = "ocaml_augeas_defnode"
external defvar : t -> string -> string option -> int option
  = "ocaml_augeas_defvar"
external get : t -> path -> value option
  = "ocaml_augeas_get"
external exists : t -> path -> bool
  = "ocaml_augeas_exists"
external insert : t -> ?before:bool -> path -> string -> unit
  = "ocaml_augeas_insert"
external label : t -> path -> string option
  = "ocaml_augeas_label"
external rm : t -> path -> int
  = "ocaml_augeas_rm"
external matches : t -> path -> path list
  = "ocaml_augeas_match"
external count_matches : t -> path -> int
  = "ocaml_augeas_count_matches"
external save : t -> unit
  = "ocaml_augeas_save"
external load : t -> unit
  = "ocaml_augeas_load"
external mv : t -> path -> path -> unit
  = "ocaml_augeas_mv"
external set : t -> path -> value option -> unit
  = "ocaml_augeas_set"
external setm : t -> path -> string option -> value option -> int
  = "ocaml_augeas_setm"
external transform : t -> string -> string -> transform_mode -> unit
  = "ocaml_augeas_transform"
external source : t -> path -> path option
  = "ocaml_augeas_source"

let () =
  Callback.register_exception "Augeas.Error" (Error (AugErrInternal, "", "", "", ""))
