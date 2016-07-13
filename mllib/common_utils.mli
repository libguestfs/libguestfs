(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2010-2016 Red Hat Inc.
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

module Char : sig
    type t = char
    val chr : int -> char
    val code : char -> int
    val compare: t -> t -> int
    val escaped : char -> string
    val unsafe_chr : int -> char

    val lowercase_ascii : char -> char
    val uppercase_ascii : char -> char
end
(** Override the Char module from stdlib. *)

module String : sig
    type t = string
    val blit : string -> int -> string -> int -> int -> unit
    val compare: t -> t -> int
    val concat : string -> string list -> string
    val contains : string -> char -> bool
    val contains_from : string -> int -> char -> bool
    val copy : string -> string
    val create : int -> string
    val escaped : string -> string
    val fill : string -> int -> int -> char -> unit
    val get : string -> int -> char
    val index : string -> char -> int
    val index_from : string -> int -> char -> int
    val iter : (char -> unit) -> string -> unit
    val length : string -> int
    val make : int -> char -> string
    val rcontains_from : string -> int -> char -> bool
    val rindex : string -> char -> int
    val rindex_from : string -> int -> char -> int
    val set : string -> int -> char -> unit
    val sub : string -> int -> int -> string
    val unsafe_blit : string -> int -> string -> int -> int -> unit
    val unsafe_fill : string -> int -> int -> char -> unit
    val unsafe_get : string -> int -> char
    val unsafe_set : string -> int -> char -> unit

    val lowercase_ascii : string -> string
    val uppercase_ascii : string -> string

    val is_prefix : string -> string -> bool
    (** [is_prefix str prefix] returns true if [prefix] is a prefix of [str]. *)
    val is_suffix : string -> string -> bool
    (** [is_suffix str suffix] returns true if [suffix] is a suffix of [str]. *)
    val find : string -> string -> int
    (** [find str sub] searches for [sub] as a substring of [str].  If
        found it returns the index.  If not found, it returns [-1]. *)
    val replace : string -> string -> string -> string
    (** [replace str s1 s2] replaces all instances of [s1] appearing in
        [str] with [s2]. *)
    val nsplit : string -> string -> string list
    (** [nsplit sep str] splits [str] into multiple strings at each
        separator [sep]. *)
    val split : string -> string -> string * string
    (** [split sep str] splits [str] at the first occurrence of the
        separator [sep], returning the part before and the part after.
        If separator is not found, return the whole string and an
        empty string. *)
    val lines_split : string -> string list
    (** [lines_split str] splits [str] into lines, keeping continuation
        characters (i.e. [\] at the end of lines) into account. *)
    val random8 : unit -> string
    (** Return a string of 8 random printable characters. *)
end
(** Override the String module from stdlib. *)

val ( // ) : string -> string -> string
(** Concatenate directory and filename. *)

val ( +^ ) : int64 -> int64 -> int64
val ( -^ ) : int64 -> int64 -> int64
val ( *^ ) : int64 -> int64 -> int64
val ( /^ ) : int64 -> int64 -> int64
val ( &^ ) : int64 -> int64 -> int64
val ( ~^ ) : int64 -> int64
(** Various int64 operators. *)

val roundup64 : int64 -> int64 -> int64
(** [roundup64 i a] returns [i] rounded up to the next multiple of [a]. *)
val div_roundup64 : int64 -> int64 -> int64
(** [div_roundup64 i a] returns [i] rounded up to the next multiple of [a],
    with the result divided by [a]. *)
val int_of_le32 : string -> int64
(** Unpack a 4 byte string as a little endian 32 bit integer. *)
val le32_of_int : int64 -> string
(** Pack a 32 bit integer a 4 byte string stored little endian. *)

val isdigit : char -> bool
(** Return true if the character is a digit [[0-9]]. *)
val isxdigit : char -> bool
(** Return true if the character is a hex digit [[0-9a-fA-F]]. *)

val wrap : ?chan:out_channel -> ?indent:int -> string -> unit
(** Wrap text. *)

val output_spaces : out_channel -> int -> unit
(** Write [n] spaces to [out_channel]. *)

val dropwhile : ('a -> bool) -> 'a list -> 'a list
(** [dropwhile f xs] drops leading elements from [xs] until
    [f] returns false. *)
val takewhile : ('a -> bool) -> 'a list -> 'a list
(** [takewhile f xs] takes leading elements from [xs] until
    [f] returns false.

    For any list [xs] and function [f],
    [xs = takewhile f xs @ dropwhile f xs] *)
val filter_map : ('a -> 'b option) -> 'a list -> 'b list
(** [filter_map f xs] applies [f] to each element of [xs].  If
    [f x] returns [Some y] then [y] is added to the returned list. *)
val iteri : (int -> 'a -> 'b) -> 'a list -> unit
(** [iteri f xs] calls [f i x] for each element, with [i] counting from [0]. *)
val mapi : (int -> 'a -> 'b) -> 'a list -> 'b list
(** [mapi f xs] calls [f i x] for each element, with [i] counting from [0],
    forming the return values from [f] into another list. *)

val combine3 : 'a list -> 'b list -> 'c list -> ('a * 'b * 'c) list
(** Like {!List.combine} but for triples.  All lists must be the same length. *)

val assoc : ?cmp:('a -> 'a -> int) -> default:'b -> 'a -> ('a * 'b) list -> 'b
(** Like {!List.assoc} but with a user-defined comparison function, and
    instead of raising [Not_found], it returns the [~default] value. *)

val push_back : 'a list ref -> 'a -> unit
val push_front : 'a -> 'a list ref -> unit
val pop_back : 'a list ref -> 'a
val pop_front : 'a list ref -> 'a
(** Imperative list manipulation functions, similar to C++ STL
    functions with the same names.  (Although the names are similar,
    the computational complexity of the functions is quite different.)

    These operate on list references, and each function modifies the
    list reference that is passed to it.

    [push_back xsp x] appends the element [x] to the end of the list
    [xsp].  This function is not tail-recursive.

    [push_front x xsp] prepends the element [x] to the head of the
    list [xsp].  (The arguments are reversed compared to the same Perl
    function, but OCaml is type safe so that's OK.)

    [pop_back xsp] removes the last element of the list [xsp] and
    returns it.  The list is modified to become the list minus the
    final element.  If a zero-length list is passed in, this raises
    [Failure "pop_back"].  This function is not tail-recursive.

    [pop_front xsp] removes the head element of the list [xsp] and
    returns it.  The list is modified to become the tail of the list.
    If a zero-length list is passed in, this raises [Failure
    "pop_front"]. *)

val append : 'a list ref -> 'a list -> unit
val prepend : 'a list -> 'a list ref -> unit
(** More imperative list manipulation functions.

    [append] is like {!push_back} above, except it appends a list to
    the list reference.  This function is not tail-recursive.

    [prepend] is like {!push_front} above, except it prepends a list
    to the list reference. *)

val may : ('a -> unit) -> 'a option -> unit
(** [may f (Some x)] runs [f x].  [may f None] does nothing. *)

type ('a, 'b) maybe = Either of 'a | Or of 'b
(** Like the Haskell [Either] type. *)

val protect : f:(unit -> 'a) -> finally:(unit -> unit) -> 'a
(** Execute [~f] and afterwards execute [~finally].

    If [~f] throws an exception then [~finally] is run and the
    original exception from [~f] is re-raised.

    If [~finally] throws an exception, then the original exception
    is lost. (NB: Janestreet core {!Exn.protectx}, on which this
    function is modelled, doesn't throw away the exception in this
    case, but requires a lot more work by the caller.  Perhaps we
    will change this in future.) *)

val prog : string
(** The program name (derived from {!Sys.executable_name}). *)

val set_quiet : unit -> unit
val quiet : unit -> bool
val set_trace : unit -> unit
val trace : unit -> bool
val set_verbose : unit -> unit
val verbose : unit -> bool
(** Stores the quiet ([--quiet]), trace ([-x]) and verbose ([-v]) flags
    in global variables. *)

val message : ('a, unit, string, unit) format4 -> 'a
(** Timestamped progress messages.  Used for ordinary messages when
    not [--quiet]. *)

val error : ?exit_code:int -> ('a, unit, string, 'b) format4 -> 'a
(** Standard error function. *)

val warning : ('a, unit, string, unit) format4 -> 'a
(** Standard warning function. *)

val info : ('a, unit, string, unit) format4 -> 'a
(** Standard info function.  Note: Use full sentences for this. *)

val debug : ('a, unit, string, unit) format4 -> 'a
(** Standard debug function.

    The message is only emitted if the verbose ([-v]) flag was set on
    the command line.  As with libguestfs debugging messages, it is
    sent to [stderr]. *)

val open_guestfs : ?identifier:string -> unit -> Guestfs.guestfs
(** Common function to create a new Guestfs handle, with common options
    (e.g. debug, tracing) already set.

    The optional [?identifier] parameter sets the handle identifier. *)

val run_main_and_handle_errors : (unit -> unit) -> unit
(** Common function for handling pretty-printing exceptions. *)

val generated_by : string
(** The string ["generated by <prog> <version>"]. *)

val read_whole_file : string -> string
(** Read in the whole file as a string. *)

val parse_size : string -> int64
(** Parse a size field, eg. [10G] *)

val parse_resize : int64 -> string -> int64
(** Parse a size field, eg. [10G], [+20%] etc.  Used particularly by
    [virt-resize --resize] and [--resize-force] options. *)

val human_size : int64 -> string
(** Converts a size in bytes to a human-readable string. *)

val skip_dashes : string -> string
(** Skip any leading '-' characters when comparing command line args. *)

val compare_command_line_args : string -> string -> int
(** Compare command line arguments for equality, ignoring any leading [-]s. *)

val set_standard_options : (Arg.key * Arg.spec * Arg.doc) list -> (Arg.key * Arg.spec * Arg.doc) list
(** Adds the standard libguestfs command line options to the specified ones,
    sorting them, and setting [long_options] to them.

    Returns the resulting options. *)

val compare_version : string -> string -> int
(** Compare two version strings. *)

val compare_lvm2_uuids : string -> string -> int
(** Compare two LVM2 UUIDs, ignoring '-' characters. *)

val stringify_args : string list -> string
(** Create a "pretty-print" representation of a program invocation
    (i.e. executable and its arguments). *)

val external_command : ?echo_cmd:bool -> string -> string list
(** Run an external command, slurp up the output as a list of lines.

    [echo_cmd] specifies whether to output the full command on verbose
    mode, and it's on by default. *)

val run_command : ?echo_cmd:bool -> string list -> int
(** Run an external command without using a shell, and return its exit code.

    [echo_cmd] specifies whether output the full command on verbose
    mode, and it's on by default. *)

val shell_command : ?echo_cmd:bool -> string -> int
(** Run an external shell command, and return its exit code.

    [echo_cmd] specifies whether to output the full command on verbose
    mode, and it's on by default. *)

val uuidgen : unit -> string
(** Run uuidgen to return a random UUID. *)

val unlink_on_exit : string -> unit
(** Unlink a temporary file on exit. *)

val rmdir_on_exit : string -> unit
(** Remove a temporary directory on exit (using [rm -rf]). *)

val rm_rf_only_files : Guestfs.guestfs -> ?filter:(string -> bool) -> string -> unit
(** Using the libguestfs API, recursively remove only files from the
    given directory.  Useful for cleaning [/var/cache] etc in sysprep
    without removing the actual directory structure.  Also if [dir] is
    not a directory or doesn't exist, ignore it.

    The optional [filter] is used to filter out files which will be
    removed: files returning true are not removed.

    XXX Could be faster with a specific API for doing this. *)

val truncate_recursive : Guestfs.guestfs -> string -> unit
(** Using the libguestfs API, recurse into the given directory and
    truncate all files found to zero size. *)

val debug_augeas_errors : Guestfs.guestfs -> unit
(** In verbose mode, any Augeas errors which happened most recently
    on the handle and printed on standard error.  You should usually
    call this just after either [g#aug_init] or [g#aug_load].

    Note this doesn't call {!error} if there were any errors on the
    handle.  It is just for debugging.  It is expected that a
    subsequent Augeas command will fail, eg. when trying to match
    an Augeas path which is expected to exist but does not exist
    because of a parsing error.  In that case turning on debugging
    will reveal the parse error.

    If not in verbose mode, this does nothing. *)

val detect_file_type : string -> [`GZip | `Tar | `XZ | `Zip | `Unknown]
(** Detect type of a file (for a very limited range of file types). *)

val is_block_device : string -> bool
val is_char_device : string -> bool
val is_directory : string -> bool
(** These don't throw exceptions, unlike the [Sys] functions. *)

val is_partition : string -> bool
(** Return true if the host device [dev] is a partition.  If it's
    anything else, or missing, returns false. *)

val absolute_path : string -> string
(** Convert any path to an absolute path. *)

val qemu_input_filename : string -> string
(** Sanitizes a filename for passing it safely to qemu/qemu-img. *)

val mkdir_p : string -> int -> unit
(** Creates a directory, and its parents if missing. *)

val normalize_arch : string -> string
(** Normalize the architecture name, i.e. maps it into a defined
    identifier for it -- e.g. i386, i486, i586, and i686 are
    normalized as i386. *)

val guest_arch_compatible : string -> bool
(** Are guest arch and host_cpu compatible, in terms of being able
    to run commands in the libguestfs appliance? *)

val last_part_of : string -> char -> string option
(** Return the last part of a string, after the specified separator. *)

val read_first_line_from_file : string -> string
(** Read only the first line (i.e. until the first newline character)
    of a file. *)

val is_regular_file : string -> bool
(** Checks whether the file is a regular file. *)
