(* Binding for fnmatch.
 * Copyright (C) 2009-2016 Red Hat Inc.
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

(* NB: These flags must appear in the same order as fnmatch-c.c *)
type flag =
| FNM_NOESCAPE
| FNM_PATHNAME
| FNM_PERIOD
| FNM_FILE_NAME
| FNM_LEADING_DIR
| FNM_CASEFOLD

external fnmatch : string -> string -> flag list -> bool =
  "guestfs_int_mllib_fnmatch"
