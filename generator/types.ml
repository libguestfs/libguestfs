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

(* Please read generator/README first. *)

(* Types used to describe the API - see [types.mli] file for the
   documentation. *)

type style = ret * args * optargs
and ret =
  | RErr
  | RInt of string
  | RInt64 of string
  | RBool of string
  | RConstString of string
  | RConstOptString of string
  | RString of rstringt * string
  | RStringList of rstringt * string
  | RStruct of string * string		(* name of retval, name of struct *)
  | RStructList of string * string	(* name of retval, name of struct *)
  | RHashtable of rstringt * rstringt * string
  | RBufferOut of string

and rstringt =
  | RPlainString        (* none of the others *)
  | RDevice             (* /dev device name *)
  | RMountable          (* location of mountable filesystem *)

and args = argt list	(* Function parameters, guestfs handle is implicit. *)

and argt =
  | Bool of string
  | Int of string
  | Int64 of string
  | String of stringt * string

  | OptString of string
  | StringList of stringt * string
  | BufferIn of string
  | Pointer of (string * string)

and stringt =
  | PlainString
  | Device
  | Mountable
  | Pathname
  | FileIn
  | FileOut
  | Key
  | GUID
  | Filename
  | Dev_or_Path
  | Mountable_or_Path

and optargs = optargt list

and optargt =
  | OBool of string
  | OInt of string
  | OInt64 of string
  | OString of string
  | OStringList of string

type errcode = [ `CannotReturnError | `ErrorIsMinusOne | `ErrorIsNULL ]

type fish_output_t =
  | FishOutputOctal       (* for int return, print in octal *)
  | FishOutputHexadecimal (* for int return, print in hex *)

(* See guestfs-hacking(1). *)
type c_api_tests = (c_api_test_init * c_api_test_prereq * c_api_test * c_api_test_cleanup) list
and c_api_test =
  | TestRun of seq
  | TestResult of seq * string
  | TestResultString of seq * string
  | TestResultDevice of seq * string
  | TestResultTrue of seq
  | TestResultFalse of seq
  | TestLastFail of seq
  | TestRunOrUnsupported of seq

(* Test prerequisites. *)
and c_api_test_prereq =
  | Always
  | Disabled
  | IfAvailable of string
  | IfNotCrossAppliance

(* Some initial scenarios for testing. *)
and c_api_test_init =
  | InitNone
  | InitEmpty
  | InitPartition
  | InitGPT
  | InitBasicFS
  | InitBasicFSonLVM
  | InitISOFS
  | InitScratchFS

(* Cleanup commands which are run whether the test succeeds or fails. *)
and c_api_test_cleanup = cmd list

(* Sequence of commands for testing. *)
and seq = cmd list
and cmd = string list

type visibility =
  | VPublic
  | VPublicNoFish
  | VStateTest
  | VBindTest
  | VDebug
  | VInternal

type version = int * int * int

type deprecated_by =
  | Not_deprecated
  | Replaced_by of string
  | Deprecated_no_replacement

type impl =
  | C
  | OCaml of string

(* Type of an action as declared in Actions module. *)
type action = {
  name : string;
  added : version;
  style : style;
  impl : impl;
  proc_nr : int option;
  tests : c_api_tests;
  test_excuse : string;
  shortdesc : string;
  longdesc : string;

  (* Lots of flags ... *)
  protocol_limit_warning : bool;
  fish_alias : string list;
  fish_output : fish_output_t option;
  visibility: visibility;
  deprecated_by : deprecated_by;  (* function is deprecated *)
  optional : string option;       (* function is part of an optional group *)
  progress : bool;                (* function can generate progress messages *)
  camel_name : string;            (* Pretty camel case name of
                                     function.  Only specify this if the
                                     generator doesn't make a good job of
                                     it, for example if it contains an
                                     abbreviation. *)
  cancellable : bool;             (* the user can cancel this long-running
                                     function *)
  config_only : bool;             (* non-daemon-function which can only be used
                                     while in CONFIG state *)
  once_had_no_optargs : bool;     (* mark functions that once had no optargs
                                     but now do, so we can generate the
                                     required back-compat machinery *)
  blocking : bool;                (* Function blocks (long-running).  All
                                     daemon functions are blocking by
                                     definition.  Some functions that just
                                     set flags in the handle are marked
                                     non-blocking so that we don't add
                                     machinery in various bindings. *)
  wrapper : bool;                 (* For non-daemon functions, generate a
                                     wrapper which calls the underlying
                                     guestfs_impl_<name> function.  The wrapper
                                     checks arguments and deals with trace
                                     messages.  Set this to false for functions
                                     that have to be thread-safe. *)

  (* "Internal" data attached by the generator at various stages.  This
   * doesn't need to (and shouldn't) be set when defining actions.
   *)
  c_name : string;                (* shortname exposed by C API *)
  c_function : string;            (* full name of C API function called by
                                     non-C bindings *)
  c_optarg_prefix : string;       (* prefix for optarg names/bitmask names *)
  non_c_aliases : string list;    (* back-compat aliases that have to be
                                     generated for this function *)
}

(* Default settings for all action fields.  So we copy and override
 * the action struct by writing '{ defaults with name = ... }'.
 *)
let defaults = { name = "";
                 added = (-1,-1,-1);
                 style = RErr, [], []; impl = C; proc_nr = None;
                 tests = []; test_excuse = "";
                 shortdesc = ""; longdesc = "";
                 protocol_limit_warning = false; fish_alias = [];
                 fish_output = None; visibility = VPublic;
                 deprecated_by = Not_deprecated; optional = None;
                 progress = false; camel_name = "";
                 cancellable = false; config_only = false;
                 once_had_no_optargs = false; blocking = true; wrapper = true;
                 c_name = ""; c_function = ""; c_optarg_prefix = "";
                 non_c_aliases = [] }

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
  | CallOStringList of string * string list
