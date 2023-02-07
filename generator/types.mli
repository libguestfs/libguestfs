(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(** Types used to describe the API. *)

type style = ret * args * optargs
(** The [style] is a tuple which describes the return value and
    arguments of a function.

    [ret] is the return value, one of the [R*] values below.

    The second element is the list of required arguments, a list of
    [argt]s from the list below, eg. [Bool], [String] etc.  Each has
    a name so that for example [Int "foo"] corresponds in the C
    bindings to an [int foo] parameter.

    The third element is the list of optional arguments.  These are
    mapped to optional arguments in the language binding, eg. in
    Perl to:
{v
      $g->fn (required1, required2, opt1 => val, opt2 => val);
v}
    As the name suggests these are optional, and the function can
    tell which optional parameters were supplied by the caller. *)

and ret =
  | RErr
(** "RErr" as a return value means an int used as a simple error
    indication, ie. 0 or -1. *)

  | RInt of string
(** "RInt" as a return value means an int which is -1 for error
    or any value >= 0 on success.  Only use this for smallish
    positive ints (0 <= i < 2^30). *)

  | RInt64 of string
(** "RInt64" is the same as RInt, but is guaranteed to be able
    to return a full 64 bit value, _except_ that -1 means error
    (so -1 cannot be a valid, non-error return value). *)

  | RBool of string
(** "RBool" is a bool return value which can be true/false or
    -1 for error. *)

  | RConstString of string
(** "RConstString" is a string that refers to a constant value.
    The return value must NOT be NULL (since NULL indicates
    an error).

    Try to avoid using this.  In particular you cannot use this
    for values returned from the daemon, because there is no
    thread-safe way to return them in the C API. *)

  | RConstOptString of string
(** "RConstOptString" is an even more broken version of
     "RConstString".  The returned string may be NULL and there
     is no way to return an error indication.  Avoid using this! *)

  | RString of rstringt * string
(** "RString" is a returned string.  It must NOT be NULL, since
    a NULL return indicates an error.  The caller frees this. *)

  | RStringList of rstringt * string
(** "RStringList" is a list of strings.  No string in the list
    can be NULL.  The caller frees the strings and the array. *)

  | RStruct of string * string		(* name of retval, name of struct *)
(** "RStruct" is a function which returns a single named structure
    or an error indication (in C, a struct, and in other languages
    with varying representations, but usually very efficient).  See
    after the function list below for the structures. *)

  | RStructList of string * string	(* name of retval, name of struct *)
(** "RStructList" is a function which returns either a list/array
    of structures (could be zero-length), or an error indication. *)

  | RHashtable of rstringt * rstringt * string
(** Key-value pairs of untyped strings.  Turns into a hashtable or
    dictionary in languages which support it.

    DON'T use this as a general "bucket" for results.  Prefer a
    stronger typed return value if one is available, or write a
    custom struct.  Don't use this if the list could potentially
    be very long, since it is inefficient.

    Keys should be unique.  NULLs are not permitted.
    The first rstringt is the type of the keys, the second
    rstringt is the type of the values. *)

  | RBufferOut of string
(** "RBufferOut" is handled almost exactly like RString, but
    it allows the string to contain arbitrary 8 bit data including
    ASCII NUL.  In the C API this causes an implicit extra parameter
    to be added of type <size_t *size_r>.  The extra parameter
    returns the actual size of the return buffer in bytes.

    Other programming languages support strings with arbitrary 8 bit
    data.

    At the RPC layer we have to use the opaque<> type instead of
    string<>.  Returned data is still limited to the max message
    size (ie. ~ 2 MB). *)

and rstringt =
  | RPlainString        (** none of the others *)
  | RDevice             (** /dev device name *)
  | RMountable          (** location of mountable filesystem *)

and args = argt list	(** Function parameters, guestfs handle is implicit. *)

and argt =
  | Bool of string	(** boolean *)
  | Int of string	(** int (smallish ints, signed, <= 31 bits) *)
  | Int64 of string	(** any 64 bit int *)

  | String of stringt * string
  (** Strings: These can be plain strings, device names, mountable
      filesystems, etc.  They cannot be NULL. *)

  | OptString of string	(** Plain string, may be NULL. *)

  | StringList of stringt * string
  (** List of strings: The strings may be plain strings, device names
      etc., but all of the same type.  The strings cannot be NULL. *)

  | BufferIn of string
  (** Opaque buffer which can contain arbitrary 8 bit data.
      In the C API, this is expressed as <const char *, size_t> pair.
      Most other languages have a string type which can contain
      ASCII NUL.  We use whatever type is appropriate for each
      language.

      Buffers are limited by the total message size.  To transfer
      large blocks of data, use FileIn/FileOut parameters instead.
      To return an arbitrary buffer, use RBufferOut. *)

  | Pointer of (string * string)
  (** This specifies an opaque pointer that is passed through
      untouched.  Only non-daemon functions are supported.

      Pointer ("foo *", "bar") translates to "foo *bar" in the
      C API.  The pointer ("bar") cannot be NULL.

      This is less well supported in other language bindings:
      if the pointer type is known then we may be able to produce
      a suitable binding, otherwise this is translated into a 64
      bit int.

      Functions with this parameter type are not supported at all
      in guestfish (the function must be declared "NotInFish" else
      you will get an error).  Also the function cannot contain
      tests, although we should fix this in future. *)

and stringt =
  | PlainString         (** none of the others *)
  | Device              (** /dev device name *)
  | Mountable           (** location of mountable filesystem *)

  | Pathname
  (** An absolute path within the appliance filesystem. *)

  | FileIn
  | FileOut
  (** These are treated as filenames (simple string parameters) in
      the C API and bindings.  But in the RPC protocol, we transfer
      the actual file content up to or down from the daemon.
      FileIn: local machine -> daemon (in request)
      FileOut: daemon -> local machine (in reply)
      In guestfish (only), the special name "-" means read from
      stdin or write to stdout. *)

  | Key
  (** Key material / passphrase.  Eventually we should treat this
      as sensitive and mlock it into physical RAM.  However this
      is highly complex because of all the places that XDR-encoded
      strings can end up.  So currently the only difference from
      'PlainString' is the way that guestfish requests these
      parameters from the user. *)

  | GUID
  (** A GUID string.

      It cannot be NULL, and it will be validated using
      guestfs_int_validate_guid. *)

  | Filename
  (** A simple filename (not a path nor a relative path).  It cannot
      be NULL, empty, or anything different than a simple file name. *)

    (* The following two are DEPRECATED and must not be used in
     * any new APIs.
     *)
  | Dev_or_Path         (** Device or Pathname. *)
  | Mountable_or_Path   (** Mountable or Pathname. *)

and optargs = optargt list

and optargt =
  | OBool of string	(** boolean *)
  | OInt of string	(** int (smallish ints, signed, <= 31 bits) *)
  | OInt64 of string	(** any 64 bit int *)
  | OString of string	(** const char *name, cannot be NULL *)
  | OStringList of string (** char **strings, neither the list nor any
                             string may be NULL *)

type errcode = [ `CannotReturnError | `ErrorIsMinusOne | `ErrorIsNULL ]

type fish_output_t =
  | FishOutputOctal       (* for int return, print in octal *)
  | FishOutputHexadecimal (* for int return, print in hex *)

(* See guestfs-hacking(1). *)
type c_api_tests = (c_api_test_init * c_api_test_prereq * c_api_test * c_api_test_cleanup) list
and c_api_test =
  | TestRun of seq
  (** Run the command sequence and just expect nothing to fail. *)

  | TestResult of seq * string
  (** Run the command sequence.  No command should fail, and the
      output of the command(s) is tested using the C expression which
      should return true.

      In the C expression, 'ret' is the result of the final command,
      'ret1' is the result of the last but one command, and so on
      backwards. *)

  | TestResultString of seq * string
  | TestResultDevice of seq * string
  (** Run the command sequence.  No command should fail, and the
      last command must return the given string or device name. *)

  | TestResultTrue of seq
  | TestResultFalse of seq
  (** Run the command sequence.  No command should fail, and the
      last command must return true or false. *)

  | TestLastFail of seq
  (** Run the command sequence and expect the final command (only)
      to fail. *)

  | TestRunOrUnsupported of seq
  (** Run the command sequence and expect either nothing to fail,
      or that the last command only can fail with ENOTSUP. *)

(** Test prerequisites. *)
and c_api_test_prereq =
  | Always
  (** Test always runs. *)

  | Disabled
  (** Test is currently disabled - eg. it fails, or it tests some
      unimplemented feature. *)

  | IfAvailable of string
  (** Run the test only if 'string' is available in the daemon. *)

  | IfNotCrossAppliance
  (** Run the test when the appliance and the OS differ - for example,
      when using a fixed appliance created in a different OS/distribution. *)

(** Some initial scenarios for testing. *)
and c_api_test_init =
  | InitNone
  (** Do nothing, block devices could contain random stuff including
      LVM PVs, and some filesystems might be mounted.  This is usually
      a bad idea. *)

  | InitEmpty
  (** Block devices are empty and no filesystems are mounted. *)

  | InitPartition
  (** /dev/sda contains a single partition /dev/sda1, with random
      content.  No LVM. *)

  | InitGPT
  (** Identical to InitPartition, except that the partition table is GPT
      instead of MBR. *)

  | InitBasicFS
  (** /dev/sda contains a single partition /dev/sda1, which is formatted
      as ext2, empty [except for lost+found] and mounted on /.
      No LVM.

      Note: for testing filesystem operations, it is quicker to use
      InitScratchFS *)

  | InitBasicFSonLVM
  (** /dev/sda:
        /dev/sda1 (is a PV):
          /dev/VG/LV (size 8MB):
            formatted as ext2, empty [except for lost+found], mounted on /
     
      Note: only use this if you really need a freshly created filesystem
      on LVM.  Normally you should use InitScratchFS instead. *)

  | InitISOFS
  (** /dev/sdd (the ISO, see images/ directory in source)
      is mounted on / *)

  | InitScratchFS
  (** /dev/sdb1 (write scratch disk) is mounted on /.  The filesystem
      will be empty.

      Note that this filesystem is not recreated between tests, and
      could contain random files and directories from previous tests.
      Therefore it is recommended that you create uniquely named files
      and directories for your tests. *)

and c_api_test_cleanup = cmd list
(** Cleanup commands which are run whether the test succeeds or fails. *)

and seq = cmd list
and cmd = string list
(** Sequence of commands for testing. *)

type visibility =
  | VPublic                       (** Part of the public API *)
  | VPublicNoFish                 (** Like VPublic, but not exported in
                                      guestfish *)
  | VStateTest                    (** A function which tests the state
                                      of the appliance *)
  | VBindTest                     (** Only used for testing language bindings *)
  | VDebug                        (** Exported everywhere, but not documented *)
  | VInternal                     (** Not exported *)

type version = int * int * int

type deprecated_by =
  | Not_deprecated                (** function not deprecated *)
  | Replaced_by of string         (** replaced by another function *)
  | Deprecated_no_replacement     (** deprecated with no replacement *)

type impl =
  | C                             (** implemented in C by "do_<name>" *)
  | OCaml of string               (** implemented in OCaml by named function *)

(** Type of an action as declared in Actions module. *)
type action = {
  name : string;                  (** name, not including "guestfs_" *)
  added : version;                (** which version was the API first added *)
  style : style;                  (** args and return value *)
  impl : impl;                    (** implementation language (C or OCaml) *)
  proc_nr : int option;           (** proc number, None for non-daemon *)
  tests : c_api_tests;            (** C API tests *)
  test_excuse : string;           (** if there's no tests ... *)
  shortdesc : string;             (** single line description *)
  longdesc : string;              (** longer documentation *)

  (* Lots of flags ... *)
  protocol_limit_warning : bool;  (** warn about protocol size limits *)
  fish_alias : string list;       (** alias(es) for this cmd in guestfish *)
  fish_output : fish_output_t option; (** how to display output in guestfish *)
  visibility: visibility;         (** The visbility of function *)
  deprecated_by : deprecated_by;  (** function is deprecated *)
  optional : string option;       (** function is part of an optional group *)
  progress : bool;                (** function can generate progress messages *)
  camel_name : string;            (** Pretty camel case name of
                                      function.  Only specify this if the
                                      generator doesn't make a good job of
                                      it, for example if it contains an
                                      abbreviation. *)
  cancellable : bool;             (** the user can cancel this long-running
                                      function *)
  config_only : bool;             (** non-daemon-function which can only be used
                                      while in CONFIG state *)
  once_had_no_optargs : bool;     (** mark functions that once had no optargs
                                      but now do, so we can generate the
                                      required back-compat machinery *)
  blocking : bool;                (** Function blocks (long-running).  All
                                      daemon functions are blocking by
                                      definition.  Some functions that just
                                      set flags in the handle are marked
                                      non-blocking so that we don't add
                                      machinery in various bindings. *)
  wrapper : bool;                 (** For non-daemon functions, generate a
                                      wrapper which calls the underlying
                                      guestfs_impl_<name> function.  The wrapper
                                      checks arguments and deals with trace
                                      messages.  Set this to false for functions
                                      that have to be thread-safe. *)

  (* "Internal" data attached by the generator at various stages.  This
   * doesn't need to (and shouldn't) be set when defining actions.
   *)
  c_name : string;                (** shortname exposed by C API *)
  c_function : string;            (** full name of C API function called by
                                      non-C bindings *)
  c_optarg_prefix : string;       (** prefix for optarg names/bitmask names *)
  non_c_aliases : string list;    (** back-compat aliases that have to be
                                      generated for this function *)
}

(** Default settings for all action fields.  So we copy and override
    the action struct by writing '{ defaults with name = ... }'. *)
val defaults : action

(** Field types for structures. *)
type field =
  | FChar			(** C 'char' (really, a 7 bit byte). *)
  | FString			(** nul-terminated ASCII string, NOT NULL. *)
  | FBuffer			(** opaque buffer of bytes, (char *, int) pair*)
  | FUInt32
  | FInt32
  | FUInt64
  | FInt64
  | FBytes		        (** Any int measure that counts bytes. *)
  | FUUID			(** 32 bytes long, NOT nul-terminated. *)
  | FOptPercent			(** [0..100], or -1 meaning "not present". *)

(** Used for testing language bindings. *)
type callt =
  | CallString of string
  | CallOptString of string option
  | CallStringList of string list
  | CallInt of int
  | CallInt64 of int64
  | CallBool of bool
  | CallBuffer of string

type call_optargt =
  | CallOBool of string * bool
  | CallOInt of string * int
  | CallOInt64 of string * int64
  | CallOString of string * string
  | CallOStringList of string * string list
