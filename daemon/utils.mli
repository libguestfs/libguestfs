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

val is_device_parameter : string -> bool
(** Use this function to tell the difference between a device
    or path for [Dev_or_Path] parameters. *)

val split_device_partition : string -> string * int
(** Split a device name like [/dev/sda1] into a device name and
    partition number, eg. ["sda", 1].

    The [/dev/] prefix is skipped and removed, if present.

    If the partition number is not present (a whole device), 0 is returned.

    This function splits [/dev/md0p1] to ["md0", 1]. *)

val sort_device_names : string list -> string list
(** Sort device names correctly so that /dev/sdaa appears after /dev/sdz.
    This also deals with partition numbers, and works whether or not
    [/dev/] is present. *)

val has_bogus_mbr : string -> bool
(** Check whether the first sector of the device contains a bogus MBR partition
    table; namely one where the first partition table entry describes a
    partition that starts at absolute sector 0, thereby overlapping the
    partition table itself.

    dosfstools-4.2+ creates bogus partition tables like this by default when
    formatting non-removable, non-partitioned block devices. Refer to
    RHBZ#1931821. *)

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

val read_small_file : string -> string list option
(** If [filename] is a small file (see {!is_small_file}) then read it
    split into lines.  Otherwise emits a debug message and returns
    [None]. *)

val unix_canonical_path : string -> string
(** Canonicalize a Unix path, so "///usr//local//" -> "/usr/local"

    The path is modified in place because the result is always
    the same length or shorter than the argument passed. *)

val simple_unquote : string -> string
(** Unquote the string, by removing a pair of single- or double-quotes
    at the beginning and the end of the string.

    No other handling is done, unlike what {!shell_unquote} does. *)

val parse_key_value_strings : ?unquote:(string -> string) -> string list -> (string * string) list
(** Split the lines by the [=] separator; if [unquote] is specified,
    it is applied on the values as unquote function.  Empty lines,
    or that start with a comment character [#], are ignored. *)

(**/**)
val get_verbose_flag : unit -> bool
