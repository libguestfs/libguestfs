(* virt-customize
 * Copyright (C) 2015 Red Hat Inc.
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

open Common_gettext.Gettext
open Common_utils

type sm_credentials = {
  sm_username : string;
  sm_password : string;
}

type sm_pool =
| PoolAuto
| PoolId of string

let rec parse_credentials_selector arg =
  parse_credentials_selector_list arg (string_nsplit ":" arg)

and parse_credentials_selector_list orig_arg = function
  | [ username; "password"; password ] ->
    { sm_username = username; sm_password = password }
  | [ username; "file"; filename ] ->
    { sm_username = username; sm_password = read_first_line_from_file filename }
  | _ ->
    error (f_"invalid sm-credentials selector '%s'; see the man page") orig_arg

let rec parse_pool_selector arg =
  parse_pool_selector_list arg (string_nsplit ":" arg)

and parse_pool_selector_list orig_arg = function
  | [ "auto" ] ->
    PoolAuto
  | [ "pool"; pool ] ->
    PoolId pool
  | [ "file"; filename ] ->
    PoolId (read_first_line_from_file filename)
  | _ ->
    error (f_"invalid sm-attach selector '%s'; see the man page") orig_arg
