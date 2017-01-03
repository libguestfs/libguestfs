(* interface to -a URI option parsing mini library
 * Copyright (C) 2013-2018 Red Hat Inc.
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

type uri = {
  path : string;
  protocol : string;
  server : string array option;
  username : string option;
  password : string option;
}

exception Parse_failed

external parse_uri : string -> uri = "guestfs_int_mllib_parse_uri"

let () =
  Callback.register_exception "URI.Parse_failed" Parse_failed
