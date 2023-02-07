(* guestfs-inspection
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(** This is a generic module for running functions in a chroot directory.

    It is normally used where we want to run a function on files mounted
    under [Sysroot.sysroot ()] (normally [/sysroot]), ie. in the
    libguestfs namespace.

    The function runs in a forked subprocess, ensuring that the main
    daemon process does not chroot so everything is restored properly
    afterwards.  (Note this is different from how the legacy
    C [CHROOT_IN] and [CHROOT_OUT] macros work).

    Basic usage is:

{v
  let chroot = Chroot.create ~name:(sprintf "lstat: %s" path) () in
  let statbuf = Chroot.f chroot lstat path in
  ...
v}

    After this runs, [statbuf] will contain the results of [lstat]
    on [Sysroot.sysroot () // path].  (Any exception thrown by [lstat]
    will be rethrown in the main process.)

    This module handles passing the parameter, forking, running the
    function and marshalling the result or any exceptions. *)

type t

val create : ?name:string -> ?chroot:string -> unit -> t
(** Create a chroot handle.

    [?name] is an optional name used in debugging and error messages.

    [?chroot] is the optional chroot directory.  This parameter
    defaults to [Sysroot.sysroot ()]. *)

val f : t -> ('a -> 'b) -> 'a -> 'b
(** Run a function in the chroot, returning the result or re-raising
    any exception thrown. *)
