(* guestfs-inspection
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

val prog_exists : string -> bool
(** Return true iff the program is found on [$PATH]. *)

val udev_settle : ?filename:string -> unit -> unit
(**
 * LVM and other commands aren't synchronous, especially when udev is
 * involved.  eg. You can create or remove some device, but the
 * [/dev] device node won't appear until some time later.  This means
 * that you get an error if you run one command followed by another.
 *
 * Use [udevadm settle] after certain commands, but don't be too
 * fussed if it fails.
 *
 * The optional [?filename] passes the [udevadm settle -E filename]
 * option, which means udevadm stops waiting as soon as the named
 * file is created (or if it exists at the start).
 *)

val is_root_device : string -> bool
(** Return true if this is the root (appliance) device. *)

val is_root_device_stat : Unix.stats -> bool
(** As for {!is_root_device} but operates on a statbuf instead of
    a device name. *)

val proc_unmangle_path : string -> string
(** Reverse kernel path escaping done in fs/seq_file.c:mangle_path.
    This is inconsistently used for /proc fields. *)

val command : ?fold_stdout_on_stderr:bool -> string -> string list -> string
(** Run an external command without using the shell, and collect
    stdout and stderr separately.  Returns stdout if the command
    runs successfully.

    On failure of the command, this throws an exception containing
    the stderr from the command.

    [?fold_stdout_on_stderr] (default: false)

    For broken external commands that send error messages to stdout
    (hello, parted) but that don't have any useful stdout information,
    use this flag to capture the error messages in the [stderr]
    buffer.  Nothing will be captured on stdout if you use this flag. *)

val commandr : ?fold_stdout_on_stderr:bool -> string -> string list -> (int * string * string)
(** Run an external command without using the shell, and collect
    stdout and stderr separately.

    Returns [status, stdout, stderr].  As with the C function in
    [daemon/command.c], this strips the trailing [\n] from stderr,
    but {b not} from stdout. *)

val is_small_file : string -> bool
(** Return true if the path is a small regular file. *)
