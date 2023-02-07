(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Types

(* Deprecated hivex APIs. *)

let daemon_functions = [
  { defaults with
    name = "hivex_value_utf8"; added = (1, 19, 35);
    style = RString (RPlainString, "databuf"), [Int64 "valueh"], [];
    optional = Some "hivex";
    deprecated_by = Replaced_by "hivex_value_string";
    shortdesc = "return the data field as a UTF-8 string";
    longdesc = "\
This calls C<guestfs_hivex_value_value> (which returns the
data field from a hivex value tuple).  It then assumes that
the field is a UTF-16LE string and converts the result to
UTF-8 (or if this is not possible, it returns an error).

This is useful for reading strings out of the Windows registry.
However it is not foolproof because the registry is not
strongly-typed and fields can contain arbitrary or unexpected
data." };

]
