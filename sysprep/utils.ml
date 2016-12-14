(* virt-sysprep
 * Copyright (C) 2016 Red Hat Inc.
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

(* Utility functions. *)

open Printf

let rec pod_of_list ?(style = `Dot) xs =
  match style with
  | `Verbatim -> String.concat "\n" (List.map ((^) " ") xs)
  | `Star -> _pod_of_list "*" xs
  | `Dash -> _pod_of_list "-" xs
  | `Dot -> _pod_of_list "·" xs

and _pod_of_list delim xs =
  "=over 4\n\n" ^
  String.concat "" (List.map (sprintf "=item %s\n\n%s\n\n" delim) xs) ^
  "=back"
