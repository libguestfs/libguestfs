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

(** This module is a wrapper around curl, plus local caching. *)

type uri = string
type filename = string

type t
(** The abstract data type. *)

val create : curl:string -> cache:Cache.t option -> t
(** Create the abstract type. *)

val download : t -> ?template:(string*string*Utils.revision) -> ?progress_bar:bool -> ?proxy:Curl.proxy -> uri -> (filename * bool)
(** Download the URI, returning the downloaded filename and a
    temporary file flag.  The temporary file flag is [true] iff
    the downloaded file is temporary and should be deleted by the
    caller (otherwise it's in the cache and you shouldn't delete it).

    For templates, you must supply [~template:(name, arch, revision)].
    This causes the cache to be used (if possible).  Name, arch(itecture)
    and revision are used for cache control (see the man page for details).

    If [~progress_bar:true] then display a progress bar if the file
    doesn't come from the cache.  In verbose mode, progress messages
    are always displayed.

    [proxy] specifies the type of proxy to be used in the transfer,
    if possible. *)
