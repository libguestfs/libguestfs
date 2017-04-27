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

(** OCaml bindings for the [common/qemuopts] library. *)

type t

val create : unit -> t
(** Create an empty qemu command line.

    In case of error, all these functions raise [Unix_error]. *)

val set_binary : t -> string -> unit
(** Set the qemu binary name. *)

val set_binary_by_arch : t -> string option -> unit
(** Set the qemu binary to [qemu-system-<arch>].  If [arch] is [None],
    then this picks the right KVM binary for the current host
    architecture. *)

val flag : t -> string -> unit
(** [flag t "-foo"] adds a parameter to the command line with no argument. *)

val arg : t -> string -> string -> unit
(** [arg t "-m" "1024"] adds [-m 1024] to the command line.

    The value will shell-quoted if required, so you do not need to quote
    the string.  However if the value is a comma-separated list
    (eg. [-drive file=foo,if=ide]) then do {b not} use this function, call
    {!arg_list} instead. *)

val arg_noquote : t -> string -> string -> unit
(** Like {!arg} except no quoting is done on the value. *)

val arg_list : t -> string -> string list -> unit
(** [arg_list t "-drive" ["file=foo"; "if=ide"]] adds a comma-separated
    list of parameters to the command line [-drive file=foo,if=ide].

    This does both qemu comma-quoting and shell-quoting as required. *)

val to_script : t -> string -> unit
(** [to_script t "./file.sh"] writes the resulting command line to
    a file.  The file begins with [#!/bin/sh] and is chmod 0755. *)

val to_chan : t -> out_channel -> unit
(** [to_chan t chan] appends the resulting command line to
    an output channel.  The caller must write [!#/bin/sh] and chmod 0755
    the output file, if needed. *)
