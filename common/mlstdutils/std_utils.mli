(* Common utilities for OCaml tools in libguestfs.
 * Copyright (C) 2010-2017 Red Hat Inc.
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

    val isspace : char -> bool
    (** Return true if char is a whitespace character. *)
    val isdigit : char -> bool
    (** Return true if the character is a digit [[0-9]]. *)
    val isxdigit : char -> bool
    (** Return true if the character is a hex digit [[0-9a-fA-F]]. *)
    val isalpha : char -> bool
    (** Return true if the character is a US ASCII 7 bit alphabetic. *)
    val isalnum : char -> bool
    (** Return true if the character is a US ASCII 7 bit alphanumeric. *)

    val hexdigit : char -> int
    (** Return the value of a hex digit.  If the char is not in
        the set [[0-9a-fA-F]] then this returns [-1]. *)

    val mem : char -> string -> bool
    (** [mem c str] returns true if the byte [c] is contained in [str].

        This is actually the same as {!String.contains} with the
        parameters reversed. *)
end
(** Override the Char module from stdlib. *)

module String : sig
    type t = string
    val compare: t -> t -> int
    val concat : string -> string list -> string
    val contains : string -> char -> bool
    val contains_from : string -> int -> char -> bool
    val copy : string -> string
    val escaped : string -> string
    val get : string -> int -> char
    val index : string -> char -> int
    val index_from : string -> int -> char -> int
    val iter : (char -> unit) -> string -> unit
    val iteri : (int -> char -> unit) -> string -> unit
    val map : (char -> char) -> string -> string
    val length : string -> int
    val make : int -> char -> string
    val rcontains_from : string -> int -> char -> bool
    val rindex : string -> char -> int
    val rindex_from : string -> int -> char -> int
    val sub : string -> int -> int -> string
    val unsafe_get : string -> int -> char

    val lowercase_ascii : string -> string
    val uppercase_ascii : string -> string
    val capitalize_ascii : string -> string

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
    val replace_char : string -> char -> char -> string
    (** Replace character in string. *)
    val split : string -> string -> string * string
    (** [split sep str] splits [str] at the first occurrence of the
        separator [sep], returning the part before and the part after.
        If separator is not found, return the whole string and an
        empty string. *)
    val nsplit : ?max:int -> string -> string -> string list
    (** [nsplit ?max sep str] splits [str] into multiple strings at each
        separator [sep].

        As with the Perl split function, you can give an optional
        [?max] parameter to limit the number of strings returned.  The
        final element of the list will contain the remainder of the
        input string. *)
    val lines_split : string -> string list
    (** [lines_split str] splits [str] into lines, keeping continuation
        characters (i.e. [\] at the end of lines) into account. *)
    val random8 : unit -> string
    (** Return a string of 8 random printable characters. *)
    val triml : ?test:(char -> bool) -> string -> string
    (** Trim left. *)
    val trimr : ?test:(char -> bool) -> string -> string
    (** Trim right. *)
    val trim : ?test:(char -> bool) -> string -> string
    (** Trim left and right. *)
    val chomp : string -> string
    (** If the string ends with [\n], remove it. *)
    val count_chars : char -> string -> int
    (** Count number of times the character occurs in string. *)
    val explode : string -> char list
    (** Explode a string into a list of characters. *)
    val map_chars : (char -> 'a) -> string -> 'a list
    (** Explode string, then map function over the characters. *)
    val spaces : int -> string
    (** [spaces n] creates a string of n spaces. *)
    val span : string -> string -> int
    val cspan : string -> string -> int
    (** [span str accept] returns the length in bytes of the initial
        segment of [str] which contains only bytes in [accept].

        [cspan str reject] returns the length in bytes of the initial
        segment of [str] which contains only bytes {!i not} in [reject].

        These work exactly like the C functions [strspn] and [strcspn]. *)
end
(** Override the String module from stdlib. *)

module List : sig
    val length : 'a list -> int
    val hd : 'a list -> 'a
    val tl : 'a list -> 'a list
    val nth : 'a list -> int -> 'a
    val rev : 'a list -> 'a list
    val append : 'a list -> 'a list -> 'a list
    val rev_append : 'a list -> 'a list -> 'a list
    val concat : 'a list list -> 'a list
    val flatten : 'a list list -> 'a list
    val iter : ('a -> unit) -> 'a list -> unit
    val iteri : (int -> 'a -> unit) -> 'a list -> unit
    val map : ('a -> 'b) -> 'a list -> 'b list
    val mapi : (int -> 'a -> 'b) -> 'a list -> 'b list
    val rev_map : ('a -> 'b) -> 'a list -> 'b list
    val fold_left : ('a -> 'b -> 'a) -> 'a -> 'b list -> 'a
    val fold_right : ('a -> 'b -> 'b) -> 'a list -> 'b -> 'b
    val iter2 : ('a -> 'b -> unit) -> 'a list -> 'b list -> unit
    val map2 : ('a -> 'b -> 'c) -> 'a list -> 'b list -> 'c list
    val rev_map2 : ('a -> 'b -> 'c) -> 'a list -> 'b list -> 'c list
    val fold_left2 : ('a -> 'b -> 'c -> 'a) -> 'a -> 'b list -> 'c list -> 'a
    val fold_right2 : ('a -> 'b -> 'c -> 'c) -> 'a list -> 'b list -> 'c -> 'c
    val for_all : ('a -> bool) -> 'a list -> bool
    val exists : ('a -> bool) -> 'a list -> bool
    val for_all2 : ('a -> 'b -> bool) -> 'a list -> 'b list -> bool
    val exists2 : ('a -> 'b -> bool) -> 'a list -> 'b list -> bool
    val mem : 'a -> 'a list -> bool
    val memq : 'a -> 'a list -> bool
    val find : ('a -> bool) -> 'a list -> 'a
    val filter : ('a -> bool) -> 'a list -> 'a list
    val find_all : ('a -> bool) -> 'a list -> 'a list
    val partition : ('a -> bool) -> 'a list -> 'a list * 'a list
    val assoc : 'a -> ('a * 'b) list -> 'b
    val assq : 'a -> ('a * 'b) list -> 'b
    val mem_assoc : 'a -> ('a * 'b) list -> bool
    val mem_assq : 'a -> ('a * 'b) list -> bool
    val remove_assoc : 'a -> ('a * 'b) list -> ('a * 'b) list
    val remove_assq : 'a -> ('a * 'b) list -> ('a * 'b) list
    val split : ('a * 'b) list -> 'a list * 'b list
    val combine : 'a list -> 'b list -> ('a * 'b) list
    val sort : ('a -> 'a -> int) -> 'a list -> 'a list
    val stable_sort : ('a -> 'a -> int) -> 'a list -> 'a list
    val fast_sort : ('a -> 'a -> int) -> 'a list -> 'a list
    val merge : ('a -> 'a -> int) -> 'a list -> 'a list -> 'a list

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
    val find_map : ('a -> 'b option) -> 'a list -> 'b
    (** [find_map f xs] applies [f] to each element of [xs] until
        [f x] returns [Some y].  It returns [y].  If we exhaust the
        list then this raises [Not_found]. *)

    val combine3 : 'a list -> 'b list -> 'c list -> ('a * 'b * 'c) list
    (** Like {!List.combine} but for triples.
        All lists must be the same length. *)

    val assoc_lbl : ?cmp:('a -> 'a -> int) -> default:'b -> 'a -> ('a * 'b) list -> 'b
    (** Like {!assoc} but with a user-defined comparison function, and
        instead of raising [Not_found], it returns the [~default] value. *)

    val uniq : ?cmp:('a -> 'a -> int) -> 'a list -> 'a list
    (** Uniquify a list (the list must be sorted first). *)

    val sort_uniq : ?cmp:('a -> 'a -> int) -> 'a list -> 'a list
    (** Sort and uniquify a list. *)

    val remove_duplicates : 'a list -> 'a list
    (** Remove duplicates from an unsorted list; useful when the order
        of the elements matter.

        Please use [sort_uniq] when the order does not matter. *)

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

    val push_back_list : 'a list ref -> 'a list -> unit
    val push_front_list : 'a list -> 'a list ref -> unit
    (** More imperative list manipulation functions.

        [push_back_list] is like {!push_back} above, except it appends
        a list to the list reference.  This function is not tail-recursive.

        [push_front_list] is like {!push_front} above, except it prepends
        a list to the list reference. *)
end
(** Override the List module from stdlib. *)

module Option : sig
    val may : ('a -> unit) -> 'a option -> unit
    (** [may f (Some x)] runs [f x].  [may f None] does nothing. *)

    val map : ('a -> 'b) -> 'a option -> 'b option
    (** [map f (Some x)] returns [Some (f x)].  [map f None] returns [None]. *)

    val default : 'a -> 'a option -> 'a
    (** [default x (Some y)] returns [y].  [default x None] returns [x]. *)
end
(** Functions for dealing with option types. *)

val ( // ) : string -> string -> string
(** Concatenate directory and filename. *)

val quote : string -> string
(** Shell-safe quoting of a string (alias for {!Filename.quote}). *)

val subdirectory : string -> string -> string
(** [subdirectory parent path] returns subdirectory part of [path] relative
    to the [parent]. If [path] and [parent] point to the same directory empty
    string is returned.

    Note: path normalization on arguments is {b not} performed!

    If [parent] is not a path prefix of [path] the function raises
    [Invalid_argument]. *)

val ( +^ ) : int64 -> int64 -> int64
val ( -^ ) : int64 -> int64 -> int64
val ( *^ ) : int64 -> int64 -> int64
val ( /^ ) : int64 -> int64 -> int64
val ( &^ ) : int64 -> int64 -> int64
val ( ~^ ) : int64 -> int64
(** Various int64 operators. *)

external identity : 'a -> 'a = "%identity"

val roundup64 : int64 -> int64 -> int64
(** [roundup64 i a] returns [i] rounded up to the next multiple of [a]. *)
val div_roundup64 : int64 -> int64 -> int64
(** [div_roundup64 i a] returns [i] rounded up to the next multiple of [a],
    with the result divided by [a]. *)

val int_of_le16 : string -> int64
val le16_of_int : int64 -> string
val int_of_be16 : string -> int64
val be16_of_int : int64 -> string
val int_of_le32 : string -> int64
val le32_of_int : int64 -> string
val int_of_be32 : string -> int64
val be32_of_int : int64 -> string
val int_of_le64 : string -> int64
val le64_of_int : int64 -> string
val int_of_be64 : string -> int64
val be64_of_int : int64 -> string
(** [int_of_X] functions unpack a string and return the equivalent integer.

    [X_of_int] functions pack an integer into a string.

    The value of [X] encodes whether the string is stored as
    little endian [le] or big endian [be] and the size in bits
    [16], [32] or [64].

    On the OCaml side, 64 bit integers are always used so that you
    can use the [.^] operators on them for bit manipulation. *)

val wrap : ?chan:out_channel -> ?indent:int -> string -> unit
(** Wrap text. *)

val output_spaces : out_channel -> int -> unit
(** Write [n] spaces to [out_channel]. *)

val unique : unit -> int
(** Returns a unique number each time called. *)

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

type 'a return = { return: 'b. 'a -> 'b } (* OCaml >= 4.03: [@@unboxed] *)
val with_return : ('a return -> 'a) -> 'a
(** {v
    with_return (fun {return} ->
      some code ...
    )
    v}
    emulates the [return] statement found in other programming
    languages.

    The ‘some code’ part may either return implicitly, or may call
    [return x] to immediately return the value [x].  All returned
    values must have the same type. *)

val failwithf : ('a, unit, string, 'b) format4 -> 'a
(** Like [failwith] but supports printf-like arguments. *)

exception Executable_not_found of string (* executable *)
(** Exception thrown by [which] when the specified executable is not found
    in [$PATH]. *)

val which : string -> string
(** Return the full path of the specified executable from [$PATH].

    Throw [Executable_not_found] if not available. *)

val prog : string
(** The program name (derived from {!Sys.executable_name}). *)

val set_colours : unit -> unit
val colours : unit -> bool
val set_quiet : unit -> unit
val quiet : unit -> bool
val set_trace : unit -> unit
val trace : unit -> bool
val set_verbose : unit -> unit
val verbose : unit -> bool
(** Stores the colours ([--colours]), quiet ([--quiet]), trace ([-x])
    and verbose ([-v]) flags in global variables. *)

val with_open_in : string -> (in_channel -> 'a) -> 'a
(** [with_open_in filename f] calls function [f] with [filename]
    open for input.  The file is always closed either on normal
    return or if the function [f] throws an exception, so this is
    both safer and more concise than the regular function. *)

val with_open_out : string -> (out_channel -> 'a) -> 'a
(** [with_open_out filename f] calls function [f] with [filename]
    open for output.  The file is always closed either on normal
    return or if the function [f] throws an exception, so this is
    both safer and more concise than the regular function. *)

val with_openfile : string -> Unix.open_flag list -> Unix.file_perm -> (Unix.file_descr -> 'a) -> 'a
(** [with_openfile] calls function [f] with [filename] opened by the
    {!Unix.openfile} function.  The file is always closed either on
    normal return or if the function [f] throws an exception, so this
    is both safer and more concise than the regular function. *)

val read_whole_file : string -> string
(** Read in the whole file as a string. *)

val compare_version : string -> string -> int
(** Compare two version strings. *)

val compare_lvm2_uuids : string -> string -> int
(** Compare two LVM2 UUIDs, ignoring '-' characters. *)

val stringify_args : string list -> string
(** Create a "pretty-print" representation of a program invocation
    (i.e. executable and its arguments). *)

val unlink_on_exit : string -> unit
(** Unlink a temporary file on exit. *)

val is_block_device : string -> bool
val is_char_device : string -> bool
val is_directory : string -> bool
(** These don't throw exceptions, unlike the [Sys] functions. *)

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

val unix_like : string -> bool
(** Is the guest OS "Unix-like"?  Call this with the result of
    {!Guestfs.inspect_get_type}. *)

val last_part_of : string -> char -> string option
(** Return the last part of a string, after the specified separator. *)

val read_first_line_from_file : string -> string
(** Read only the first line (i.e. until the first newline character)
    of a file.  If the file is empty this returns an empty string. *)

val is_regular_file : string -> bool
(** Checks whether the file is a regular file. *)
