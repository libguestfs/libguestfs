(* Binding for fnmatch.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(** Binding for the fnmatch(3) function in glibc or gnulib. *)

type flag =
| FNM_NOESCAPE
| FNM_PATHNAME
| FNM_PERIOD
| FNM_FILE_NAME
| FNM_LEADING_DIR
| FNM_CASEFOLD
(** Flags passed to the fnmatch function. *)

val fnmatch : string -> string -> flag list -> bool
(** The [fnmatch pattern filename flags] function checks whether
    the [filename] argument matches the wildcard in the [pattern]
    argument.  The [flags] is a list of flags.  Consult the
    fnmatch(3) man page for details of the flags.

    The [filename] might be a filename element or a full path
    (depending on the pattern and flags). *)
