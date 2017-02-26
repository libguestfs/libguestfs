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

(** Generate a qemu command line, dealing with quoting. *)

type t

val create : ?arch:string -> unit -> t
(** Create an empty qemu command.  If the optional [?arch] parameter
    is supplied then the command will be [qemu-system-<arch>],
    otherwise it will be [qemu-system-x86_64]. *)

val flag : t -> string -> unit
(** [flag t "-foo"] adds a parameter to the command line with no argument. *)

val arg : t -> string -> string -> unit
(** [arg t "-m" "1024"] adds [-m 1024] to the command line.

    The value will shell-quoted if required, so you do not need to quote
    the string.  However if the value is a comma-separated list
    (eg. [-drive file=foo,if=ide]) then do {b not} use this function, call
    {!commas} instead. *)

val arg_noquote : t -> string -> string -> unit
(** Like {!arg} except no quoting is done on the value. *)

val commas : t -> string -> string list -> unit
(** [commas t "-drive" ["file=foo"; "if=ide"]] adds a comma-separated
    list of parameters to the command line [-drive file=foo,if=ide].

    This does both qemu comma-quoting and shell-quoting as required. *)

val to_script : t -> string -> unit
(** [to_script t "./file.sh"] writes the resulting command line to
    a file.  The file begins with [#!/bin/sh] and is chmod 0755. *)

val to_chan : t -> out_channel -> unit
(** [to_chan t chan] appends the resulting command line to
    an output channel.  The caller must write [!#/bin/sh] and chmod 0755
    the output file, if needed. *)
