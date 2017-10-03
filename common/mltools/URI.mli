(* virt-resize - interface to -a URI option parsing mini library
 * Copyright (C) 2013 Red Hat Inc.
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

(** Interface to [-a] URI option parsing mini library. *)

type uri = {
  path : string;                        (** path *)
  protocol : string;                    (** protocol, eg. [file], [nbd] *)
  server : string array option;         (** list of servers *)
  username : string option;             (** username *)
  password : string option;             (** password *)
}

exception Parse_failed

val parse_uri : string -> uri
(** See [fish/uri.h].

    This can raise {!Parse_failed}.

    Unfortunately we cannot be specific about the actual error
    (although [fish/uri.c] should print something).  XXX We should
    be able to fetch and throw a real exception with the error. *)
