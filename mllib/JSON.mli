(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(** Simple JSON generator. *)

type field = string * json_t    (** ["field": "value"] *)
and json_t =                    (** JSON value. *)
  | String of string            (** string value, eg. ["string"] *)
  | Int of int                  (** int value, eg. [99] *)
  | Int64 of int64              (** int64 value, eg. [99] *)
  | Bool of bool                (** boolean value, [true] or [false] *)
  | List of json_t list         (** array value, eg. [[1,2,3]] *)
  | Dict of field list          (** object, eg. [{ "a": 1, "b": "c" }] *)
and doc = field list            (** JSON document. *)

type output_format =
  | Compact                     (** Output on a single line (if possible). *)
  | Indented                    (** Output a multi-line document. *)

val string_of_doc : ?fmt:output_format -> doc -> string
  (** Serialize {!doc} object as a string. *)
