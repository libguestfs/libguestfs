(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** Functions for making files and directories as another user.

    [-o rhev] output mode has to write files as UID:GID 36:36,
    otherwise RHEV cannot read them.  Because the files are located on
    NFS (and hence might be root-squashed) we also cannot chown the
    files.  We cannot setuid the whole process to 36:36 because it
    needs to do other root things like mounting and unmounting the NFS
    volume.

    The solution to this craziness is to fork a subprocess every time
    we need to create a file, setuid in the subprocess, and write the
    file.  The subprocess then exits, leaving the main process still
    running as root.

    This mini-library encapsulates this tomfoolery into something that
    is slightly more sane to use.

    NB. We are {b not} dropping permissions for security reasons.
    This file has nothing to do with security. *)

type t
(** Abstract handle. *)

val create : ?uid:int -> ?gid:int -> unit -> t
(** Create handle.  The optional [?uid] and [?gid] parameters are the
    user/group to run as.  If omitted, then we don't change user
    and/or group (but we still do the forking anyway). *)

val mkdir : t -> string -> int -> unit
(** [mkdir t path perm] creates the directory [path] with mode [perm]. *)

val rmdir : t -> string -> unit
(** [rmdir t path] removes the directory [path]. *)

val make_file : t -> string -> string -> unit
(** [make_file t path content] creates the file [path] with content
    [content].  The current umask controls file permissions. *)

val output : t -> string -> (out_channel -> unit) -> unit
(** [output t path f] creates the file [path] with content from
    function [f].  The current umask controls file permissions. *)

val unlink : t -> string -> unit
(** [unlink t path] deletes the file [path]. *)

val func : t -> (unit -> unit) -> unit
(** [func t f] runs the arbitrary function [f]. *)

val command : t -> string -> unit
(** [command t cmd] runs [cmd] as the alternate user/group after
    forking. *)
