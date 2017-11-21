(* virt-builder
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

val get_index : downloader:Downloader.t -> sigchecker:Sigchecker.t -> ?template:bool -> Sources.source -> Index.index
(** [get_index download sigchecker template source] will parse the source
    index file into an index entry list. If the template flag is set to
    true, the parser will be less picky about missing values. *)

val write_entry : out_channel -> (string * Index.entry) -> unit
(** [write_entry chan entry] writes the index entry to the chan output
    stream.*)
