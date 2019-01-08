(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

type t

type args = (string * string option) list

type proxy =
  | UnsetProxy            (** The proxy is forced off. *)
  | SystemProxy           (** Use the system settings. *)
  | ForcedProxy of string (** The proxy is forced to the specified URL. *)

val create : ?curl:string -> ?proxy:proxy -> ?tmpdir:string -> args -> t
(** Create a curl command handle.

    The curl arguments are a list of key, value pairs corresponding
    to curl command line parameters, without leading dashes,
    eg. [("user", Some "user:password")].

    The optional [?curl] parameter controls the name of the curl
    binary (default ["curl"]).

    The optional [?proxy] parameter adds extra arguments to
    control the proxy.

    Note that some extra arguments are added implicitly:

    - [--max-redirs 5] Only follow 3XX redirects up to 5 times.
    - [--globoff] Disable URL globbing.

    Note this does {b not} enable redirects.  If you want to follow
    redirects you have to add the ["location"] parameter yourself. *)

val run : t -> string list
(** [run t] runs previously constructed the curl command.

    It actually uses the [curl --config] option to pass the arguments
    securely to curl through an external file.  Thus passwords etc are
    not exposed to other users on the same machine.

    The result is the output of curl as a list of lines. *)

val to_string : t -> string
(** Convert the curl command line to a string.

    This elides any arguments that might contain passwords, so is
    useful for debugging. *)

val print : out_channel -> t -> unit
(** Print the curl command line.

    This elides any arguments that might contain passwords, so is
    useful for debugging. *)
