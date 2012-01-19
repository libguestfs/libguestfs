(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

(* Please read generator/README first. *)

(* Types used to describe the API. *)

type style = ret * args * optargs
    (* The [style] is a tuple which describes the return value and
     * arguments of a function.
     * 
     * [ret] is the return value, one of the [R*] values below.
     * 
     * The second element is the list of required arguments, a list of
     * [argt]s from the list below, eg. [Bool], [String] etc.  Each has
     * a name so that for example [Int "foo"] corresponds in the C
     * bindings to an [int foo] parameter.
     * 
     * The third element is the list of optional arguments.  These are
     * mapped to optional arguments in the language binding, eg. in
     * Perl to:
     *   $g->fn (required1, required2, opt1 => val, opt2 => val);
     * As the name suggests these are optional, and the function can
     * tell which optional parameters were supplied by the caller.
     * 
     * Only [Bool], [Int], [Int64], [String] may currently appear in
     * the optional argument list (we may permit more types in future).
     *
     * ABI and API considerations
     * --------------------------
     * 
     * The return type and required arguments may not be changed after
     * these have been published in a stable version of libguestfs,
     * because doing so would break the ABI.
     * 
     * If a published function has one or more optional arguments,
     * then the call can be extended without breaking the ABI or API.
     * This is in fact the only way to change an existing function.
     * There are limitations on this:
     *
     * (1) you may _only_ add extra elements at the end of the list
     * (2) you may _not_ rearrange or rename or remove existing elements
     * (3) you may _not_ add optional arguments to a function which did
     *     not have any before (since this breaks the C ABI).
     *)

and ret =
    (* "RErr" as a return value means an int used as a simple error
     * indication, ie. 0 or -1.
     *)
  | RErr

    (* "RInt" as a return value means an int which is -1 for error
     * or any value >= 0 on success.  Only use this for smallish
     * positive ints (0 <= i < 2^30).
     *)
  | RInt of string

    (* "RInt64" is the same as RInt, but is guaranteed to be able
     * to return a full 64 bit value, _except_ that -1 means error
     * (so -1 cannot be a valid, non-error return value).
     *)
  | RInt64 of string

    (* "RBool" is a bool return value which can be true/false or
     * -1 for error.
     *)
  | RBool of string

    (* "RConstString" is a string that refers to a constant value.
     * The return value must NOT be NULL (since NULL indicates
     * an error).
     *
     * Try to avoid using this.  In particular you cannot use this
     * for values returned from the daemon, because there is no
     * thread-safe way to return them in the C API.
     *)
  | RConstString of string

    (* "RConstOptString" is an even more broken version of
     * "RConstString".  The returned string may be NULL and there
     * is no way to return an error indication.  Avoid using this!
     *)
  | RConstOptString of string

    (* "RString" is a returned string.  It must NOT be NULL, since
     * a NULL return indicates an error.  The caller frees this.
     *)
  | RString of string

    (* "RStringList" is a list of strings.  No string in the list
     * can be NULL.  The caller frees the strings and the array.
     *)
  | RStringList of string

    (* "RStruct" is a function which returns a single named structure
     * or an error indication (in C, a struct, and in other languages
     * with varying representations, but usually very efficient).  See
     * after the function list below for the structures.
     *)
  | RStruct of string * string		(* name of retval, name of struct *)

    (* "RStructList" is a function which returns either a list/array
     * of structures (could be zero-length), or an error indication.
     *)
  | RStructList of string * string	(* name of retval, name of struct *)

    (* Key-value pairs of untyped strings.  Turns into a hashtable or
     * dictionary in languages which support it.  DON'T use this as a
     * general "bucket" for results.  Prefer a stronger typed return
     * value if one is available, or write a custom struct.  Don't use
     * this if the list could potentially be very long, since it is
     * inefficient.  Keys should be unique.  NULLs are not permitted.
     *)
  | RHashtable of string

    (* "RBufferOut" is handled almost exactly like RString, but
     * it allows the string to contain arbitrary 8 bit data including
     * ASCII NUL.  In the C API this causes an implicit extra parameter
     * to be added of type <size_t *size_r>.  The extra parameter
     * returns the actual size of the return buffer in bytes.
     *
     * Other programming languages support strings with arbitrary 8 bit
     * data.
     *
     * At the RPC layer we have to use the opaque<> type instead of
     * string<>.  Returned data is still limited to the max message
     * size (ie. ~ 2 MB).
     *)
  | RBufferOut of string

and args = argt list	(* Function parameters, guestfs handle is implicit. *)

and argt =
  | Bool of string	(* boolean *)
  | Int of string	(* int (smallish ints, signed, <= 31 bits) *)
  | Int64 of string	(* any 64 bit int *)
  | String of string	(* const char *name, cannot be NULL *)
  | Device of string	(* /dev device name, cannot be NULL *)
  | Pathname of string	(* file name, cannot be NULL *)
  | Dev_or_Path of string (* /dev device name or Pathname, cannot be NULL *)
  | OptString of string	(* const char *name, may be NULL *)
  | StringList of string(* list of strings (each string cannot be NULL) *)
  | DeviceList of string(* list of Device names (each cannot be NULL) *)
    (* Opaque buffer which can contain arbitrary 8 bit data.
     * In the C API, this is expressed as <const char *, size_t> pair.
     * Most other languages have a string type which can contain
     * ASCII NUL.  We use whatever type is appropriate for each
     * language.
     * Buffers are limited by the total message size.  To transfer
     * large blocks of data, use FileIn/FileOut parameters instead.
     * To return an arbitrary buffer, use RBufferOut.
     *)
  | BufferIn of string
    (* Key material / passphrase.  Eventually we should treat this
     * as sensitive and mlock it into physical RAM.  However this
     * is highly complex because of all the places that XDR-encoded
     * strings can end up.  So currently the only difference from
     * 'String' is the way that guestfish requests these parameters
     * from the user.
     *)
  | Key of string
    (* These are treated as filenames (simple string parameters) in
     * the C API and bindings.  But in the RPC protocol, we transfer
     * the actual file content up to or down from the daemon.
     * FileIn: local machine -> daemon (in request)
     * FileOut: daemon -> local machine (in reply)
     * In guestfish (only), the special name "-" means read from
     * stdin or write to stdout.
     *)
  | FileIn of string
  | FileOut of string
    (* This specifies an opaque pointer that is passed through
     * untouched.  Only non-daemon functions are supported.
     *
     * Pointer ("foo *", "bar") translates to "foo *bar" in the
     * C API.  The pointer ("bar") cannot be NULL.
     *
     * This is less well supported in other language bindings:
     * if the pointer type is known then we may be able to produce
     * a suitable binding, otherwise this is translated into a 64
     * bit int.
     *
     * Functions with this parameter type are not supported at all
     * in guestfish (the function must be declared "NotInFish" else
     * you will get an error).  Also the function cannot contain
     * tests, although we should fix this in future.
     *)
  | Pointer of (string * string)

and optargs = optargt list

and optargt =
  | OBool of string	(* boolean *)
  | OInt of string	(* int (smallish ints, signed, <= 31 bits) *)
  | OInt64 of string	(* any 64 bit int *)
  | OString of string	(* const char *name, cannot be NULL *)

type errcode = [ `CannotReturnError | `ErrorIsMinusOne | `ErrorIsNULL ]

type flags =
  | ProtocolLimitWarning  (* display warning about protocol size limits *)
  | FishAlias of string	  (* provide an alias for this cmd in guestfish *)
  | FishOutput of fish_output_t (* how to display output in guestfish *)
  | NotInFish		  (* do not export via guestfish *)
  | NotInDocs		  (* do not add this function to documentation *)
  | DeprecatedBy of string (* function is deprecated, use .. instead *)
  | Optional of string	  (* function is part of an optional group *)
  | Progress              (* function can generate progress messages *)
  | CamelName of string   (* Pretty camel case name of function. Only specify
                             this if the generator doesn't make a good job of
                             it, for example if it contains an abbreviation.
                             This flag is currently only used by the GObject
                             bindings. *)
  | Cancellable           (* The user can cancel this long-running function *)

and fish_output_t =
  | FishOutputOctal       (* for int return, print in octal *)
  | FishOutputHexadecimal (* for int return, print in hex *)

(* See guestfs(3)/EXTENDING LIBGUESTFS. *)
type tests = (test_init * test_prereq * test) list
and test =
    (* Run the command sequence and just expect nothing to fail. *)
  | TestRun of seq

    (* Run the command sequence and expect the output of the final
     * command to be the string.
     *)
  | TestOutput of seq * string

    (* Run the command sequence and expect the output of the final
     * command to be the list of strings.
     *)
  | TestOutputList of seq * string list

    (* Run the command sequence and expect the output of the final
     * command to be the list of block devices (could be either
     * "/dev/sd.." or "/dev/hd.." form - we don't check the 5th
     * character of each string).
     *)
  | TestOutputListOfDevices of seq * string list

    (* Run the command sequence and expect the output of the final
     * command to be the integer.
     *)
  | TestOutputInt of seq * int

    (* Run the command sequence and expect the output of the final
     * command to be <op> <int>, eg. ">=", "1".
     *)
  | TestOutputIntOp of seq * string * int

    (* Run the command sequence and expect the output of the final
     * command to be a true value (!= 0 or != NULL).
     *)
  | TestOutputTrue of seq

    (* Run the command sequence and expect the output of the final
     * command to be a false value (== 0 or == NULL, but not an error).
     *)
  | TestOutputFalse of seq

    (* Run the command sequence and expect the output of the final
     * command to be a list of the given length (but don't care about
     * content).
     *)
  | TestOutputLength of seq * int

    (* Run the command sequence and expect the output of the final
     * command to be a buffer (RBufferOut), ie. string + size.
     *)
  | TestOutputBuffer of seq * string

    (* Run the command sequence and expect the output of the final
     * command to be a structure.
     *)
  | TestOutputStruct of seq * test_field_compare list

    (* Run the command sequence and expect the output of the final
     * command to be a string which is the hex MD5 of the content of
     * the named file.
     *)
  | TestOutputFileMD5 of seq * string

    (* Run the command sequence and expect the output of the final
     * command to be a string which is a block device name (we don't
     * check the 5th character of the string, so "/dev/sda" == "/dev/vda").
     *)
  | TestOutputDevice of seq * string

    (* Run the command sequence and expect a hashtable.  Check
     * one of more fields in the hashtable against known good
     * strings.
     *)
  | TestOutputHashtable of seq * (string * string) list

  (* Run the command sequence and expect the final command (only)
   * to fail.
   *)
  | TestLastFail of seq

and test_field_compare =
  | CompareWithInt of string * int
  | CompareWithIntOp of string * string * int
  | CompareWithString of string * string
  | CompareFieldsIntEq of string * string
  | CompareFieldsStrEq of string * string

(* Test prerequisites. *)
and test_prereq =
    (* Test always runs. *)
  | Always

    (* Test is currently disabled - eg. it fails, or it tests some
     * unimplemented feature.
     *)
  | Disabled

    (* 'string' is some C code (a function body) that should return
     * true or false.  The test will run if the code returns true.
     *)
  | If of string

    (* As for 'If' but the test runs _unless_ the code returns true. *)
  | Unless of string

    (* Run the test only if 'string' is available in the daemon. *)
  | IfAvailable of string

(* Some initial scenarios for testing. *)
and test_init =
    (* Do nothing, block devices could contain random stuff including
     * LVM PVs, and some filesystems might be mounted.  This is usually
     * a bad idea.
     *)
  | InitNone

    (* Block devices are empty and no filesystems are mounted. *)
  | InitEmpty

    (* /dev/sda contains a single partition /dev/sda1, with random
     * content.  No LVM.
     *)
  | InitPartition

    (* /dev/sda contains a single partition /dev/sda1, which is formatted
     * as ext2, empty [except for lost+found] and mounted on /.
     * No LVM.
     *
     * Note: for testing filesystem operations, it is quicker to use
     * InitScratchFS
     *)
  | InitBasicFS

    (* /dev/sda:
     *   /dev/sda1 (is a PV):
     *     /dev/VG/LV (size 8MB):
     *       formatted as ext2, empty [except for lost+found], mounted on /
     *
     * Note: only use this if you really need a freshly created filesystem
     * on LVM.  Normally you should use InitScratchFS instead.
     *)
  | InitBasicFSonLVM

    (* /dev/sdd (the ISO, see images/ directory in source)
     * is mounted on /
     *)
  | InitISOFS

    (* /dev/sdb1 (write scratch disk) is mounted on /.  The filesystem
     * will be empty.
     *
     * Note that this filesystem is not recreated between tests, and
     * could contain random files and directories from previous tests.
     * Therefore it is recommended that you create uniquely named files
     * and directories for your tests.
     *)
  | InitScratchFS

(* Sequence of commands for testing. *)
and seq = cmd list
and cmd = string list

(* Type of an action as declared in Generator_actions module. *)
type action = string * style * int * flags list * tests * string * string

(* Field types for structures. *)
type field =
  | FChar			(* C 'char' (really, a 7 bit byte). *)
  | FString			(* nul-terminated ASCII string, NOT NULL. *)
  | FBuffer			(* opaque buffer of bytes, (char *, int) pair *)
  | FUInt32
  | FInt32
  | FUInt64
  | FInt64
  | FBytes		        (* Any int measure that counts bytes. *)
  | FUUID			(* 32 bytes long, NOT nul-terminated. *)
  | FOptPercent			(* [0..100], or -1 meaning "not present". *)

(* Used for testing language bindings. *)
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
