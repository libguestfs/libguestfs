(* virt-v2v
 * Copyright (C) 2009-2015 Red Hat Inc.
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

(** Functions for dealing with [curl]. *)

type curl_args = (string * string option) list

val run : curl_args -> string list
(** [run curl_args] runs the [curl] command.

    It actually uses the [curl --config] option to pass the arguments
    securely to curl through an external file.  Thus passwords etc are
    not exposed to other users on the same machine.

    The curl arguments are a list of key, value pairs corresponding
    to curl command line parameters, without leading dashes,
    eg. [("user", Some "user:password")].

    The result is the output of curl as a list of lines. *)

val print_curl_command : out_channel -> curl_args -> unit
(** Print the curl command line.  This elides any arguments that
    might contain passwords, so is useful for debugging. *)
