#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

(* This script generates a large amount of code and documentation for
 * all the daemon actions.
 * 
 * To add a new action there are only two files you need to change,
 * this one to describe the interface (see the big table of
 * 'daemon_functions' below), and daemon/<somefile>.c to write the
 * implementation.
 * 
 * After editing this file, run it (./src/generator.ml) to regenerate
 * all the output files.  'make' will rerun this automatically when
 * necessary.  Note that if you are using a separate build directory
 * you must run generator.ml from the _source_ directory.
 * 
 * IMPORTANT: This script should NOT print any warnings.  If it prints
 * warnings, you should treat them as errors.
 *
 * OCaml tips:
 * (1) In emacs, install tuareg-mode to display and format OCaml code
 * correctly.  'vim' comes with a good OCaml editing mode by default.
 * (2) Read the resources at http://ocaml-tutorial.org/
 *)

#load "unix.cma";;
#load "str.cma";;
#directory "+xml-light";;
#load "xml-light.cma";;

open Unix
open Printf

type style = ret * args
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

    (* Note in future we should allow a "variable args" parameter as
     * the final parameter, to allow commands like
     *   chmod mode file [file(s)...]
     * This is not implemented yet, but many commands (such as chmod)
     * are currently defined with the argument order keeping this future
     * possibility in mind.
     *)
and argt =
  | String of string	(* const char *name, cannot be NULL *)
  | Device of string	(* /dev device name, cannot be NULL *)
  | Pathname of string	(* file name, cannot be NULL *)
  | Dev_or_Path of string (* /dev device name or Pathname, cannot be NULL *)
  | OptString of string	(* const char *name, may be NULL *)
  | StringList of string(* list of strings (each string cannot be NULL) *)
  | DeviceList of string(* list of Device names (each cannot be NULL) *)
  | Bool of string	(* boolean *)
  | Int of string	(* int (smallish ints, signed, <= 31 bits) *)
  | Int64 of string	(* any 64 bit int *)
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
(* Not implemented:
    (* Opaque buffer which can contain arbitrary 8 bit data.
     * In the C API, this is expressed as <char *, int> pair.
     * Most other languages have a string type which can contain
     * ASCII NUL.  We use whatever type is appropriate for each
     * language.
     * Buffers are limited by the total message size.  To transfer
     * large blocks of data, use FileIn/FileOut parameters instead.
     * To return an arbitrary buffer, use RBufferOut.
     *)
  | BufferIn of string
*)

type flags =
  | ProtocolLimitWarning  (* display warning about protocol size limits *)
  | DangerWillRobinson	  (* flags particularly dangerous commands *)
  | FishAlias of string	  (* provide an alias for this cmd in guestfish *)
  | FishAction of string  (* call this function in guestfish *)
  | NotInFish		  (* do not export via guestfish *)
  | NotInDocs		  (* do not add this function to documentation *)
  | DeprecatedBy of string (* function is deprecated, use .. instead *)
  | Optional of string	  (* function is part of an optional group *)

(* You can supply zero or as many tests as you want per API call.
 *
 * Note that the test environment has 3 block devices, of size 500MB,
 * 50MB and 10MB (respectively /dev/sda, /dev/sdb, /dev/sdc), and
 * a fourth ISO block device with some known files on it (/dev/sdd).
 *
 * Note for partitioning purposes, the 500MB device has 1015 cylinders.
 * Number of cylinders was 63 for IDE emulated disks with precisely
 * the same size.  How exactly this is calculated is a mystery.
 *
 * The ISO block device (/dev/sdd) comes from images/test.iso.
 *
 * To be able to run the tests in a reasonable amount of time,
 * the virtual machine and block devices are reused between tests.
 * So don't try testing kill_subprocess :-x
 *
 * Between each test we blockdev-setrw, umount-all, lvm-remove-all.
 *
 * Don't assume anything about the previous contents of the block
 * devices.  Use 'Init*' to create some initial scenarios.
 *
 * You can add a prerequisite clause to any individual test.  This
 * is a run-time check, which, if it fails, causes the test to be
 * skipped.  Useful if testing a command which might not work on
 * all variations of libguestfs builds.  A test that has prerequisite
 * of 'Always' is run unconditionally.
 *
 * In addition, packagers can skip individual tests by setting the
 * environment variables:     eg:
 *   SKIP_TEST_<CMD>_<NUM>=1  SKIP_TEST_COMMAND_3=1  (skips test #3 of command)
 *   SKIP_TEST_<CMD>=1        SKIP_TEST_ZEROFREE=1   (skips all zerofree tests)
 *)
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
     * content.  /dev/sdb and /dev/sdc may have random content.
     * No LVM.
     *)
  | InitPartition

    (* /dev/sda contains a single partition /dev/sda1, which is formatted
     * as ext2, empty [except for lost+found] and mounted on /.
     * /dev/sdb and /dev/sdc may have random content.
     * No LVM.
     *)
  | InitBasicFS

    (* /dev/sda:
     *   /dev/sda1 (is a PV):
     *     /dev/VG/LV (size 8MB):
     *       formatted as ext2, empty [except for lost+found], mounted on /
     * /dev/sdb and /dev/sdc may have random content.
     *)
  | InitBasicFSonLVM

    (* /dev/sdd (the ISO, see images/ directory in source)
     * is mounted on /
     *)
  | InitISOFS

(* Sequence of commands for testing. *)
and seq = cmd list
and cmd = string list

(* Note about long descriptions: When referring to another
 * action, use the format C<guestfs_other> (ie. the full name of
 * the C function).  This will be replaced as appropriate in other
 * language bindings.
 *
 * Apart from that, long descriptions are just perldoc paragraphs.
 *)

(* Generate a random UUID (used in tests). *)
let uuidgen () =
  let chan = open_process_in "uuidgen" in
  let uuid = input_line chan in
  (match close_process_in chan with
   | WEXITED 0 -> ()
   | WEXITED _ ->
       failwith "uuidgen: process exited with non-zero status"
   | WSIGNALED _ | WSTOPPED _ ->
       failwith "uuidgen: process signalled or stopped by signal"
  );
  uuid

(* These test functions are used in the language binding tests. *)

let test_all_args = [
  String "str";
  OptString "optstr";
  StringList "strlist";
  Bool "b";
  Int "integer";
  Int64 "integer64";
  FileIn "filein";
  FileOut "fileout";
]

let test_all_rets = [
  (* except for RErr, which is tested thoroughly elsewhere *)
  "test0rint",         RInt "valout";
  "test0rint64",       RInt64 "valout";
  "test0rbool",        RBool "valout";
  "test0rconststring", RConstString "valout";
  "test0rconstoptstring", RConstOptString "valout";
  "test0rstring",      RString "valout";
  "test0rstringlist",  RStringList "valout";
  "test0rstruct",      RStruct ("valout", "lvm_pv");
  "test0rstructlist",  RStructList ("valout", "lvm_pv");
  "test0rhashtable",   RHashtable "valout";
]

let test_functions = [
  ("test0", (RErr, test_all_args), -1, [NotInFish; NotInDocs],
   [],
   "internal test function - do not use",
   "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It echos the contents of each parameter to stdout.

You probably don't want to call this function.");
] @ List.flatten (
  List.map (
    fun (name, ret) ->
      [(name, (ret, [String "val"]), -1, [NotInFish; NotInDocs],
        [],
        "internal test function - do not use",
        "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

It converts string C<val> to the return type.

You probably don't want to call this function.");
       (name ^ "err", (ret, []), -1, [NotInFish; NotInDocs],
        [],
        "internal test function - do not use",
        "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

This function always returns an error.

You probably don't want to call this function.")]
  ) test_all_rets
)

(* non_daemon_functions are any functions which don't get processed
 * in the daemon, eg. functions for setting and getting local
 * configuration values.
 *)

let non_daemon_functions = test_functions @ [
  ("launch", (RErr, []), -1, [FishAlias "run"; FishAction "launch"],
   [],
   "launch the qemu subprocess",
   "\
Internally libguestfs is implemented by running a virtual machine
using L<qemu(1)>.

You should call this after configuring the handle
(eg. adding drives) but before performing any actions.");

  ("wait_ready", (RErr, []), -1, [NotInFish],
   [],
   "wait until the qemu subprocess launches (no op)",
   "\
This function is a no op.

In versions of the API E<lt> 1.0.71 you had to call this function
just after calling C<guestfs_launch> to wait for the launch
to complete.  However this is no longer necessary because
C<guestfs_launch> now does the waiting.

If you see any calls to this function in code then you can just
remove them, unless you want to retain compatibility with older
versions of the API.");

  ("kill_subprocess", (RErr, []), -1, [],
   [],
   "kill the qemu subprocess",
   "\
This kills the qemu subprocess.  You should never need to call this.");

  ("add_drive", (RErr, [String "filename"]), -1, [FishAlias "add"],
   [],
   "add an image to examine or modify",
   "\
This function adds a virtual machine disk image C<filename> to the
guest.  The first time you call this function, the disk appears as IDE
disk 0 (C</dev/sda>) in the guest, the second time as C</dev/sdb>, and
so on.

You don't necessarily need to be root when using libguestfs.  However
you obviously do need sufficient permissions to access the filename
for whatever operations you want to perform (ie. read access if you
just want to read the image or write access if you want to modify the
image).

This is equivalent to the qemu parameter
C<-drive file=filename,cache=off,if=...>.
C<cache=off> is omitted in cases where it is not supported by
the underlying filesystem.

Note that this call checks for the existence of C<filename>.  This
stops you from specifying other types of drive which are supported
by qemu such as C<nbd:> and C<http:> URLs.  To specify those, use
the general C<guestfs_config> call instead.");

  ("add_cdrom", (RErr, [String "filename"]), -1, [FishAlias "cdrom"],
   [],
   "add a CD-ROM disk image to examine",
   "\
This function adds a virtual CD-ROM disk image to the guest.

This is equivalent to the qemu parameter C<-cdrom filename>.

Note that this call checks for the existence of C<filename>.  This
stops you from specifying other types of drive which are supported
by qemu such as C<nbd:> and C<http:> URLs.  To specify those, use
the general C<guestfs_config> call instead.");

  ("add_drive_ro", (RErr, [String "filename"]), -1, [FishAlias "add-ro"],
   [],
   "add a drive in snapshot mode (read-only)",
   "\
This adds a drive in snapshot mode, making it effectively
read-only.

Note that writes to the device are allowed, and will be seen for
the duration of the guestfs handle, but they are written
to a temporary file which is discarded as soon as the guestfs
handle is closed.  We don't currently have any method to enable
changes to be committed, although qemu can support this.

This is equivalent to the qemu parameter
C<-drive file=filename,snapshot=on,if=...>.

Note that this call checks for the existence of C<filename>.  This
stops you from specifying other types of drive which are supported
by qemu such as C<nbd:> and C<http:> URLs.  To specify those, use
the general C<guestfs_config> call instead.");

  ("config", (RErr, [String "qemuparam"; OptString "qemuvalue"]), -1, [],
   [],
   "add qemu parameters",
   "\
This can be used to add arbitrary qemu command line parameters
of the form C<-param value>.  Actually it's not quite arbitrary - we
prevent you from setting some parameters which would interfere with
parameters that we use.

The first character of C<param> string must be a C<-> (dash).

C<value> can be NULL.");

  ("set_qemu", (RErr, [String "qemu"]), -1, [FishAlias "qemu"],
   [],
   "set the qemu binary",
   "\
Set the qemu binary that we will use.

The default is chosen when the library was compiled by the
configure script.

You can also override this by setting the C<LIBGUESTFS_QEMU>
environment variable.

Setting C<qemu> to C<NULL> restores the default qemu binary.");

  ("get_qemu", (RConstString "qemu", []), -1, [],
   [InitNone, Always, TestRun (
      [["get_qemu"]])],
   "get the qemu binary",
   "\
Return the current qemu binary.

This is always non-NULL.  If it wasn't set already, then this will
return the default qemu binary name.");

  ("set_path", (RErr, [String "searchpath"]), -1, [FishAlias "path"],
   [],
   "set the search path",
   "\
Set the path that libguestfs searches for kernel and initrd.img.

The default is C<$libdir/guestfs> unless overridden by setting
C<LIBGUESTFS_PATH> environment variable.

Setting C<path> to C<NULL> restores the default path.");

  ("get_path", (RConstString "path", []), -1, [],
   [InitNone, Always, TestRun (
      [["get_path"]])],
   "get the search path",
   "\
Return the current search path.

This is always non-NULL.  If it wasn't set already, then this will
return the default path.");

  ("set_append", (RErr, [OptString "append"]), -1, [FishAlias "append"],
   [],
   "add options to kernel command line",
   "\
This function is used to add additional options to the
guest kernel command line.

The default is C<NULL> unless overridden by setting
C<LIBGUESTFS_APPEND> environment variable.

Setting C<append> to C<NULL> means I<no> additional options
are passed (libguestfs always adds a few of its own).");

  ("get_append", (RConstOptString "append", []), -1, [],
   (* This cannot be tested with the current framework.  The
    * function can return NULL in normal operations, which the
    * test framework interprets as an error.
    *)
   [],
   "get the additional kernel options",
   "\
Return the additional kernel options which are added to the
guest kernel command line.

If C<NULL> then no options are added.");

  ("set_autosync", (RErr, [Bool "autosync"]), -1, [FishAlias "autosync"],
   [],
   "set autosync mode",
   "\
If C<autosync> is true, this enables autosync.  Libguestfs will make a
best effort attempt to run C<guestfs_umount_all> followed by
C<guestfs_sync> when the handle is closed
(also if the program exits without closing handles).

This is disabled by default (except in guestfish where it is
enabled by default).");

  ("get_autosync", (RBool "autosync", []), -1, [],
   [InitNone, Always, TestRun (
      [["get_autosync"]])],
   "get autosync mode",
   "\
Get the autosync flag.");

  ("set_verbose", (RErr, [Bool "verbose"]), -1, [FishAlias "verbose"],
   [],
   "set verbose mode",
   "\
If C<verbose> is true, this turns on verbose messages (to C<stderr>).

Verbose messages are disabled unless the environment variable
C<LIBGUESTFS_DEBUG> is defined and set to C<1>.");

  ("get_verbose", (RBool "verbose", []), -1, [],
   [],
   "get verbose mode",
   "\
This returns the verbose messages flag.");

  ("is_ready", (RBool "ready", []), -1, [],
   [InitNone, Always, TestOutputTrue (
      [["is_ready"]])],
   "is ready to accept commands",
   "\
This returns true iff this handle is ready to accept commands
(in the C<READY> state).

For more information on states, see L<guestfs(3)>.");

  ("is_config", (RBool "config", []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_config"]])],
   "is in configuration state",
   "\
This returns true iff this handle is being configured
(in the C<CONFIG> state).

For more information on states, see L<guestfs(3)>.");

  ("is_launching", (RBool "launching", []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_launching"]])],
   "is launching subprocess",
   "\
This returns true iff this handle is launching the subprocess
(in the C<LAUNCHING> state).

For more information on states, see L<guestfs(3)>.");

  ("is_busy", (RBool "busy", []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_busy"]])],
   "is busy processing a command",
   "\
This returns true iff this handle is busy processing a command
(in the C<BUSY> state).

For more information on states, see L<guestfs(3)>.");

  ("get_state", (RInt "state", []), -1, [],
   [],
   "get the current state",
   "\
This returns the current state as an opaque integer.  This is
only useful for printing debug and internal error messages.

For more information on states, see L<guestfs(3)>.");

  ("set_memsize", (RErr, [Int "memsize"]), -1, [FishAlias "memsize"],
   [InitNone, Always, TestOutputInt (
      [["set_memsize"; "500"];
       ["get_memsize"]], 500)],
   "set memory allocated to the qemu subprocess",
   "\
This sets the memory size in megabytes allocated to the
qemu subprocess.  This only has any effect if called before
C<guestfs_launch>.

You can also change this by setting the environment
variable C<LIBGUESTFS_MEMSIZE> before the handle is
created.

For more information on the architecture of libguestfs,
see L<guestfs(3)>.");

  ("get_memsize", (RInt "memsize", []), -1, [],
   [InitNone, Always, TestOutputIntOp (
      [["get_memsize"]], ">=", 256)],
   "get memory allocated to the qemu subprocess",
   "\
This gets the memory size in megabytes allocated to the
qemu subprocess.

If C<guestfs_set_memsize> was not called
on this handle, and if C<LIBGUESTFS_MEMSIZE> was not set,
then this returns the compiled-in default value for memsize.

For more information on the architecture of libguestfs,
see L<guestfs(3)>.");

  ("get_pid", (RInt "pid", []), -1, [FishAlias "pid"],
   [InitNone, Always, TestOutputIntOp (
      [["get_pid"]], ">=", 1)],
   "get PID of qemu subprocess",
   "\
Return the process ID of the qemu subprocess.  If there is no
qemu subprocess, then this will return an error.

This is an internal call used for debugging and testing.");

  ("version", (RStruct ("version", "version"), []), -1, [],
   [InitNone, Always, TestOutputStruct (
      [["version"]], [CompareWithInt ("major", 1)])],
   "get the library version number",
   "\
Return the libguestfs version number that the program is linked
against.

Note that because of dynamic linking this is not necessarily
the version of libguestfs that you compiled against.  You can
compile the program, and then at runtime dynamically link
against a completely different C<libguestfs.so> library.

This call was added in version C<1.0.58>.  In previous
versions of libguestfs there was no way to get the version
number.  From C code you can use ELF weak linking tricks to find out if
this symbol exists (if it doesn't, then it's an earlier version).

The call returns a structure with four elements.  The first
three (C<major>, C<minor> and C<release>) are numbers and
correspond to the usual version triplet.  The fourth element
(C<extra>) is a string and is normally empty, but may be
used for distro-specific information.

To construct the original version string:
C<$major.$minor.$release$extra>

I<Note:> Don't use this call to test for availability
of features.  Distro backports makes this unreliable.  Use
C<guestfs_available> instead.");

  ("set_selinux", (RErr, [Bool "selinux"]), -1, [FishAlias "selinux"],
   [InitNone, Always, TestOutputTrue (
      [["set_selinux"; "true"];
       ["get_selinux"]])],
   "set SELinux enabled or disabled at appliance boot",
   "\
This sets the selinux flag that is passed to the appliance
at boot time.  The default is C<selinux=0> (disabled).

Note that if SELinux is enabled, it is always in
Permissive mode (C<enforcing=0>).

For more information on the architecture of libguestfs,
see L<guestfs(3)>.");

  ("get_selinux", (RBool "selinux", []), -1, [],
   [],
   "get SELinux enabled flag",
   "\
This returns the current setting of the selinux flag which
is passed to the appliance at boot time.  See C<guestfs_set_selinux>.

For more information on the architecture of libguestfs,
see L<guestfs(3)>.");

  ("set_trace", (RErr, [Bool "trace"]), -1, [FishAlias "trace"],
   [InitNone, Always, TestOutputFalse (
      [["set_trace"; "false"];
       ["get_trace"]])],
   "enable or disable command traces",
   "\
If the command trace flag is set to 1, then commands are
printed on stdout before they are executed in a format
which is very similar to the one used by guestfish.  In
other words, you can run a program with this enabled, and
you will get out a script which you can feed to guestfish
to perform the same set of actions.

If you want to trace C API calls into libguestfs (and
other libraries) then possibly a better way is to use
the external ltrace(1) command.

Command traces are disabled unless the environment variable
C<LIBGUESTFS_TRACE> is defined and set to C<1>.");

  ("get_trace", (RBool "trace", []), -1, [],
   [],
   "get command trace enabled flag",
   "\
Return the command trace flag.");

  ("set_direct", (RErr, [Bool "direct"]), -1, [FishAlias "direct"],
   [InitNone, Always, TestOutputFalse (
      [["set_direct"; "false"];
       ["get_direct"]])],
   "enable or disable direct appliance mode",
   "\
If the direct appliance mode flag is enabled, then stdin and
stdout are passed directly through to the appliance once it
is launched.

One consequence of this is that log messages aren't caught
by the library and handled by C<guestfs_set_log_message_callback>,
but go straight to stdout.

You probably don't want to use this unless you know what you
are doing.

The default is disabled.");

  ("get_direct", (RBool "direct", []), -1, [],
   [],
   "get direct appliance mode flag",
   "\
Return the direct appliance mode flag.");

  ("set_recovery_proc", (RErr, [Bool "recoveryproc"]), -1, [FishAlias "recovery-proc"],
   [InitNone, Always, TestOutputTrue (
      [["set_recovery_proc"; "true"];
       ["get_recovery_proc"]])],
   "enable or disable the recovery process",
   "\
If this is called with the parameter C<false> then
C<guestfs_launch> does not create a recovery process.  The
purpose of the recovery process is to stop runaway qemu
processes in the case where the main program aborts abruptly.

This only has any effect if called before C<guestfs_launch>,
and the default is true.

About the only time when you would want to disable this is
if the main process will fork itself into the background
(\"daemonize\" itself).  In this case the recovery process
thinks that the main program has disappeared and so kills
qemu, which is not very helpful.");

  ("get_recovery_proc", (RBool "recoveryproc", []), -1, [],
   [],
   "get recovery process enabled flag",
   "\
Return the recovery process enabled flag.");

]

(* daemon_functions are any functions which cause some action
 * to take place in the daemon.
 *)

let daemon_functions = [
  ("mount", (RErr, [Device "device"; String "mountpoint"]), 1, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "mount a guest disk at a position in the filesystem",
   "\
Mount a guest disk at a position in the filesystem.  Block devices
are named C</dev/sda>, C</dev/sdb> and so on, as they were added to
the guest.  If those block devices contain partitions, they will have
the usual names (eg. C</dev/sda1>).  Also LVM C</dev/VG/LV>-style
names can be used.

The rules are the same as for L<mount(2)>:  A filesystem must
first be mounted on C</> before others can be mounted.  Other
filesystems can only be mounted on directories which already
exist.

The mounted filesystem is writable, if we have sufficient permissions
on the underlying device.

The filesystem options C<sync> and C<noatime> are set with this
call, in order to improve reliability.");

  ("sync", (RErr, []), 2, [],
   [ InitEmpty, Always, TestRun [["sync"]]],
   "sync disks, writes are flushed through to the disk image",
   "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
closing the handle.");

  ("touch", (RErr, [Pathname "path"]), 3, [],
   [InitBasicFS, Always, TestOutputTrue (
      [["touch"; "/new"];
       ["exists"; "/new"]])],
   "update file timestamps or create a new file",
   "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.");

  ("cat", (RString "content", [Pathname "path"]), 4, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutput (
      [["cat"; "/known-2"]], "abcdef\n")],
   "list the contents of a file",
   "\
Return the contents of the file named C<path>.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_read_file>
or C<guestfs_download> functions which have a more complex interface.");

  ("ll", (RString "listing", [Pathname "directory"]), 5, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'ls -l' command, which changes between F10 and F11.
        *)
   "list the files in a directory (long format)",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.");

  ("ls", (RStringList "listing", [Pathname "directory"]), 6, [],
   [InitBasicFS, Always, TestOutputList (
      [["touch"; "/new"];
       ["touch"; "/newer"];
       ["touch"; "/newest"];
       ["ls"; "/"]], ["lost+found"; "new"; "newer"; "newest"])],
   "list the files in a directory",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd).  The '.' and '..' entries are not returned, but
hidden files are shown.

This command is mostly useful for interactive sessions.  Programs
should probably use C<guestfs_readdir> instead.");

  ("list_devices", (RStringList "devices", []), 7, [],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["list_devices"]], ["/dev/sda"; "/dev/sdb"; "/dev/sdc"; "/dev/sdd"])],
   "list the block devices",
   "\
List all the block devices.

The full block device names are returned, eg. C</dev/sda>");

  ("list_partitions", (RStringList "partitions", []), 8, [],
   [InitBasicFS, Always, TestOutputListOfDevices (
      [["list_partitions"]], ["/dev/sda1"]);
    InitEmpty, Always, TestOutputListOfDevices (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["list_partitions"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "list the partitions",
   "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. C</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.");

  ("pvs", (RStringList "physvols", []), 9, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputListOfDevices (
      [["pvs"]], ["/dev/sda1"]);
    InitEmpty, Always, TestOutputListOfDevices (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["pvs"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.

This returns a list of just the device names that contain
PVs (eg. C</dev/sda2>).

See also C<guestfs_pvs_full>.");

  ("vgs", (RStringList "volgroups", []), 10, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["vgs"]], ["VG"]);
    InitEmpty, Always, TestOutputList (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
       ["vgcreate"; "VG2"; "/dev/sda3"];
       ["vgs"]], ["VG1"; "VG2"])],
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.

This returns a list of just the volume group names that were
detected (eg. C<VolGroup00>).

See also C<guestfs_vgs_full>.");

  ("lvs", (RStringList "logvols", []), 11, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["lvs"]], ["/dev/VG/LV"]);
    InitEmpty, Always, TestOutputList (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
       ["vgcreate"; "VG2"; "/dev/sda3"];
       ["lvcreate"; "LV1"; "VG1"; "50"];
       ["lvcreate"; "LV2"; "VG1"; "50"];
       ["lvcreate"; "LV3"; "VG2"; "50"];
       ["lvs"]], ["/dev/VG1/LV1"; "/dev/VG1/LV2"; "/dev/VG2/LV3"])],
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.

This returns a list of the logical volume device names
(eg. C</dev/VolGroup00/LogVol00>).

See also C<guestfs_lvs_full>.");

  ("pvs_full", (RStructList ("physvols", "lvm_pv"), []), 12, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields.");

  ("vgs_full", (RStructList ("volgroups", "lvm_vg"), []), 13, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields.");

  ("lvs_full", (RStructList ("logvols", "lvm_lv"), []), 14, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields.");

  ("read_lines", (RStringList "lines", [Pathname "path"]), 15, [],
   [InitISOFS, Always, TestOutputList (
      [["read_lines"; "/known-4"]], ["abc"; "def"; "ghi"]);
    InitISOFS, Always, TestOutputList (
      [["read_lines"; "/empty"]], [])],
   "read file as lines",
   "\
Return the contents of the file named C<path>.

The file contents are returned as a list of lines.  Trailing
C<LF> and C<CRLF> character sequences are I<not> returned.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of line).  For those you need to use the C<guestfs_read_file>
function which has a more complex interface.");

  ("aug_init", (RErr, [Pathname "root"; Int "flags"]), 16, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "create a new Augeas handle",
   "\
Create a new Augeas handle for editing configuration files.
If there was any previous Augeas handle associated with this
guestfs session, then it is closed.

You must call this before using any other C<guestfs_aug_*>
commands.

C<root> is the filesystem root.  C<root> must not be NULL,
use C</> instead.

The flags are the same as the flags defined in
E<lt>augeas.hE<gt>, the logical I<or> of the following
integers:

=over 4

=item C<AUG_SAVE_BACKUP> = 1

Keep the original file with a C<.augsave> extension.

=item C<AUG_SAVE_NEWFILE> = 2

Save changes into a file with extension C<.augnew>, and
do not overwrite original.  Overrides C<AUG_SAVE_BACKUP>.

=item C<AUG_TYPE_CHECK> = 4

Typecheck lenses (can be expensive).

=item C<AUG_NO_STDINC> = 8

Do not use standard load path for modules.

=item C<AUG_SAVE_NOOP> = 16

Make save a no-op, just record what would have been changed.

=item C<AUG_NO_LOAD> = 32

Do not load the tree in C<guestfs_aug_init>.

=back

To close the handle, you can call C<guestfs_aug_close>.

To find out more about Augeas, see L<http://augeas.net/>.");

  ("aug_close", (RErr, []), 26, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "close the current Augeas handle",
   "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions.");

  ("aug_defvar", (RInt "nrnodes", [String "name"; OptString "expr"]), 17, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "define an Augeas variable",
   "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset.");

  ("aug_defnode", (RStruct ("nrnodescreated", "int_bool"), [String "name"; String "expr"; String "val"]), 18, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "define an Augeas node",
   "\
Defines a variable C<name> whose value is the result of
evaluating C<expr>.

If C<expr> evaluates to an empty nodeset, a node is created,
equivalent to calling C<guestfs_aug_set> C<expr>, C<value>.
C<name> will be the nodeset containing that single node.

On success this returns a pair containing the
number of nodes in the nodeset, and a boolean flag
if a node was created.");

  ("aug_get", (RString "val", [String "augpath"]), 19, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "look up the value of an Augeas path",
   "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned.");

  ("aug_set", (RErr, [String "augpath"; String "val"]), 20, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "set Augeas path to value",
   "\
Set the value associated with C<path> to C<value>.");

  ("aug_insert", (RErr, [String "augpath"; String "label"; Bool "before"]), 21, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "insert a sibling Augeas node",
   "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain C</>, C<*> or end
with a bracketed index C<[N]>.");

  ("aug_rm", (RInt "nrnodes", [String "augpath"]), 22, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "remove an Augeas path",
   "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed.");

  ("aug_mv", (RErr, [String "src"; String "dest"]), 23, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "move Augeas node",
   "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists.");

  ("aug_match", (RStringList "matches", [String "augpath"]), 24, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "return Augeas nodes which match augpath",
   "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree.");

  ("aug_save", (RErr, []), 25, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "write all pending Augeas changes to disk",
   "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved.");

  ("aug_load", (RErr, []), 27, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "load files into the tree",
   "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details.");

  ("aug_ls", (RStringList "matches", [String "augpath"]), 28, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "list Augeas nodes under augpath",
   "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the resulting nodes into alphabetical order.");

  ("rm", (RErr, [Pathname "path"]), 29, [],
   [InitBasicFS, Always, TestRun
      [["touch"; "/new"];
       ["rm"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["rm"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["mkdir"; "/new"];
       ["rm"; "/new"]]],
   "remove a file",
   "\
Remove the single file C<path>.");

  ("rmdir", (RErr, [Pathname "path"]), 30, [],
   [InitBasicFS, Always, TestRun
      [["mkdir"; "/new"];
       ["rmdir"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["rmdir"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["touch"; "/new"];
       ["rmdir"; "/new"]]],
   "remove a directory",
   "\
Remove the single directory C<path>.");

  ("rm_rf", (RErr, [Pathname "path"]), 31, [],
   [InitBasicFS, Always, TestOutputFalse
      [["mkdir"; "/new"];
       ["mkdir"; "/new/foo"];
       ["touch"; "/new/foo/bar"];
       ["rm_rf"; "/new"];
       ["exists"; "/new"]]],
   "remove a file or directory recursively",
   "\
Remove the file or directory C<path>, recursively removing the
contents if its a directory.  This is like the C<rm -rf> shell
command.");

  ("mkdir", (RErr, [Pathname "path"]), 32, [],
   [InitBasicFS, Always, TestOutputTrue
      [["mkdir"; "/new"];
       ["is_dir"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["mkdir"; "/new/foo/bar"]]],
   "create a directory",
   "\
Create a directory named C<path>.");

  ("mkdir_p", (RErr, [Pathname "path"]), 33, [],
   [InitBasicFS, Always, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new/foo/bar"]];
    InitBasicFS, Always, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new/foo"]];
    InitBasicFS, Always, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new"]];
    (* Regression tests for RHBZ#503133: *)
    InitBasicFS, Always, TestRun
      [["mkdir"; "/new"];
       ["mkdir_p"; "/new"]];
    InitBasicFS, Always, TestLastFail
      [["touch"; "/new"];
       ["mkdir_p"; "/new"]]],
   "create a directory and parents",
   "\
Create a directory named C<path>, creating any parent directories
as necessary.  This is like the C<mkdir -p> shell command.");

  ("chmod", (RErr, [Int "mode"; Pathname "path"]), 34, [],
   [], (* XXX Need stat command to test *)
   "change file mode",
   "\
Change the mode (permissions) of C<path> to C<mode>.  Only
numeric modes are supported.");

  ("chown", (RErr, [Int "owner"; Int "group"; Pathname "path"]), 35, [],
   [], (* XXX Need stat command to test *)
   "change file owner and group",
   "\
Change the file owner to C<owner> and group to C<group>.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy).");

  ("exists", (RBool "existsflag", [Pathname "path"]), 36, [],
   [InitISOFS, Always, TestOutputTrue (
      [["exists"; "/empty"]]);
    InitISOFS, Always, TestOutputTrue (
      [["exists"; "/directory"]])],
   "test if file or directory exists",
   "\
This returns C<true> if and only if there is a file, directory
(or anything) with the given C<path> name.

See also C<guestfs_is_file>, C<guestfs_is_dir>, C<guestfs_stat>.");

  ("is_file", (RBool "fileflag", [Pathname "path"]), 37, [],
   [InitISOFS, Always, TestOutputTrue (
      [["is_file"; "/known-1"]]);
    InitISOFS, Always, TestOutputFalse (
      [["is_file"; "/directory"]])],
   "test if file exists",
   "\
This returns C<true> if and only if there is a file
with the given C<path> name.  Note that it returns false for
other objects like directories.

See also C<guestfs_stat>.");

  ("is_dir", (RBool "dirflag", [Pathname "path"]), 38, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_dir"; "/known-3"]]);
    InitISOFS, Always, TestOutputTrue (
      [["is_dir"; "/directory"]])],
   "test if file exists",
   "\
This returns C<true> if and only if there is a directory
with the given C<path> name.  Note that it returns false for
other objects like files.

See also C<guestfs_stat>.");

  ("pvcreate", (RErr, [Device "device"]), 39, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["pvs"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "create an LVM physical volume",
   "\
This creates an LVM physical volume on the named C<device>,
where C<device> should usually be a partition name such
as C</dev/sda1>.");

  ("vgcreate", (RErr, [String "volgroup"; DeviceList "physvols"]), 40, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
       ["vgcreate"; "VG2"; "/dev/sda3"];
       ["vgs"]], ["VG1"; "VG2"])],
   "create an LVM volume group",
   "\
This creates an LVM volume group called C<volgroup>
from the non-empty list of physical volumes C<physvols>.");

  ("lvcreate", (RErr, [String "logvol"; String "volgroup"; Int "mbytes"]), 41, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
       ["vgcreate"; "VG2"; "/dev/sda3"];
       ["lvcreate"; "LV1"; "VG1"; "50"];
       ["lvcreate"; "LV2"; "VG1"; "50"];
       ["lvcreate"; "LV3"; "VG2"; "50"];
       ["lvcreate"; "LV4"; "VG2"; "50"];
       ["lvcreate"; "LV5"; "VG2"; "50"];
       ["lvs"]],
      ["/dev/VG1/LV1"; "/dev/VG1/LV2";
       "/dev/VG2/LV3"; "/dev/VG2/LV4"; "/dev/VG2/LV5"])],
   "create an LVM volume group",
   "\
This creates an LVM volume group called C<logvol>
on the volume group C<volgroup>, with C<size> megabytes.");

  ("mkfs", (RErr, [String "fstype"; Device "device"]), 42, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "make a filesystem",
   "\
This creates a filesystem on C<device> (usually a partition
or LVM logical volume).  The filesystem type is C<fstype>, for
example C<ext3>.");

  ("sfdisk", (RErr, [Device "device";
                     Int "cyls"; Int "heads"; Int "sectors";
                     StringList "lines"]), 43, [DangerWillRobinson],
   [],
   "create partitions on a block device",
   "\
This is a direct interface to the L<sfdisk(8)> program for creating
partitions on block devices.

C<device> should be a block device, for example C</dev/sda>.

C<cyls>, C<heads> and C<sectors> are the number of cylinders, heads
and sectors on the device, which are passed directly to sfdisk as
the I<-C>, I<-H> and I<-S> parameters.  If you pass C<0> for any
of these, then the corresponding parameter is omitted.  Usually for
'large' disks, you can just pass C<0> for these, but for small
(floppy-sized) disks, sfdisk (or rather, the kernel) cannot work
out the right geometry and you will need to tell it.

C<lines> is a list of lines that we feed to C<sfdisk>.  For more
information refer to the L<sfdisk(8)> manpage.

To create a single partition occupying the whole disk, you would
pass C<lines> as a single element list, when the single element being
the string C<,> (comma).

See also: C<guestfs_sfdisk_l>, C<guestfs_sfdisk_N>,
C<guestfs_part_init>");

  ("write_file", (RErr, [Pathname "path"; String "content"; Int "size"]), 44, [ProtocolLimitWarning],
   [InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents");
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "\nnew file contents\n"; "0"];
       ["cat"; "/new"]], "\nnew file contents\n");
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "\n\n"; "0"];
       ["cat"; "/new"]], "\n\n");
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; ""; "0"];
       ["cat"; "/new"]], "");
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "\n\n\n"; "0"];
       ["cat"; "/new"]], "\n\n\n");
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "\n"; "0"];
       ["cat"; "/new"]], "\n")],
   "create a file",
   "\
This call creates a file called C<path>.  The contents of the
file is the string C<content> (which can contain any 8 bit data),
with length C<size>.

As a special case, if C<size> is C<0>
then the length is calculated using C<strlen> (so in this case
the content cannot contain embedded ASCII NULs).

I<NB.> Owing to a bug, writing content containing ASCII NUL
characters does I<not> work, even if the length is specified.
We hope to resolve this bug in a future version.  In the meantime
use C<guestfs_upload>.");

  ("umount", (RErr, [String "pathordevice"]), 45, [FishAlias "unmount"],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["mounts"]], ["/dev/sda1"]);
    InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["umount"; "/"];
       ["mounts"]], [])],
   "unmount a filesystem",
   "\
This unmounts the given filesystem.  The filesystem may be
specified either by its mountpoint (path) or the device which
contains the filesystem.");

  ("mounts", (RStringList "devices", []), 46, [],
   [InitBasicFS, Always, TestOutputListOfDevices (
      [["mounts"]], ["/dev/sda1"])],
   "show mounted filesystems",
   "\
This returns the list of currently mounted filesystems.  It returns
the list of devices (eg. C</dev/sda1>, C</dev/VG/LV>).

Some internal mounts are not shown.

See also: C<guestfs_mountpoints>");

  ("umount_all", (RErr, []), 47, [FishAlias "unmount-all"],
   [InitBasicFS, Always, TestOutputList (
      [["umount_all"];
       ["mounts"]], []);
    (* check that umount_all can unmount nested mounts correctly: *)
    InitEmpty, Always, TestOutputList (
      [["sfdiskM"; "/dev/sda"; ",100 ,200 ,"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mkfs"; "ext2"; "/dev/sda2"];
       ["mkfs"; "ext2"; "/dev/sda3"];
       ["mount"; "/dev/sda1"; "/"];
       ["mkdir"; "/mp1"];
       ["mount"; "/dev/sda2"; "/mp1"];
       ["mkdir"; "/mp1/mp2"];
       ["mount"; "/dev/sda3"; "/mp1/mp2"];
       ["mkdir"; "/mp1/mp2/mp3"];
       ["umount_all"];
       ["mounts"]], [])],
   "unmount all filesystems",
   "\
This unmounts all mounted filesystems.

Some internal mounts are not unmounted by this call.");

  ("lvm_remove_all", (RErr, []), 48, [DangerWillRobinson; Optional "lvm2"],
   [],
   "remove all LVM LVs, VGs and PVs",
   "\
This command removes all LVM logical volumes, volume groups
and physical volumes.");

  ("file", (RString "description", [Dev_or_Path "path"]), 49, [],
   [InitISOFS, Always, TestOutput (
      [["file"; "/empty"]], "empty");
    InitISOFS, Always, TestOutput (
      [["file"; "/known-1"]], "ASCII text");
    InitISOFS, Always, TestLastFail (
      [["file"; "/notexists"]])],
   "determine file type",
   "\
This call uses the standard L<file(1)> command to determine
the type or contents of the file.  This also works on devices,
for example to find out whether a partition contains a filesystem.

This call will also transparently look inside various types
of compressed file.

The exact command which runs is C<file -zbsL path>.  Note in
particular that the filename is not prepended to the output
(the C<-b> option).");

  ("command", (RString "output", [StringList "arguments"]), 50, [ProtocolLimitWarning],
   [InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 1"]], "Result1");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 2"]], "Result2\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 3"]], "\nResult3");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 4"]], "\nResult4\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 5"]], "\nResult5\n\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 6"]], "\n\nResult6\n\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 7"]], "");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 8"]], "\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 9"]], "\n\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 10"]], "Result10-1\nResult10-2\n");
    InitBasicFS, Always, TestOutput (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command 11"]], "Result11-1\nResult11-2");
    InitBasicFS, Always, TestLastFail (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command"; "/test-command"]])],
   "run a command from the guest filesystem",
   "\
This call runs a command from the guest filesystem.  The
filesystem must be mounted, and must contain a compatible
operating system (ie. something Linux, with the same
or compatible processor architecture).

The single parameter is an argv-style list of arguments.
The first element is the name of the program to run.
Subsequent elements are parameters.  The list must be
non-empty (ie. must contain a program name).  Note that
the command runs directly, and is I<not> invoked via
the shell (see C<guestfs_sh>).

The return value is anything printed to I<stdout> by
the command.

If the command returns a non-zero exit status, then
this function returns an error message.  The error message
string is the content of I<stderr> from the command.

The C<$PATH> environment variable will contain at least
C</usr/bin> and C</bin>.  If you require a program from
another location, you should provide the full path in the
first parameter.

Shared libraries and data files required by the program
must be available on filesystems which are mounted in the
correct places.  It is the caller's responsibility to ensure
all filesystems that are needed are mounted at the right
locations.");

  ("command_lines", (RStringList "lines", [StringList "arguments"]), 51, [ProtocolLimitWarning],
   [InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 1"]], ["Result1"]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 2"]], ["Result2"]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 3"]], ["";"Result3"]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 4"]], ["";"Result4"]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 5"]], ["";"Result5";""]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 6"]], ["";"";"Result6";""]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 7"]], []);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 8"]], [""]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 9"]], ["";""]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 10"]], ["Result10-1";"Result10-2"]);
    InitBasicFS, Always, TestOutputList (
      [["upload"; "test-command"; "/test-command"];
       ["chmod"; "0o755"; "/test-command"];
       ["command_lines"; "/test-command 11"]], ["Result11-1";"Result11-2"])],
   "run a command, returning lines",
   "\
This is the same as C<guestfs_command>, but splits the
result into a list of lines.

See also: C<guestfs_sh_lines>");

  ("stat", (RStruct ("statbuf", "stat"), [Pathname "path"]), 52, [],
   [InitISOFS, Always, TestOutputStruct (
      [["stat"; "/empty"]], [CompareWithInt ("size", 0)])],
   "get file information",
   "\
Returns file information for the given C<path>.

This is the same as the C<stat(2)> system call.");

  ("lstat", (RStruct ("statbuf", "stat"), [Pathname "path"]), 53, [],
   [InitISOFS, Always, TestOutputStruct (
      [["lstat"; "/empty"]], [CompareWithInt ("size", 0)])],
   "get file information for a symbolic link",
   "\
Returns file information for the given C<path>.

This is the same as C<guestfs_stat> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the C<lstat(2)> system call.");

  ("statvfs", (RStruct ("statbuf", "statvfs"), [Pathname "path"]), 54, [],
   [InitISOFS, Always, TestOutputStruct (
      [["statvfs"; "/"]], [CompareWithInt ("namemax", 255)])],
   "get file system statistics",
   "\
Returns file system statistics for any mounted file system.
C<path> should be a file or directory in the mounted file system
(typically it is the mount point itself, but it doesn't need to be).

This is the same as the C<statvfs(2)> system call.");

  ("tune2fs_l", (RHashtable "superblock", [Device "device"]), 55, [],
   [], (* XXX test *)
   "get ext2/ext3/ext4 superblock details",
   "\
This returns the contents of the ext2, ext3 or ext4 filesystem
superblock on C<device>.

It is the same as running C<tune2fs -l device>.  See L<tune2fs(8)>
manpage for more details.  The list of fields returned isn't
clearly defined, and depends on both the version of C<tune2fs>
that libguestfs was built against, and the filesystem itself.");

  ("blockdev_setro", (RErr, [Device "device"]), 56, [],
   [InitEmpty, Always, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-only",
   "\
Sets the block device named C<device> to read-only.

This uses the L<blockdev(8)> command.");

  ("blockdev_setrw", (RErr, [Device "device"]), 57, [],
   [InitEmpty, Always, TestOutputFalse (
      [["blockdev_setrw"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-write",
   "\
Sets the block device named C<device> to read-write.

This uses the L<blockdev(8)> command.");

  ("blockdev_getro", (RBool "ro", [Device "device"]), 58, [],
   [InitEmpty, Always, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "is block device set to read-only",
   "\
Returns a boolean indicating if the block device is read-only
(true if read-only, false if not).

This uses the L<blockdev(8)> command.");

  ("blockdev_getss", (RInt "sectorsize", [Device "device"]), 59, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getss"; "/dev/sda"]], 512)],
   "get sectorsize of block device",
   "\
This returns the size of sectors on a block device.
Usually 512, but can be larger for modern devices.

(Note, this is not the size in sectors, use C<guestfs_blockdev_getsz>
for that).

This uses the L<blockdev(8)> command.");

  ("blockdev_getbsz", (RInt "blocksize", [Device "device"]), 60, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getbsz"; "/dev/sda"]], 4096)],
   "get blocksize of block device",
   "\
This returns the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_setbsz", (RErr, [Device "device"; Int "blocksize"]), 61, [],
   [], (* XXX test *)
   "set blocksize of block device",
   "\
This sets the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_getsz", (RInt64 "sizeinsectors", [Device "device"]), 62, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getsz"; "/dev/sda"]], 1024000)],
   "get total size of device in 512-byte sectors",
   "\
This returns the size of the device in units of 512-byte sectors
(even if the sectorsize isn't 512 bytes ... weird).

See also C<guestfs_blockdev_getss> for the real sector size of
the device, and C<guestfs_blockdev_getsize64> for the more
useful I<size in bytes>.

This uses the L<blockdev(8)> command.");

  ("blockdev_getsize64", (RInt64 "sizeinbytes", [Device "device"]), 63, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getsize64"; "/dev/sda"]], 524288000)],
   "get total size of device in bytes",
   "\
This returns the size of the device in bytes.

See also C<guestfs_blockdev_getsz>.

This uses the L<blockdev(8)> command.");

  ("blockdev_flushbufs", (RErr, [Device "device"]), 64, [],
   [InitEmpty, Always, TestRun
      [["blockdev_flushbufs"; "/dev/sda"]]],
   "flush device buffers",
   "\
This tells the kernel to flush internal buffers associated
with C<device>.

This uses the L<blockdev(8)> command.");

  ("blockdev_rereadpt", (RErr, [Device "device"]), 65, [],
   [InitEmpty, Always, TestRun
      [["blockdev_rereadpt"; "/dev/sda"]]],
   "reread partition table",
   "\
Reread the partition table on C<device>.

This uses the L<blockdev(8)> command.");

  ("upload", (RErr, [FileIn "filename"; Dev_or_Path "remotefilename"]), 66, [],
   [InitBasicFS, Always, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
      [["upload"; "../COPYING.LIB"; "/COPYING.LIB"];
       ["checksum"; "md5"; "/COPYING.LIB"]],
      Digest.to_hex (Digest.file "COPYING.LIB"))],
   "upload a file from the local machine",
   "\
Upload local file C<filename> to C<remotefilename> on the
filesystem.

C<filename> can also be a named pipe.

See also C<guestfs_download>.");

  ("download", (RErr, [Dev_or_Path "remotefilename"; FileOut "filename"]), 67, [],
   [InitBasicFS, Always, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
      [["upload"; "../COPYING.LIB"; "/COPYING.LIB"];
       ["download"; "/COPYING.LIB"; "testdownload.tmp"];
       ["upload"; "testdownload.tmp"; "/upload"];
       ["checksum"; "md5"; "/upload"]],
      Digest.to_hex (Digest.file "COPYING.LIB"))],
   "download a file to the local machine",
   "\
Download file C<remotefilename> and save it as C<filename>
on the local machine.

C<filename> can also be a named pipe.

See also C<guestfs_upload>, C<guestfs_cat>.");

  ("checksum", (RString "checksum", [String "csumtype"; Pathname "path"]), 68, [],
   [InitISOFS, Always, TestOutput (
      [["checksum"; "crc"; "/known-3"]], "2891671662");
    InitISOFS, Always, TestLastFail (
      [["checksum"; "crc"; "/notexists"]]);
    InitISOFS, Always, TestOutput (
      [["checksum"; "md5"; "/known-3"]], "46d6ca27ee07cdc6fa99c2e138cc522c");
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha1"; "/known-3"]], "b7ebccc3ee418311091c3eda0a45b83c0a770f15");
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha224"; "/known-3"]], "d2cd1774b28f3659c14116be0a6dc2bb5c4b350ce9cd5defac707741");
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha256"; "/known-3"]], "75bb71b90cd20cb13f86d2bea8dad63ac7194e7517c3b52b8d06ff52d3487d30");
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha384"; "/known-3"]], "5fa7883430f357b5d7b7271d3a1d2872b51d73cba72731de6863d3dea55f30646af2799bef44d5ea776a5ec7941ac640");
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha512"; "/known-3"]], "2794062c328c6b216dca90443b7f7134c5f40e56bd0ed7853123275a09982a6f992e6ca682f9d2fba34a4c5e870d8fe077694ff831e3032a004ee077e00603f6")],
   "compute MD5, SHAx or CRC checksum of file",
   "\
This call computes the MD5, SHAx or CRC checksum of the
file named C<path>.

The type of checksum to compute is given by the C<csumtype>
parameter which must have one of the following values:

=over 4

=item C<crc>

Compute the cyclic redundancy check (CRC) specified by POSIX
for the C<cksum> command.

=item C<md5>

Compute the MD5 hash (using the C<md5sum> program).

=item C<sha1>

Compute the SHA1 hash (using the C<sha1sum> program).

=item C<sha224>

Compute the SHA224 hash (using the C<sha224sum> program).

=item C<sha256>

Compute the SHA256 hash (using the C<sha256sum> program).

=item C<sha384>

Compute the SHA384 hash (using the C<sha384sum> program).

=item C<sha512>

Compute the SHA512 hash (using the C<sha512sum> program).

=back

The checksum is returned as a printable string.");

  ("tar_in", (RErr, [FileIn "tarfile"; String "directory"]), 69, [],
   [InitBasicFS, Always, TestOutput (
      [["tar_in"; "../images/helloworld.tar"; "/"];
       ["cat"; "/hello"]], "hello\n")],
   "unpack tarfile to directory",
   "\
This command uploads and unpacks local file C<tarfile> (an
I<uncompressed> tar file) into C<directory>.

To upload a compressed tarball, use C<guestfs_tgz_in>.");

  ("tar_out", (RErr, [String "directory"; FileOut "tarfile"]), 70, [],
   [],
   "pack directory into tarfile",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarfile>.

To download a compressed tarball, use C<guestfs_tgz_out>.");

  ("tgz_in", (RErr, [FileIn "tarball"; String "directory"]), 71, [],
   [InitBasicFS, Always, TestOutput (
      [["tgz_in"; "../images/helloworld.tar.gz"; "/"];
       ["cat"; "/hello"]], "hello\n")],
   "unpack compressed tarball to directory",
   "\
This command uploads and unpacks local file C<tarball> (a
I<gzip compressed> tar file) into C<directory>.

To upload an uncompressed tarball, use C<guestfs_tar_in>.");

  ("tgz_out", (RErr, [Pathname "directory"; FileOut "tarball"]), 72, [],
   [],
   "pack directory into compressed tarball",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarball>.

To download an uncompressed tarball, use C<guestfs_tar_out>.");

  ("mount_ro", (RErr, [Device "device"; String "mountpoint"]), 73, [],
   [InitBasicFS, Always, TestLastFail (
      [["umount"; "/"];
       ["mount_ro"; "/dev/sda1"; "/"];
       ["touch"; "/new"]]);
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/new"; "data"; "0"];
       ["umount"; "/"];
       ["mount_ro"; "/dev/sda1"; "/"];
       ["cat"; "/new"]], "data")],
   "mount a guest disk, read-only",
   "\
This is the same as the C<guestfs_mount> command, but it
mounts the filesystem with the read-only (I<-o ro>) flag.");

  ("mount_options", (RErr, [String "options"; Device "device"; String "mountpoint"]), 74, [],
   [],
   "mount a guest disk with mount options",
   "\
This is the same as the C<guestfs_mount> command, but it
allows you to set the mount options as for the
L<mount(8)> I<-o> flag.");

  ("mount_vfs", (RErr, [String "options"; String "vfstype"; Device "device"; String "mountpoint"]), 75, [],
   [],
   "mount a guest disk with mount options and vfstype",
   "\
This is the same as the C<guestfs_mount> command, but it
allows you to set both the mount options and the vfstype
as for the L<mount(8)> I<-o> and I<-t> flags.");

  ("debug", (RString "result", [String "subcmd"; StringList "extraargs"]), 76, [],
   [],
   "debugging and internals",
   "\
The C<guestfs_debug> command exposes some internals of
C<guestfsd> (the guestfs daemon) that runs inside the
qemu subprocess.

There is no comprehensive help for this command.  You have
to look at the file C<daemon/debug.c> in the libguestfs source
to find out what you can do.");

  ("lvremove", (RErr, [Device "device"]), 77, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["lvremove"; "/dev/VG/LV1"];
       ["lvs"]], ["/dev/VG/LV2"]);
    InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["lvremove"; "/dev/VG"];
       ["lvs"]], []);
    InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["lvremove"; "/dev/VG"];
       ["vgs"]], ["VG"])],
   "remove an LVM logical volume",
   "\
Remove an LVM logical volume C<device>, where C<device> is
the path to the LV, such as C</dev/VG/LV>.

You can also remove all LVs in a volume group by specifying
the VG name, C</dev/VG>.");

  ("vgremove", (RErr, [String "vgname"]), 78, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["vgremove"; "VG"];
       ["lvs"]], []);
    InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["vgremove"; "VG"];
       ["vgs"]], [])],
   "remove an LVM volume group",
   "\
Remove an LVM volume group C<vgname>, (for example C<VG>).

This also forcibly removes all logical volumes in the volume
group (if any).");

  ("pvremove", (RErr, [Device "device"]), 79, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["vgremove"; "VG"];
       ["pvremove"; "/dev/sda1"];
       ["lvs"]], []);
    InitEmpty, Always, TestOutputListOfDevices (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["vgremove"; "VG"];
       ["pvremove"; "/dev/sda1"];
       ["vgs"]], []);
    InitEmpty, Always, TestOutputListOfDevices (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV1"; "VG"; "50"];
       ["lvcreate"; "LV2"; "VG"; "50"];
       ["vgremove"; "VG"];
       ["pvremove"; "/dev/sda1"];
       ["pvs"]], [])],
   "remove an LVM physical volume",
   "\
This wipes a physical volume C<device> so that LVM will no longer
recognise it.

The implementation uses the C<pvremove> command which refuses to
wipe physical volumes that contain any volume groups, so you have
to remove those first.");

  ("set_e2label", (RErr, [Device "device"; String "label"]), 80, [],
   [InitBasicFS, Always, TestOutput (
      [["set_e2label"; "/dev/sda1"; "testlabel"];
       ["get_e2label"; "/dev/sda1"]], "testlabel")],
   "set the ext2/3/4 filesystem label",
   "\
This sets the ext2/3/4 filesystem label of the filesystem on
C<device> to C<label>.  Filesystem labels are limited to
16 characters.

You can use either C<guestfs_tune2fs_l> or C<guestfs_get_e2label>
to return the existing label on a filesystem.");

  ("get_e2label", (RString "label", [Device "device"]), 81, [],
   [],
   "get the ext2/3/4 filesystem label",
   "\
This returns the ext2/3/4 filesystem label of the filesystem on
C<device>.");

  ("set_e2uuid", (RErr, [Device "device"; String "uuid"]), 82, [],
   (let uuid = uuidgen () in
    [InitBasicFS, Always, TestOutput (
       [["set_e2uuid"; "/dev/sda1"; uuid];
        ["get_e2uuid"; "/dev/sda1"]], uuid);
     InitBasicFS, Always, TestOutput (
       [["set_e2uuid"; "/dev/sda1"; "clear"];
        ["get_e2uuid"; "/dev/sda1"]], "");
     (* We can't predict what UUIDs will be, so just check the commands run. *)
     InitBasicFS, Always, TestRun (
       [["set_e2uuid"; "/dev/sda1"; "random"]]);
     InitBasicFS, Always, TestRun (
       [["set_e2uuid"; "/dev/sda1"; "time"]])]),
   "set the ext2/3/4 filesystem UUID",
   "\
This sets the ext2/3/4 filesystem UUID of the filesystem on
C<device> to C<uuid>.  The format of the UUID and alternatives
such as C<clear>, C<random> and C<time> are described in the
L<tune2fs(8)> manpage.

You can use either C<guestfs_tune2fs_l> or C<guestfs_get_e2uuid>
to return the existing UUID of a filesystem.");

  ("get_e2uuid", (RString "uuid", [Device "device"]), 83, [],
   [],
   "get the ext2/3/4 filesystem UUID",
   "\
This returns the ext2/3/4 filesystem UUID of the filesystem on
C<device>.");

  ("fsck", (RInt "status", [String "fstype"; Device "device"]), 84, [],
   [InitBasicFS, Always, TestOutputInt (
      [["umount"; "/dev/sda1"];
       ["fsck"; "ext2"; "/dev/sda1"]], 0);
    InitBasicFS, Always, TestOutputInt (
      [["umount"; "/dev/sda1"];
       ["zero"; "/dev/sda1"];
       ["fsck"; "ext2"; "/dev/sda1"]], 8)],
   "run the filesystem checker",
   "\
This runs the filesystem checker (fsck) on C<device> which
should have filesystem type C<fstype>.

The returned integer is the status.  See L<fsck(8)> for the
list of status codes from C<fsck>.

Notes:

=over 4

=item *

Multiple status codes can be summed together.

=item *

A non-zero return code can mean \"success\", for example if
errors have been corrected on the filesystem.

=item *

Checking or repairing NTFS volumes is not supported
(by linux-ntfs).

=back

This command is entirely equivalent to running C<fsck -a -t fstype device>.");

  ("zero", (RErr, [Device "device"]), 85, [],
   [InitBasicFS, Always, TestOutput (
      [["umount"; "/dev/sda1"];
       ["zero"; "/dev/sda1"];
       ["file"; "/dev/sda1"]], "data")],
   "write zeroes to the device",
   "\
This command writes zeroes over the first few blocks of C<device>.

How many blocks are zeroed isn't specified (but it's I<not> enough
to securely wipe the device).  It should be sufficient to remove
any partition tables, filesystem superblocks and so on.

See also: C<guestfs_scrub_device>.");

  ("grub_install", (RErr, [Pathname "root"; Device "device"]), 86, [],
   (* Test disabled because grub-install incompatible with virtio-blk driver.
    * See also: https://bugzilla.redhat.com/show_bug.cgi?id=479760
    *)
   [InitBasicFS, Disabled, TestOutputTrue (
      [["grub_install"; "/"; "/dev/sda1"];
       ["is_dir"; "/boot"]])],
   "install GRUB",
   "\
This command installs GRUB (the Grand Unified Bootloader) on
C<device>, with the root directory being C<root>.");

  ("cp", (RErr, [Pathname "src"; Pathname "dest"]), 87, [],
   [InitBasicFS, Always, TestOutput (
      [["write_file"; "/old"; "file content"; "0"];
       ["cp"; "/old"; "/new"];
       ["cat"; "/new"]], "file content");
    InitBasicFS, Always, TestOutputTrue (
      [["write_file"; "/old"; "file content"; "0"];
       ["cp"; "/old"; "/new"];
       ["is_file"; "/old"]]);
    InitBasicFS, Always, TestOutput (
      [["write_file"; "/old"; "file content"; "0"];
       ["mkdir"; "/dir"];
       ["cp"; "/old"; "/dir/new"];
       ["cat"; "/dir/new"]], "file content")],
   "copy a file",
   "\
This copies a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory.");

  ("cp_a", (RErr, [Pathname "src"; Pathname "dest"]), 88, [],
   [InitBasicFS, Always, TestOutput (
      [["mkdir"; "/olddir"];
       ["mkdir"; "/newdir"];
       ["write_file"; "/olddir/file"; "file content"; "0"];
       ["cp_a"; "/olddir"; "/newdir"];
       ["cat"; "/newdir/olddir/file"]], "file content")],
   "copy a file or directory recursively",
   "\
This copies a file or directory from C<src> to C<dest>
recursively using the C<cp -a> command.");

  ("mv", (RErr, [Pathname "src"; Pathname "dest"]), 89, [],
   [InitBasicFS, Always, TestOutput (
      [["write_file"; "/old"; "file content"; "0"];
       ["mv"; "/old"; "/new"];
       ["cat"; "/new"]], "file content");
    InitBasicFS, Always, TestOutputFalse (
      [["write_file"; "/old"; "file content"; "0"];
       ["mv"; "/old"; "/new"];
       ["is_file"; "/old"]])],
   "move a file",
   "\
This moves a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory.");

  ("drop_caches", (RErr, [Int "whattodrop"]), 90, [],
   [InitEmpty, Always, TestRun (
      [["drop_caches"; "3"]])],
   "drop kernel page cache, dentries and inodes",
   "\
This instructs the guest kernel to drop its page cache,
and/or dentries and inode caches.  The parameter C<whattodrop>
tells the kernel what precisely to drop, see
L<http://linux-mm.org/Drop_Caches>

Setting C<whattodrop> to 3 should drop everything.

This automatically calls L<sync(2)> before the operation,
so that the maximum guest memory is freed.");

  ("dmesg", (RString "kmsgs", []), 91, [],
   [InitEmpty, Always, TestRun (
      [["dmesg"]])],
   "return kernel messages",
   "\
This returns the kernel messages (C<dmesg> output) from
the guest kernel.  This is sometimes useful for extended
debugging of problems.

Another way to get the same information is to enable
verbose messages with C<guestfs_set_verbose> or by setting
the environment variable C<LIBGUESTFS_DEBUG=1> before
running the program.");

  ("ping_daemon", (RErr, []), 92, [],
   [InitEmpty, Always, TestRun (
      [["ping_daemon"]])],
   "ping the guest daemon",
   "\
This is a test probe into the guestfs daemon running inside
the qemu subprocess.  Calling this function checks that the
daemon responds to the ping message, without affecting the daemon
or attached block device(s) in any other way.");

  ("equal", (RBool "equality", [Pathname "file1"; Pathname "file2"]), 93, [],
   [InitBasicFS, Always, TestOutputTrue (
      [["write_file"; "/file1"; "contents of a file"; "0"];
       ["cp"; "/file1"; "/file2"];
       ["equal"; "/file1"; "/file2"]]);
    InitBasicFS, Always, TestOutputFalse (
      [["write_file"; "/file1"; "contents of a file"; "0"];
       ["write_file"; "/file2"; "contents of another file"; "0"];
       ["equal"; "/file1"; "/file2"]]);
    InitBasicFS, Always, TestLastFail (
      [["equal"; "/file1"; "/file2"]])],
   "test if two files have equal contents",
   "\
This compares the two files C<file1> and C<file2> and returns
true if their content is exactly equal, or false otherwise.

The external L<cmp(1)> program is used for the comparison.");

  ("strings", (RStringList "stringsout", [Pathname "path"]), 94, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["strings"; "/known-5"]], ["abcdefghi"; "jklmnopqr"]);
    InitISOFS, Always, TestOutputList (
      [["strings"; "/empty"]], [])],
   "print the printable strings in a file",
   "\
This runs the L<strings(1)> command on a file and returns
the list of printable strings found.");

  ("strings_e", (RStringList "stringsout", [String "encoding"; Pathname "path"]), 95, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["strings_e"; "b"; "/known-5"]], []);
    InitBasicFS, Disabled, TestOutputList (
      [["write_file"; "/new"; "\000h\000e\000l\000l\000o\000\n\000w\000o\000r\000l\000d\000\n"; "24"];
       ["strings_e"; "b"; "/new"]], ["hello"; "world"])],
   "print the printable strings in a file",
   "\
This is like the C<guestfs_strings> command, but allows you to
specify the encoding.

See the L<strings(1)> manpage for the full list of encodings.

Commonly useful encodings are C<l> (lower case L) which will
show strings inside Windows/x86 files.

The returned strings are transcoded to UTF-8.");

  ("hexdump", (RString "dump", [Pathname "path"]), 96, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutput (
      [["hexdump"; "/known-4"]], "00000000  61 62 63 0a 64 65 66 0a  67 68 69                 |abc.def.ghi|\n0000000b\n");
    (* Test for RHBZ#501888c2 regression which caused large hexdump
     * commands to segfault.
     *)
    InitISOFS, Always, TestRun (
      [["hexdump"; "/100krandom"]])],
   "dump a file in hexadecimal",
   "\
This runs C<hexdump -C> on the given C<path>.  The result is
the human-readable, canonical hex dump of the file.");

  ("zerofree", (RErr, [Device "device"]), 97, [Optional "zerofree"],
   [InitNone, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext3"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write_file"; "/new"; "test file"; "0"];
       ["umount"; "/dev/sda1"];
       ["zerofree"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["cat"; "/new"]], "test file")],
   "zero unused inodes and disk blocks on ext2/3 filesystem",
   "\
This runs the I<zerofree> program on C<device>.  This program
claims to zero unused inodes and disk blocks on an ext2/3
filesystem, thus making it possible to compress the filesystem
more effectively.

You should B<not> run this program if the filesystem is
mounted.

It is possible that using this program can damage the filesystem
or data on the filesystem.");

  ("pvresize", (RErr, [Device "device"]), 98, [Optional "lvm2"],
   [],
   "resize an LVM physical volume",
   "\
This resizes (expands or shrinks) an existing LVM physical
volume to match the new size of the underlying device.");

  ("sfdisk_N", (RErr, [Device "device"; Int "partnum";
                       Int "cyls"; Int "heads"; Int "sectors";
                       String "line"]), 99, [DangerWillRobinson],
   [],
   "modify a single partition on a block device",
   "\
This runs L<sfdisk(8)> option to modify just the single
partition C<n> (note: C<n> counts from 1).

For other parameters, see C<guestfs_sfdisk>.  You should usually
pass C<0> for the cyls/heads/sectors parameters.

See also: C<guestfs_part_add>");

  ("sfdisk_l", (RString "partitions", [Device "device"]), 100, [],
   [],
   "display the partition table",
   "\
This displays the partition table on C<device>, in the
human-readable output of the L<sfdisk(8)> command.  It is
not intended to be parsed.

See also: C<guestfs_part_list>");

  ("sfdisk_kernel_geometry", (RString "partitions", [Device "device"]), 101, [],
   [],
   "display the kernel geometry",
   "\
This displays the kernel's idea of the geometry of C<device>.

The result is in human-readable format, and not designed to
be parsed.");

  ("sfdisk_disk_geometry", (RString "partitions", [Device "device"]), 102, [],
   [],
   "display the disk geometry from the partition table",
   "\
This displays the disk geometry of C<device> read from the
partition table.  Especially in the case where the underlying
block device has been resized, this can be different from the
kernel's idea of the geometry (see C<guestfs_sfdisk_kernel_geometry>).

The result is in human-readable format, and not designed to
be parsed.");

  ("vg_activate_all", (RErr, [Bool "activate"]), 103, [Optional "lvm2"],
   [],
   "activate or deactivate all volume groups",
   "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in all volume groups.
If activated, then they are made known to the
kernel, ie. they appear as C</dev/mapper> devices.  If deactivated,
then those devices disappear.

This command is the same as running C<vgchange -a y|n>");

  ("vg_activate", (RErr, [Bool "activate"; StringList "volgroups"]), 104, [Optional "lvm2"],
   [],
   "activate or deactivate some volume groups",
   "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in the listed volume groups C<volgroups>.
If activated, then they are made known to the
kernel, ie. they appear as C</dev/mapper> devices.  If deactivated,
then those devices disappear.

This command is the same as running C<vgchange -a y|n volgroups...>

Note that if C<volgroups> is an empty list then B<all> volume groups
are activated or deactivated.");

  ("lvresize", (RErr, [Device "device"; Int "mbytes"]), 105, [Optional "lvm2"],
   [InitNone, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV"; "VG"; "10"];
       ["mkfs"; "ext2"; "/dev/VG/LV"];
       ["mount"; "/dev/VG/LV"; "/"];
       ["write_file"; "/new"; "test content"; "0"];
       ["umount"; "/"];
       ["lvresize"; "/dev/VG/LV"; "20"];
       ["e2fsck_f"; "/dev/VG/LV"];
       ["resize2fs"; "/dev/VG/LV"];
       ["mount"; "/dev/VG/LV"; "/"];
       ["cat"; "/new"]], "test content")],
   "resize an LVM logical volume",
   "\
This resizes (expands or shrinks) an existing LVM logical
volume to C<mbytes>.  When reducing, data in the reduced part
is lost.");

  ("resize2fs", (RErr, [Device "device"]), 106, [],
   [], (* lvresize tests this *)
   "resize an ext2/ext3 filesystem",
   "\
This resizes an ext2 or ext3 filesystem to match the size of
the underlying device.

I<Note:> It is sometimes required that you run C<guestfs_e2fsck_f>
on the C<device> before calling this command.  For unknown reasons
C<resize2fs> sometimes gives an error about this and sometimes not.
In any case, it is always safe to call C<guestfs_e2fsck_f> before
calling this function.");

  ("find", (RStringList "names", [Pathname "directory"]), 107, [ProtocolLimitWarning],
   [InitBasicFS, Always, TestOutputList (
      [["find"; "/"]], ["lost+found"]);
    InitBasicFS, Always, TestOutputList (
      [["touch"; "/a"];
       ["mkdir"; "/b"];
       ["touch"; "/b/c"];
       ["find"; "/"]], ["a"; "b"; "b/c"; "lost+found"]);
    InitBasicFS, Always, TestOutputList (
      [["mkdir_p"; "/a/b/c"];
       ["touch"; "/a/b/c/d"];
       ["find"; "/a/b/"]], ["c"; "c/d"])],
   "find all files and directories",
   "\
This command lists out all files and directories, recursively,
starting at C<directory>.  It is essentially equivalent to
running the shell command C<find directory -print> but some
post-processing happens on the output, described below.

This returns a list of strings I<without any prefix>.  Thus
if the directory structure was:

 /tmp/a
 /tmp/b
 /tmp/c/d

then the returned list from C<guestfs_find> C</tmp> would be
4 elements:

 a
 b
 c
 c/d

If C<directory> is not a directory, then this command returns
an error.

The returned list is sorted.

See also C<guestfs_find0>.");

  ("e2fsck_f", (RErr, [Device "device"]), 108, [],
   [], (* lvresize tests this *)
   "check an ext2/ext3 filesystem",
   "\
This runs C<e2fsck -p -f device>, ie. runs the ext2/ext3
filesystem checker on C<device>, noninteractively (C<-p>),
even if the filesystem appears to be clean (C<-f>).

This command is only needed because of C<guestfs_resize2fs>
(q.v.).  Normally you should use C<guestfs_fsck>.");

  ("sleep", (RErr, [Int "secs"]), 109, [],
   [InitNone, Always, TestRun (
      [["sleep"; "1"]])],
   "sleep for some seconds",
   "\
Sleep for C<secs> seconds.");

  ("ntfs_3g_probe", (RInt "status", [Bool "rw"; Device "device"]), 110, [Optional "ntfs3g"],
   [InitNone, Always, TestOutputInt (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ntfs"; "/dev/sda1"];
       ["ntfs_3g_probe"; "true"; "/dev/sda1"]], 0);
    InitNone, Always, TestOutputInt (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["ntfs_3g_probe"; "true"; "/dev/sda1"]], 12)],
   "probe NTFS volume",
   "\
This command runs the L<ntfs-3g.probe(8)> command which probes
an NTFS C<device> for mountability.  (Not all NTFS volumes can
be mounted read-write, and some cannot be mounted at all).

C<rw> is a boolean flag.  Set it to true if you want to test
if the volume can be mounted read-write.  Set it to false if
you want to test if the volume can be mounted read-only.

The return value is an integer which C<0> if the operation
would succeed, or some non-zero value documented in the
L<ntfs-3g.probe(8)> manual page.");

  ("sh", (RString "output", [String "command"]), 111, [],
   [], (* XXX needs tests *)
   "run a command via the shell",
   "\
This call runs a command from the guest filesystem via the
guest's C</bin/sh>.

This is like C<guestfs_command>, but passes the command to:

 /bin/sh -c \"command\"

Depending on the guest's shell, this usually results in
wildcards being expanded, shell expressions being interpolated
and so on.

All the provisos about C<guestfs_command> apply to this call.");

  ("sh_lines", (RStringList "lines", [String "command"]), 112, [],
   [], (* XXX needs tests *)
   "run a command via the shell returning lines",
   "\
This is the same as C<guestfs_sh>, but splits the result
into a list of lines.

See also: C<guestfs_command_lines>");

  ("glob_expand", (RStringList "paths", [Pathname "pattern"]), 113, [],
   (* Use Pathname here, and hence ABS_PATH (pattern,... in generated
    * code in stubs.c, since all valid glob patterns must start with "/".
    * There is no concept of "cwd" in libguestfs, hence no "."-relative names.
    *)
   [InitBasicFS, Always, TestOutputList (
      [["mkdir_p"; "/a/b/c"];
       ["touch"; "/a/b/c/d"];
       ["touch"; "/a/b/c/e"];
       ["glob_expand"; "/a/b/c/*"]], ["/a/b/c/d"; "/a/b/c/e"]);
    InitBasicFS, Always, TestOutputList (
      [["mkdir_p"; "/a/b/c"];
       ["touch"; "/a/b/c/d"];
       ["touch"; "/a/b/c/e"];
       ["glob_expand"; "/a/*/c/*"]], ["/a/b/c/d"; "/a/b/c/e"]);
    InitBasicFS, Always, TestOutputList (
      [["mkdir_p"; "/a/b/c"];
       ["touch"; "/a/b/c/d"];
       ["touch"; "/a/b/c/e"];
       ["glob_expand"; "/a/*/x/*"]], [])],
   "expand a wildcard path",
   "\
This command searches for all the pathnames matching
C<pattern> according to the wildcard expansion rules
used by the shell.

If no paths match, then this returns an empty list
(note: not an error).

It is just a wrapper around the C L<glob(3)> function
with flags C<GLOB_MARK|GLOB_BRACE>.
See that manual page for more details.");

  ("scrub_device", (RErr, [Device "device"]), 114, [DangerWillRobinson; Optional "scrub"],
   [InitNone, Always, TestRun (	(* use /dev/sdc because it's smaller *)
      [["scrub_device"; "/dev/sdc"]])],
   "scrub (securely wipe) a device",
   "\
This command writes patterns over C<device> to make data retrieval
more difficult.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details.");

  ("scrub_file", (RErr, [Pathname "file"]), 115, [Optional "scrub"],
   [InitBasicFS, Always, TestRun (
      [["write_file"; "/file"; "content"; "0"];
       ["scrub_file"; "/file"]])],
   "scrub (securely wipe) a file",
   "\
This command writes patterns over a file to make data retrieval
more difficult.

The file is I<removed> after scrubbing.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details.");

  ("scrub_freespace", (RErr, [Pathname "dir"]), 116, [Optional "scrub"],
   [], (* XXX needs testing *)
   "scrub (securely wipe) free space",
   "\
This command creates the directory C<dir> and then fills it
with files until the filesystem is full, and scrubs the files
as for C<guestfs_scrub_file>, and deletes them.
The intention is to scrub any free space on the partition
containing C<dir>.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details.");

  ("mkdtemp", (RString "dir", [Pathname "template"]), 117, [],
   [InitBasicFS, Always, TestRun (
      [["mkdir"; "/tmp"];
       ["mkdtemp"; "/tmp/tmpXXXXXX"]])],
   "create a temporary directory",
   "\
This command creates a temporary directory.  The
C<template> parameter should be a full pathname for the
temporary directory name with the final six characters being
\"XXXXXX\".

For example: \"/tmp/myprogXXXXXX\" or \"/Temp/myprogXXXXXX\",
the second one being suitable for Windows filesystems.

The name of the temporary directory that was created
is returned.

The temporary directory is created with mode 0700
and is owned by root.

The caller is responsible for deleting the temporary
directory and its contents after use.

See also: L<mkdtemp(3)>");

  ("wc_l", (RInt "lines", [Pathname "path"]), 118, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_l"; "/10klines"]], 10000)],
   "count lines in a file",
   "\
This command counts the lines in a file, using the
C<wc -l> external command.");

  ("wc_w", (RInt "words", [Pathname "path"]), 119, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_w"; "/10klines"]], 10000)],
   "count words in a file",
   "\
This command counts the words in a file, using the
C<wc -w> external command.");

  ("wc_c", (RInt "chars", [Pathname "path"]), 120, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_c"; "/100kallspaces"]], 102400)],
   "count characters in a file",
   "\
This command counts the characters in a file, using the
C<wc -c> external command.");

  ("head", (RStringList "lines", [Pathname "path"]), 121, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["head"; "/10klines"]], ["0abcdefghijklmnopqrstuvwxyz";"1abcdefghijklmnopqrstuvwxyz";"2abcdefghijklmnopqrstuvwxyz";"3abcdefghijklmnopqrstuvwxyz";"4abcdefghijklmnopqrstuvwxyz";"5abcdefghijklmnopqrstuvwxyz";"6abcdefghijklmnopqrstuvwxyz";"7abcdefghijklmnopqrstuvwxyz";"8abcdefghijklmnopqrstuvwxyz";"9abcdefghijklmnopqrstuvwxyz"])],
   "return first 10 lines of a file",
   "\
This command returns up to the first 10 lines of a file as
a list of strings.");

  ("head_n", (RStringList "lines", [Int "nrlines"; Pathname "path"]), 122, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["head_n"; "3"; "/10klines"]], ["0abcdefghijklmnopqrstuvwxyz";"1abcdefghijklmnopqrstuvwxyz";"2abcdefghijklmnopqrstuvwxyz"]);
    InitISOFS, Always, TestOutputList (
      [["head_n"; "-9997"; "/10klines"]], ["0abcdefghijklmnopqrstuvwxyz";"1abcdefghijklmnopqrstuvwxyz";"2abcdefghijklmnopqrstuvwxyz"]);
    InitISOFS, Always, TestOutputList (
      [["head_n"; "0"; "/10klines"]], [])],
   "return first N lines of a file",
   "\
If the parameter C<nrlines> is a positive number, this returns the first
C<nrlines> lines of the file C<path>.

If the parameter C<nrlines> is a negative number, this returns lines
from the file C<path>, excluding the last C<nrlines> lines.

If the parameter C<nrlines> is zero, this returns an empty list.");

  ("tail", (RStringList "lines", [Pathname "path"]), 123, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["tail"; "/10klines"]], ["9990abcdefghijklmnopqrstuvwxyz";"9991abcdefghijklmnopqrstuvwxyz";"9992abcdefghijklmnopqrstuvwxyz";"9993abcdefghijklmnopqrstuvwxyz";"9994abcdefghijklmnopqrstuvwxyz";"9995abcdefghijklmnopqrstuvwxyz";"9996abcdefghijklmnopqrstuvwxyz";"9997abcdefghijklmnopqrstuvwxyz";"9998abcdefghijklmnopqrstuvwxyz";"9999abcdefghijklmnopqrstuvwxyz"])],
   "return last 10 lines of a file",
   "\
This command returns up to the last 10 lines of a file as
a list of strings.");

  ("tail_n", (RStringList "lines", [Int "nrlines"; Pathname "path"]), 124, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["tail_n"; "3"; "/10klines"]], ["9997abcdefghijklmnopqrstuvwxyz";"9998abcdefghijklmnopqrstuvwxyz";"9999abcdefghijklmnopqrstuvwxyz"]);
    InitISOFS, Always, TestOutputList (
      [["tail_n"; "-9998"; "/10klines"]], ["9997abcdefghijklmnopqrstuvwxyz";"9998abcdefghijklmnopqrstuvwxyz";"9999abcdefghijklmnopqrstuvwxyz"]);
    InitISOFS, Always, TestOutputList (
      [["tail_n"; "0"; "/10klines"]], [])],
   "return last N lines of a file",
   "\
If the parameter C<nrlines> is a positive number, this returns the last
C<nrlines> lines of the file C<path>.

If the parameter C<nrlines> is a negative number, this returns lines
from the file C<path>, starting with the C<-nrlines>th line.

If the parameter C<nrlines> is zero, this returns an empty list.");

  ("df", (RString "output", []), 125, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'df' command and other imponderables.
        *)
   "report file system disk space usage",
   "\
This command runs the C<df> command to report disk space used.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<statvfs> from programs.");

  ("df_h", (RString "output", []), 126, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'df' command and other imponderables.
        *)
   "report file system disk space usage (human readable)",
   "\
This command runs the C<df -h> command to report disk space used
in human-readable format.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<statvfs> from programs.");

  ("du", (RInt64 "sizekb", [Pathname "path"]), 127, [],
   [InitISOFS, Always, TestOutputInt (
      [["du"; "/directory"]], 2 (* ISO fs blocksize is 2K *))],
   "estimate file space usage",
   "\
This command runs the C<du -s> command to estimate file space
usage for C<path>.

C<path> can be a file or a directory.  If C<path> is a directory
then the estimate includes the contents of the directory and all
subdirectories (recursively).

The result is the estimated size in I<kilobytes>
(ie. units of 1024 bytes).");

  ("initrd_list", (RStringList "filenames", [Pathname "path"]), 128, [],
   [InitISOFS, Always, TestOutputList (
      [["initrd_list"; "/initrd"]], ["empty";"known-1";"known-2";"known-3";"known-4"; "known-5"])],
   "list files in an initrd",
   "\
This command lists out files contained in an initrd.

The files are listed without any initial C</> character.  The
files are listed in the order they appear (not necessarily
alphabetical).  Directory names are listed as separate items.

Old Linux kernels (2.4 and earlier) used a compressed ext2
filesystem as initrd.  We I<only> support the newer initramfs
format (compressed cpio files).");

  ("mount_loop", (RErr, [Pathname "file"; Pathname "mountpoint"]), 129, [],
   [],
   "mount a file using the loop device",
   "\
This command lets you mount C<file> (a filesystem image
in a file) on a mount point.  It is entirely equivalent to
the command C<mount -o loop file mountpoint>.");

  ("mkswap", (RErr, [Device "device"]), 130, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkswap"; "/dev/sda1"]])],
   "create a swap partition",
   "\
Create a swap partition on C<device>.");

  ("mkswap_L", (RErr, [String "label"; Device "device"]), 131, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkswap_L"; "hello"; "/dev/sda1"]])],
   "create a swap partition with a label",
   "\
Create a swap partition on C<device> with label C<label>.

Note that you cannot attach a swap label to a block device
(eg. C</dev/sda>), just to a partition.  This appears to be
a limitation of the kernel or swap tools.");

  ("mkswap_U", (RErr, [String "uuid"; Device "device"]), 132, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestRun (
       [["part_disk"; "/dev/sda"; "mbr"];
        ["mkswap_U"; uuid; "/dev/sda1"]])]),
   "create a swap partition with an explicit UUID",
   "\
Create a swap partition on C<device> with UUID C<uuid>.");

  ("mknod", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"]), 133, [Optional "mknod"],
   [InitBasicFS, Always, TestOutputStruct (
      [["mknod"; "0o10777"; "0"; "0"; "/node"];
       (* NB: default umask 022 means 0777 -> 0755 in these tests *)
       ["stat"; "/node"]], [CompareWithInt ("mode", 0o10755)]);
    InitBasicFS, Always, TestOutputStruct (
      [["mknod"; "0o60777"; "66"; "99"; "/node"];
       ["stat"; "/node"]], [CompareWithInt ("mode", 0o60755)])],
   "make block, character or FIFO devices",
   "\
This call creates block or character special devices, or
named pipes (FIFOs).

The C<mode> parameter should be the mode, using the standard
constants.  C<devmajor> and C<devminor> are the
device major and minor numbers, only used when creating block
and character special devices.");

  ("mkfifo", (RErr, [Int "mode"; Pathname "path"]), 134, [Optional "mknod"],
   [InitBasicFS, Always, TestOutputStruct (
      [["mkfifo"; "0o777"; "/node"];
       ["stat"; "/node"]], [CompareWithInt ("mode", 0o10755)])],
   "make FIFO (named pipe)",
   "\
This call creates a FIFO (named pipe) called C<path> with
mode C<mode>.  It is just a convenient wrapper around
C<guestfs_mknod>.");

  ("mknod_b", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"]), 135, [Optional "mknod"],
   [InitBasicFS, Always, TestOutputStruct (
      [["mknod_b"; "0o777"; "99"; "66"; "/node"];
       ["stat"; "/node"]], [CompareWithInt ("mode", 0o60755)])],
   "make block device node",
   "\
This call creates a block device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.");

  ("mknod_c", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"]), 136, [Optional "mknod"],
   [InitBasicFS, Always, TestOutputStruct (
      [["mknod_c"; "0o777"; "99"; "66"; "/node"];
       ["stat"; "/node"]], [CompareWithInt ("mode", 0o20755)])],
   "make char device node",
   "\
This call creates a char device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.");

  ("umask", (RInt "oldmask", [Int "mask"]), 137, [],
   [], (* XXX umask is one of those stateful things that we should
        * reset between each test.
        *)
   "set file mode creation mask (umask)",
   "\
This function sets the mask used for creating new files and
device nodes to C<mask & 0777>.

Typical umask values would be C<022> which creates new files
with permissions like \"-rw-r--r--\" or \"-rwxr-xr-x\", and
C<002> which creates new files with permissions like
\"-rw-rw-r--\" or \"-rwxrwxr-x\".

The default umask is C<022>.  This is important because it
means that directories and device nodes will be created with
C<0644> or C<0755> mode even if you specify C<0777>.

See also L<umask(2)>, C<guestfs_mknod>, C<guestfs_mkdir>.

This call returns the previous umask.");

  ("readdir", (RStructList ("entries", "dirent"), [Pathname "dir"]), 138, [],
   [],
   "read directories entries",
   "\
This returns the list of directory entries in directory C<dir>.

All entries in the directory are returned, including C<.> and
C<..>.  The entries are I<not> sorted, but returned in the same
order as the underlying filesystem.

Also this call returns basic file type information about each
file.  The C<ftyp> field will contain one of the following characters:

=over 4

=item 'b'

Block special

=item 'c'

Char special

=item 'd'

Directory

=item 'f'

FIFO (named pipe)

=item 'l'

Symbolic link

=item 'r'

Regular file

=item 's'

Socket

=item 'u'

Unknown file type

=item '?'

The L<readdir(3)> returned a C<d_type> field with an
unexpected value

=back

This function is primarily intended for use by programs.  To
get a simple list of names, use C<guestfs_ls>.  To get a printable
directory for human consumption, use C<guestfs_ll>.");

  ("sfdiskM", (RErr, [Device "device"; StringList "lines"]), 139, [DangerWillRobinson],
   [],
   "create partitions on a block device",
   "\
This is a simplified interface to the C<guestfs_sfdisk>
command, where partition sizes are specified in megabytes
only (rounded to the nearest cylinder) and you don't need
to specify the cyls, heads and sectors parameters which
were rarely if ever used anyway.

See also: C<guestfs_sfdisk>, the L<sfdisk(8)> manpage
and C<guestfs_part_disk>");

  ("zfile", (RString "description", [String "meth"; Pathname "path"]), 140, [DeprecatedBy "file"],
   [],
   "determine file type inside a compressed file",
   "\
This command runs C<file> after first decompressing C<path>
using C<method>.

C<method> must be one of C<gzip>, C<compress> or C<bzip2>.

Since 1.0.63, use C<guestfs_file> instead which can now
process compressed files.");

  ("getxattrs", (RStructList ("xattrs", "xattr"), [Pathname "path"]), 141, [Optional "linuxxattrs"],
   [],
   "list extended attributes of a file or directory",
   "\
This call lists the extended attributes of the file or directory
C<path>.

At the system call level, this is a combination of the
L<listxattr(2)> and L<getxattr(2)> calls.

See also: C<guestfs_lgetxattrs>, L<attr(5)>.");

  ("lgetxattrs", (RStructList ("xattrs", "xattr"), [Pathname "path"]), 142, [Optional "linuxxattrs"],
   [],
   "list extended attributes of a file or directory",
   "\
This is the same as C<guestfs_getxattrs>, but if C<path>
is a symbolic link, then it returns the extended attributes
of the link itself.");

  ("setxattr", (RErr, [String "xattr";
                       String "val"; Int "vallen"; (* will be BufferIn *)
                       Pathname "path"]), 143, [Optional "linuxxattrs"],
   [],
   "set extended attribute of a file or directory",
   "\
This call sets the extended attribute named C<xattr>
of the file C<path> to the value C<val> (of length C<vallen>).
The value is arbitrary 8 bit data.

See also: C<guestfs_lsetxattr>, L<attr(5)>.");

  ("lsetxattr", (RErr, [String "xattr";
                        String "val"; Int "vallen"; (* will be BufferIn *)
                        Pathname "path"]), 144, [Optional "linuxxattrs"],
   [],
   "set extended attribute of a file or directory",
   "\
This is the same as C<guestfs_setxattr>, but if C<path>
is a symbolic link, then it sets an extended attribute
of the link itself.");

  ("removexattr", (RErr, [String "xattr"; Pathname "path"]), 145, [Optional "linuxxattrs"],
   [],
   "remove extended attribute of a file or directory",
   "\
This call removes the extended attribute named C<xattr>
of the file C<path>.

See also: C<guestfs_lremovexattr>, L<attr(5)>.");

  ("lremovexattr", (RErr, [String "xattr"; Pathname "path"]), 146, [Optional "linuxxattrs"],
   [],
   "remove extended attribute of a file or directory",
   "\
This is the same as C<guestfs_removexattr>, but if C<path>
is a symbolic link, then it removes an extended attribute
of the link itself.");

  ("mountpoints", (RHashtable "mps", []), 147, [],
   [],
   "show mountpoints",
   "\
This call is similar to C<guestfs_mounts>.  That call returns
a list of devices.  This one returns a hash table (map) of
device name to directory where the device is mounted.");

  ("mkmountpoint", (RErr, [String "exemptpath"]), 148, [],
   (* This is a special case: while you would expect a parameter
    * of type "Pathname", that doesn't work, because it implies
    * NEED_ROOT in the generated calling code in stubs.c, and
    * this function cannot use NEED_ROOT.
    *)
   [],
   "create a mountpoint",
   "\
C<guestfs_mkmountpoint> and C<guestfs_rmmountpoint> are
specialized calls that can be used to create extra mountpoints
before mounting the first filesystem.

These calls are I<only> necessary in some very limited circumstances,
mainly the case where you want to mount a mix of unrelated and/or
read-only filesystems together.

For example, live CDs often contain a \"Russian doll\" nest of
filesystems, an ISO outer layer, with a squashfs image inside, with
an ext2/3 image inside that.  You can unpack this as follows
in guestfish:

 add-ro Fedora-11-i686-Live.iso
 run
 mkmountpoint /cd
 mkmountpoint /squash
 mkmountpoint /ext3
 mount /dev/sda /cd
 mount-loop /cd/LiveOS/squashfs.img /squash
 mount-loop /squash/LiveOS/ext3fs.img /ext3

The inner filesystem is now unpacked under the /ext3 mountpoint.");

  ("rmmountpoint", (RErr, [String "exemptpath"]), 149, [],
   [],
   "remove a mountpoint",
   "\
This calls removes a mountpoint that was previously created
with C<guestfs_mkmountpoint>.  See C<guestfs_mkmountpoint>
for full details.");

  ("read_file", (RBufferOut "content", [Pathname "path"]), 150, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputBuffer (
      [["read_file"; "/known-4"]], "abc\ndef\nghi")],
   "read a file",
   "\
This calls returns the contents of the file C<path> as a
buffer.

Unlike C<guestfs_cat>, this function can correctly
handle files that contain embedded ASCII NUL characters.
However unlike C<guestfs_download>, this function is limited
in the total size of file that can be handled.");

  ("grep", (RStringList "lines", [String "regex"; Pathname "path"]), 151, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["grep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"]);
    InitISOFS, Always, TestOutputList (
      [["grep"; "nomatch"; "/test-grep.txt"]], [])],
   "return lines matching a pattern",
   "\
This calls the external C<grep> program and returns the
matching lines.");

  ("egrep", (RStringList "lines", [String "regex"; Pathname "path"]), 152, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["egrep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<egrep> program and returns the
matching lines.");

  ("fgrep", (RStringList "lines", [String "pattern"; Pathname "path"]), 153, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["fgrep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<fgrep> program and returns the
matching lines.");

  ("grepi", (RStringList "lines", [String "regex"; Pathname "path"]), 154, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["grepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<grep -i> program and returns the
matching lines.");

  ("egrepi", (RStringList "lines", [String "regex"; Pathname "path"]), 155, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["egrepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<egrep -i> program and returns the
matching lines.");

  ("fgrepi", (RStringList "lines", [String "pattern"; Pathname "path"]), 156, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["fgrepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<fgrep -i> program and returns the
matching lines.");

  ("zgrep", (RStringList "lines", [String "regex"; Pathname "path"]), 157, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zgrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zgrep> program and returns the
matching lines.");

  ("zegrep", (RStringList "lines", [String "regex"; Pathname "path"]), 158, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zegrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zegrep> program and returns the
matching lines.");

  ("zfgrep", (RStringList "lines", [String "pattern"; Pathname "path"]), 159, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zfgrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zfgrep> program and returns the
matching lines.");

  ("zgrepi", (RStringList "lines", [String "regex"; Pathname "path"]), 160, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zgrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zgrep -i> program and returns the
matching lines.");

  ("zegrepi", (RStringList "lines", [String "regex"; Pathname "path"]), 161, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zegrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zegrep -i> program and returns the
matching lines.");

  ("zfgrepi", (RStringList "lines", [String "pattern"; Pathname "path"]), 162, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zfgrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zfgrep -i> program and returns the
matching lines.");

  ("realpath", (RString "rpath", [Pathname "path"]), 163, [Optional "realpath"],
   [InitISOFS, Always, TestOutput (
      [["realpath"; "/../directory"]], "/directory")],
   "canonicalized absolute pathname",
   "\
Return the canonicalized absolute pathname of C<path>.  The
returned path has no C<.>, C<..> or symbolic link path elements.");

  ("ln", (RErr, [String "target"; Pathname "linkname"]), 164, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["touch"; "/a"];
       ["ln"; "/a"; "/b"];
       ["stat"; "/b"]], [CompareWithInt ("nlink", 2)])],
   "create a hard link",
   "\
This command creates a hard link using the C<ln> command.");

  ("ln_f", (RErr, [String "target"; Pathname "linkname"]), 165, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["touch"; "/a"];
       ["touch"; "/b"];
       ["ln_f"; "/a"; "/b"];
       ["stat"; "/b"]], [CompareWithInt ("nlink", 2)])],
   "create a hard link",
   "\
This command creates a hard link using the C<ln -f> command.
The C<-f> option removes the link (C<linkname>) if it exists already.");

  ("ln_s", (RErr, [String "target"; Pathname "linkname"]), 166, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["touch"; "/a"];
       ["ln_s"; "a"; "/b"];
       ["lstat"; "/b"]], [CompareWithInt ("mode", 0o120777)])],
   "create a symbolic link",
   "\
This command creates a symbolic link using the C<ln -s> command.");

  ("ln_sf", (RErr, [String "target"; Pathname "linkname"]), 167, [],
   [InitBasicFS, Always, TestOutput (
      [["mkdir_p"; "/a/b"];
       ["touch"; "/a/b/c"];
       ["ln_sf"; "../d"; "/a/b/c"];
       ["readlink"; "/a/b/c"]], "../d")],
   "create a symbolic link",
   "\
This command creates a symbolic link using the C<ln -sf> command,
The C<-f> option removes the link (C<linkname>) if it exists already.");

  ("readlink", (RString "link", [Pathname "path"]), 168, [],
   [] (* XXX tested above *),
   "read the target of a symbolic link",
   "\
This command reads the target of a symbolic link.");

  ("fallocate", (RErr, [Pathname "path"; Int "len"]), 169, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["fallocate"; "/a"; "1000000"];
       ["stat"; "/a"]], [CompareWithInt ("size", 1_000_000)])],
   "preallocate a file in the guest filesystem",
   "\
This command preallocates a file (containing zero bytes) named
C<path> of size C<len> bytes.  If the file exists already, it
is overwritten.

Do not confuse this with the guestfish-specific
C<alloc> command which allocates a file in the host and
attaches it as a device.");

  ("swapon_device", (RErr, [Device "device"]), 170, [],
   [InitPartition, Always, TestRun (
      [["mkswap"; "/dev/sda1"];
       ["swapon_device"; "/dev/sda1"];
       ["swapoff_device"; "/dev/sda1"]])],
   "enable swap on device",
   "\
This command enables the libguestfs appliance to use the
swap device or partition named C<device>.  The increased
memory is made available for all commands, for example
those run using C<guestfs_command> or C<guestfs_sh>.

Note that you should not swap to existing guest swap
partitions unless you know what you are doing.  They may
contain hibernation information, or other information that
the guest doesn't want you to trash.  You also risk leaking
information about the host to the guest this way.  Instead,
attach a new host device to the guest and swap on that.");

  ("swapoff_device", (RErr, [Device "device"]), 171, [],
   [], (* XXX tested by swapon_device *)
   "disable swap on device",
   "\
This command disables the libguestfs appliance swap
device or partition named C<device>.
See C<guestfs_swapon_device>.");

  ("swapon_file", (RErr, [Pathname "file"]), 172, [],
   [InitBasicFS, Always, TestRun (
      [["fallocate"; "/swap"; "8388608"];
       ["mkswap_file"; "/swap"];
       ["swapon_file"; "/swap"];
       ["swapoff_file"; "/swap"]])],
   "enable swap on file",
   "\
This command enables swap to a file.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_file", (RErr, [Pathname "file"]), 173, [],
   [], (* XXX tested by swapon_file *)
   "disable swap on file",
   "\
This command disables the libguestfs appliance swap on file.");

  ("swapon_label", (RErr, [String "label"]), 174, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sdb"; "mbr"];
       ["mkswap_L"; "swapit"; "/dev/sdb1"];
       ["swapon_label"; "swapit"];
       ["swapoff_label"; "swapit"];
       ["zero"; "/dev/sdb"];
       ["blockdev_rereadpt"; "/dev/sdb"]])],
   "enable swap on labeled swap partition",
   "\
This command enables swap to a labeled swap partition.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_label", (RErr, [String "label"]), 175, [],
   [], (* XXX tested by swapon_label *)
   "disable swap on labeled swap partition",
   "\
This command disables the libguestfs appliance swap on
labeled swap partition.");

  ("swapon_uuid", (RErr, [String "uuid"]), 176, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestRun (
       [["mkswap_U"; uuid; "/dev/sdb"];
        ["swapon_uuid"; uuid];
        ["swapoff_uuid"; uuid]])]),
   "enable swap on swap partition by UUID",
   "\
This command enables swap to a swap partition with the given UUID.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_uuid", (RErr, [String "uuid"]), 177, [Optional "linuxfsuuid"],
   [], (* XXX tested by swapon_uuid *)
   "disable swap on swap partition by UUID",
   "\
This command disables the libguestfs appliance swap partition
with the given UUID.");

  ("mkswap_file", (RErr, [Pathname "path"]), 178, [],
   [InitBasicFS, Always, TestRun (
      [["fallocate"; "/swap"; "8388608"];
       ["mkswap_file"; "/swap"]])],
   "create a swap file",
   "\
Create a swap file.

This command just writes a swap file signature to an existing
file.  To create the file itself, use something like C<guestfs_fallocate>.");

  ("inotify_init", (RErr, [Int "maxevents"]), 179, [Optional "inotify"],
   [InitISOFS, Always, TestRun (
      [["inotify_init"; "0"]])],
   "create an inotify handle",
   "\
This command creates a new inotify handle.
The inotify subsystem can be used to notify events which happen to
objects in the guest filesystem.

C<maxevents> is the maximum number of events which will be
queued up between calls to C<guestfs_inotify_read> or
C<guestfs_inotify_files>.
If this is passed as C<0>, then the kernel (or previously set)
default is used.  For Linux 2.6.29 the default was 16384 events.
Beyond this limit, the kernel throws away events, but records
the fact that it threw them away by setting a flag
C<IN_Q_OVERFLOW> in the returned structure list (see
C<guestfs_inotify_read>).

Before any events are generated, you have to add some
watches to the internal watch list.  See:
C<guestfs_inotify_add_watch>,
C<guestfs_inotify_rm_watch> and
C<guestfs_inotify_watch_all>.

Queued up events should be read periodically by calling
C<guestfs_inotify_read>
(or C<guestfs_inotify_files> which is just a helpful
wrapper around C<guestfs_inotify_read>).  If you don't
read the events out often enough then you risk the internal
queue overflowing.

The handle should be closed after use by calling
C<guestfs_inotify_close>.  This also removes any
watches automatically.

See also L<inotify(7)> for an overview of the inotify interface
as exposed by the Linux kernel, which is roughly what we expose
via libguestfs.  Note that there is one global inotify handle
per libguestfs instance.");

  ("inotify_add_watch", (RInt64 "wd", [Pathname "path"; Int "mask"]), 180, [Optional "inotify"],
   [InitBasicFS, Always, TestOutputList (
      [["inotify_init"; "0"];
       ["inotify_add_watch"; "/"; "1073741823"];
       ["touch"; "/a"];
       ["touch"; "/b"];
       ["inotify_files"]], ["a"; "b"])],
   "add an inotify watch",
   "\
Watch C<path> for the events listed in C<mask>.

Note that if C<path> is a directory then events within that
directory are watched, but this does I<not> happen recursively
(in subdirectories).

Note for non-C or non-Linux callers: the inotify events are
defined by the Linux kernel ABI and are listed in
C</usr/include/sys/inotify.h>.");

  ("inotify_rm_watch", (RErr, [Int(*XXX64*) "wd"]), 181, [Optional "inotify"],
   [],
   "remove an inotify watch",
   "\
Remove a previously defined inotify watch.
See C<guestfs_inotify_add_watch>.");

  ("inotify_read", (RStructList ("events", "inotify_event"), []), 182, [Optional "inotify"],
   [],
   "return list of inotify events",
   "\
Return the complete queue of events that have happened
since the previous read call.

If no events have happened, this returns an empty list.

I<Note>: In order to make sure that all events have been
read, you must call this function repeatedly until it
returns an empty list.  The reason is that the call will
read events up to the maximum appliance-to-host message
size and leave remaining events in the queue.");

  ("inotify_files", (RStringList "paths", []), 183, [Optional "inotify"],
   [],
   "return list of watched files that had events",
   "\
This function is a helpful wrapper around C<guestfs_inotify_read>
which just returns a list of pathnames of objects that were
touched.  The returned pathnames are sorted and deduplicated.");

  ("inotify_close", (RErr, []), 184, [Optional "inotify"],
   [],
   "close the inotify handle",
   "\
This closes the inotify handle which was previously
opened by inotify_init.  It removes all watches, throws
away any pending events, and deallocates all resources.");

  ("setcon", (RErr, [String "context"]), 185, [Optional "selinux"],
   [],
   "set SELinux security context",
   "\
This sets the SELinux security context of the daemon
to the string C<context>.

See the documentation about SELINUX in L<guestfs(3)>.");

  ("getcon", (RString "context", []), 186, [Optional "selinux"],
   [],
   "get SELinux security context",
   "\
This gets the SELinux security context of the daemon.

See the documentation about SELINUX in L<guestfs(3)>,
and C<guestfs_setcon>");

  ("mkfs_b", (RErr, [String "fstype"; Int "blocksize"; Device "device"]), 187, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "ext2"; "4096"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "make a filesystem with block size",
   "\
This call is similar to C<guestfs_mkfs>, but it allows you to
control the block size of the resulting filesystem.  Supported
block sizes depend on the filesystem type, but typically they
are C<1024>, C<2048> or C<4096> only.");

  ("mke2journal", (RErr, [Int "blocksize"; Device "device"]), 188, [],
   [InitEmpty, Always, TestOutput (
      [["sfdiskM"; "/dev/sda"; ",100 ,"];
       ["mke2journal"; "4096"; "/dev/sda1"];
       ["mke2fs_J"; "ext2"; "4096"; "/dev/sda2"; "/dev/sda1"];
       ["mount"; "/dev/sda2"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "make ext2/3/4 external journal",
   "\
This creates an ext2 external journal on C<device>.  It is equivalent
to the command:

 mke2fs -O journal_dev -b blocksize device");

  ("mke2journal_L", (RErr, [Int "blocksize"; String "label"; Device "device"]), 189, [],
   [InitEmpty, Always, TestOutput (
      [["sfdiskM"; "/dev/sda"; ",100 ,"];
       ["mke2journal_L"; "4096"; "JOURNAL"; "/dev/sda1"];
       ["mke2fs_JL"; "ext2"; "4096"; "/dev/sda2"; "JOURNAL"];
       ["mount"; "/dev/sda2"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "make ext2/3/4 external journal with label",
   "\
This creates an ext2 external journal on C<device> with label C<label>.");

  ("mke2journal_U", (RErr, [Int "blocksize"; String "uuid"; Device "device"]), 190, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestOutput (
       [["sfdiskM"; "/dev/sda"; ",100 ,"];
        ["mke2journal_U"; "4096"; uuid; "/dev/sda1"];
        ["mke2fs_JU"; "ext2"; "4096"; "/dev/sda2"; uuid];
        ["mount"; "/dev/sda2"; "/"];
        ["write_file"; "/new"; "new file contents"; "0"];
        ["cat"; "/new"]], "new file contents")]),
   "make ext2/3/4 external journal with UUID",
   "\
This creates an ext2 external journal on C<device> with UUID C<uuid>.");

  ("mke2fs_J", (RErr, [String "fstype"; Int "blocksize"; Device "device"; Device "journal"]), 191, [],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on C<journal>.  It is equivalent
to the command:

 mke2fs -t fstype -b blocksize -J device=<journal> <device>

See also C<guestfs_mke2journal>.");

  ("mke2fs_JL", (RErr, [String "fstype"; Int "blocksize"; Device "device"; String "label"]), 192, [],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal labeled C<label>.

See also C<guestfs_mke2journal_L>.");

  ("mke2fs_JU", (RErr, [String "fstype"; Int "blocksize"; Device "device"; String "uuid"]), 193, [Optional "linuxfsuuid"],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal with UUID C<uuid>.

See also C<guestfs_mke2journal_U>.");

  ("modprobe", (RErr, [String "modulename"]), 194, [Optional "linuxmodules"],
   [InitNone, Always, TestRun [["modprobe"; "fat"]]],
   "load a kernel module",
   "\
This loads a kernel module in the appliance.

The kernel module must have been whitelisted when libguestfs
was built (see C<appliance/kmod.whitelist.in> in the source).");

  ("echo_daemon", (RString "output", [StringList "words"]), 195, [],
   [InitNone, Always, TestOutput (
      [["echo_daemon"; "This is a test"]], "This is a test"
    )],
   "echo arguments back to the client",
   "\
This command concatenate the list of C<words> passed with single spaces between
them and returns the resulting string.

You can use this command to test the connection through to the daemon.

See also C<guestfs_ping_daemon>.");

  ("find0", (RErr, [Pathname "directory"; FileOut "files"]), 196, [],
   [], (* There is a regression test for this. *)
   "find all files and directories, returning NUL-separated list",
   "\
This command lists out all files and directories, recursively,
starting at C<directory>, placing the resulting list in the
external file called C<files>.

This command works the same way as C<guestfs_find> with the
following exceptions:

=over 4

=item *

The resulting list is written to an external file.

=item *

Items (filenames) in the result are separated
by C<\\0> characters.  See L<find(1)> option I<-print0>.

=item *

This command is not limited in the number of names that it
can return.

=item *

The result list is not sorted.

=back");

  ("case_sensitive_path", (RString "rpath", [Pathname "path"]), 197, [],
   [InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/DIRECTORY"]], "/directory");
    InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/DIRECTORY/"]], "/directory");
    InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/Known-1"]], "/known-1");
    InitISOFS, Always, TestLastFail (
      [["case_sensitive_path"; "/Known-1/"]]);
    InitBasicFS, Always, TestOutput (
      [["mkdir"; "/a"];
       ["mkdir"; "/a/bbb"];
       ["touch"; "/a/bbb/c"];
       ["case_sensitive_path"; "/A/bbB/C"]], "/a/bbb/c");
    InitBasicFS, Always, TestOutput (
      [["mkdir"; "/a"];
       ["mkdir"; "/a/bbb"];
       ["touch"; "/a/bbb/c"];
       ["case_sensitive_path"; "/A////bbB/C"]], "/a/bbb/c");
    InitBasicFS, Always, TestLastFail (
      [["mkdir"; "/a"];
       ["mkdir"; "/a/bbb"];
       ["touch"; "/a/bbb/c"];
       ["case_sensitive_path"; "/A/bbb/../bbb/C"]])],
   "return true path on case-insensitive filesystem",
   "\
This can be used to resolve case insensitive paths on
a filesystem which is case sensitive.  The use case is
to resolve paths which you have read from Windows configuration
files or the Windows Registry, to the true path.

The command handles a peculiarity of the Linux ntfs-3g
filesystem driver (and probably others), which is that although
the underlying filesystem is case-insensitive, the driver
exports the filesystem to Linux as case-sensitive.

One consequence of this is that special directories such
as C<c:\\windows> may appear as C</WINDOWS> or C</windows>
(or other things) depending on the precise details of how
they were created.  In Windows itself this would not be
a problem.

Bug or feature?  You decide:
L<http://www.tuxera.com/community/ntfs-3g-faq/#posixfilenames1>

This function resolves the true case of each element in the
path and returns the case-sensitive path.

Thus C<guestfs_case_sensitive_path> (\"/Windows/System32\")
might return C<\"/WINDOWS/system32\"> (the exact return value
would depend on details of how the directories were originally
created under Windows).

I<Note>:
This function does not handle drive names, backslashes etc.

See also C<guestfs_realpath>.");

  ("vfs_type", (RString "fstype", [Device "device"]), 198, [],
   [InitBasicFS, Always, TestOutput (
      [["vfs_type"; "/dev/sda1"]], "ext2")],
   "get the Linux VFS type corresponding to a mounted device",
   "\
This command gets the block device type corresponding to
a mounted device called C<device>.

Usually the result is the name of the Linux VFS module that
is used to mount this device (probably determined automatically
if you used the C<guestfs_mount> call).");

  ("truncate", (RErr, [Pathname "path"]), 199, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["write_file"; "/test"; "some stuff so size is not zero"; "0"];
       ["truncate"; "/test"];
       ["stat"; "/test"]], [CompareWithInt ("size", 0)])],
   "truncate a file to zero size",
   "\
This command truncates C<path> to a zero-length file.  The
file must exist already.");

  ("truncate_size", (RErr, [Pathname "path"; Int64 "size"]), 200, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["touch"; "/test"];
       ["truncate_size"; "/test"; "1000"];
       ["stat"; "/test"]], [CompareWithInt ("size", 1000)])],
   "truncate a file to a particular size",
   "\
This command truncates C<path> to size C<size> bytes.  The file
must exist already.  If the file is smaller than C<size> then
the file is extended to the required size with null bytes.");

  ("utimens", (RErr, [Pathname "path"; Int64 "atsecs"; Int64 "atnsecs"; Int64 "mtsecs"; Int64 "mtnsecs"]), 201, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["touch"; "/test"];
       ["utimens"; "/test"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/test"]], [CompareWithInt ("mtime", 9876)])],
   "set timestamp of a file with nanosecond precision",
   "\
This command sets the timestamps of a file with nanosecond
precision.

C<atsecs, atnsecs> are the last access time (atime) in secs and
nanoseconds from the epoch.

C<mtsecs, mtnsecs> are the last modification time (mtime) in
secs and nanoseconds from the epoch.

If the C<*nsecs> field contains the special value C<-1> then
the corresponding timestamp is set to the current time.  (The
C<*secs> field is ignored in this case).

If the C<*nsecs> field contains the special value C<-2> then
the corresponding timestamp is left unchanged.  (The
C<*secs> field is ignored in this case).");

  ("mkdir_mode", (RErr, [Pathname "path"; Int "mode"]), 202, [],
   [InitBasicFS, Always, TestOutputStruct (
      [["mkdir_mode"; "/test"; "0o111"];
       ["stat"; "/test"]], [CompareWithInt ("mode", 0o40111)])],
   "create a directory with a particular mode",
   "\
This command creates a directory, setting the initial permissions
of the directory to C<mode>.  See also C<guestfs_mkdir>.");

  ("lchown", (RErr, [Int "owner"; Int "group"; Pathname "path"]), 203, [],
   [], (* XXX *)
   "change file owner and group",
   "\
Change the file owner to C<owner> and group to C<group>.
This is like C<guestfs_chown> but if C<path> is a symlink then
the link itself is changed, not the target.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy).");

  ("lstatlist", (RStructList ("statbufs", "stat"), [Pathname "path"; StringList "names"]), 204, [],
   [], (* XXX *)
   "lstat on multiple files",
   "\
This call allows you to perform the C<guestfs_lstat> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of stat structs, with a one-to-one
correspondence to the C<names> list.  If any name did not exist
or could not be lstat'd, then the C<ino> field of that structure
is set to C<-1>.

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
See also C<guestfs_lxattrlist> for a similarly efficient call
for getting extended attributes.  Very long directory listings
might cause the protocol message size to be exceeded, causing
this call to fail.  The caller must split up such requests
into smaller groups of names.");

  ("lxattrlist", (RStructList ("xattrs", "xattr"), [Pathname "path"; StringList "names"]), 205, [Optional "linuxxattrs"],
   [], (* XXX *)
   "lgetxattr on multiple files",
   "\
This call allows you to get the extended attributes
of multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a flat list of xattr structs which must be
interpreted sequentially.  The first xattr struct always has a zero-length
C<attrname>.  C<attrval> in this struct is zero-length
to indicate there was an error doing C<lgetxattr> for this
file, I<or> is a C string which is a decimal number
(the number of following attributes for this file, which could
be C<\"0\">).  Then after the first xattr struct are the
zero or more attributes for the first named file.
This repeats for the second and subsequent files.

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
See also C<guestfs_lstatlist> for a similarly efficient call
for getting standard stats.  Very long directory listings
might cause the protocol message size to be exceeded, causing
this call to fail.  The caller must split up such requests
into smaller groups of names.");

  ("readlinklist", (RStringList "links", [Pathname "path"; StringList "names"]), 206, [],
   [], (* XXX *)
   "readlink on multiple files",
   "\
This call allows you to do a C<readlink> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of strings, with a one-to-one
correspondence to the C<names> list.  Each string is the
value of the symbol link.

If the C<readlink(2)> operation fails on any name, then
the corresponding result string is the empty string C<\"\">.
However the whole operation is completed even if there
were C<readlink(2)> errors, and so you can call this
function with names where you don't know if they are
symbolic links already (albeit slightly less efficient).

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
Very long directory listings might cause the protocol
message size to be exceeded, causing
this call to fail.  The caller must split up such requests
into smaller groups of names.");

  ("pread", (RBufferOut "content", [Pathname "path"; Int "count"; Int64 "offset"]), 207, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputBuffer (
      [["pread"; "/known-4"; "1"; "3"]], "\n");
    InitISOFS, Always, TestOutputBuffer (
      [["pread"; "/empty"; "0"; "100"]], "")],
   "read part of a file",
   "\
This command lets you read part of a file.  It reads C<count>
bytes of the file, starting at C<offset>, from file C<path>.

This may read fewer bytes than requested.  For further details
see the L<pread(2)> system call.");

  ("part_init", (RErr, [Device "device"; String "parttype"]), 208, [],
   [InitEmpty, Always, TestRun (
      [["part_init"; "/dev/sda"; "gpt"]])],
   "create an empty partition table",
   "\
This creates an empty partition table on C<device> of one of the
partition types listed below.  Usually C<parttype> should be
either C<msdos> or C<gpt> (for large disks).

Initially there are no partitions.  Following this, you should
call C<guestfs_part_add> for each partition required.

Possible values for C<parttype> are:

=over 4

=item B<efi> | B<gpt>

Intel EFI / GPT partition table.

This is recommended for >= 2 TB partitions that will be accessed
from Linux and Intel-based Mac OS X.  It also has limited backwards
compatibility with the C<mbr> format.

=item B<mbr> | B<msdos>

The standard PC \"Master Boot Record\" (MBR) format used
by MS-DOS and Windows.  This partition type will B<only> work
for device sizes up to 2 TB.  For large disks we recommend
using C<gpt>.

=back

Other partition table types that may work but are not
supported include:

=over 4

=item B<aix>

AIX disk labels.

=item B<amiga> | B<rdb>

Amiga \"Rigid Disk Block\" format.

=item B<bsd>

BSD disk labels.

=item B<dasd>

DASD, used on IBM mainframes.

=item B<dvh>

MIPS/SGI volumes.

=item B<mac>

Old Mac partition format.  Modern Macs use C<gpt>.

=item B<pc98>

NEC PC-98 format, common in Japan apparently.

=item B<sun>

Sun disk labels.

=back");

  ("part_add", (RErr, [Device "device"; String "prlogex"; Int64 "startsect"; Int64 "endsect"]), 209, [],
   [InitEmpty, Always, TestRun (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "primary"; "1"; "-1"]]);
    InitEmpty, Always, TestRun (
      [["part_init"; "/dev/sda"; "gpt"];
       ["part_add"; "/dev/sda"; "primary"; "34"; "127"];
       ["part_add"; "/dev/sda"; "primary"; "128"; "-34"]]);
    InitEmpty, Always, TestRun (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "primary"; "32"; "127"];
       ["part_add"; "/dev/sda"; "primary"; "128"; "255"];
       ["part_add"; "/dev/sda"; "primary"; "256"; "511"];
       ["part_add"; "/dev/sda"; "primary"; "512"; "-1"]])],
   "add a partition to the device",
   "\
This command adds a partition to C<device>.  If there is no partition
table on the device, call C<guestfs_part_init> first.

The C<prlogex> parameter is the type of partition.  Normally you
should pass C<p> or C<primary> here, but MBR partition tables also
support C<l> (or C<logical>) and C<e> (or C<extended>) partition
types.

C<startsect> and C<endsect> are the start and end of the partition
in I<sectors>.  C<endsect> may be negative, which means it counts
backwards from the end of the disk (C<-1> is the last sector).

Creating a partition which covers the whole disk is not so easy.
Use C<guestfs_part_disk> to do that.");

  ("part_disk", (RErr, [Device "device"; String "parttype"]), 210, [DangerWillRobinson],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"]]);
    InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "gpt"]])],
   "partition whole disk with a single primary partition",
   "\
This command is simply a combination of C<guestfs_part_init>
followed by C<guestfs_part_add> to create a single primary partition
covering the whole disk.

C<parttype> is the partition table type, usually C<mbr> or C<gpt>,
but other possible values are described in C<guestfs_part_init>.");

  ("part_set_bootable", (RErr, [Device "device"; Int "partnum"; Bool "bootable"]), 211, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["part_set_bootable"; "/dev/sda"; "1"; "true"]])],
   "make a partition bootable",
   "\
This sets the bootable flag on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The bootable flag is used by some PC BIOSes to determine which
partition to boot from.  It is by no means universally recognized,
and in any case if your operating system installed a boot
sector on the device itself, then that takes precedence.");

  ("part_set_name", (RErr, [Device "device"; Int "partnum"; String "name"]), 212, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "gpt"];
       ["part_set_name"; "/dev/sda"; "1"; "thepartname"]])],
   "set partition name",
   "\
This sets the partition name on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The partition name can only be set on certain types of partition
table.  This works on C<gpt> but not on C<mbr> partitions.");

  ("part_list", (RStructList ("partitions", "partition"), [Device "device"]), 213, [],
   [], (* XXX Add a regression test for this. *)
   "list partitions on a device",
   "\
This command parses the partition table on C<device> and
returns the list of partitions found.

The fields in the returned structure are:

=over 4

=item B<part_num>

Partition number, counting from 1.

=item B<part_start>

Start of the partition I<in bytes>.  To get sectors you have to
divide by the device's sector size, see C<guestfs_blockdev_getss>.

=item B<part_end>

End of the partition in bytes.

=item B<part_size>

Size of the partition in bytes.

=back");

  ("part_get_parttype", (RString "parttype", [Device "device"]), 214, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "gpt"];
       ["part_get_parttype"; "/dev/sda"]], "gpt")],
   "get the partition table type",
   "\
This command examines the partition table on C<device> and
returns the partition table type (format) being used.

Common return values include: C<msdos> (a DOS/Windows style MBR
partition table), C<gpt> (a GPT/EFI-style partition table).  Other
values are possible, although unusual.  See C<guestfs_part_init>
for a full list.");

  ("fill", (RErr, [Int "c"; Int "len"; Pathname "path"]), 215, [],
   [InitBasicFS, Always, TestOutputBuffer (
      [["fill"; "0x63"; "10"; "/test"];
       ["read_file"; "/test"]], "cccccccccc")],
   "fill a file with octets",
   "\
This command creates a new file called C<path>.  The initial
content of the file is C<len> octets of C<c>, where C<c>
must be a number in the range C<[0..255]>.

To fill a file with zero bytes (sparsely), it is
much more efficient to use C<guestfs_truncate_size>.");

  ("available", (RErr, [StringList "groups"]), 216, [],
   [InitNone, Always, TestRun [["available"; ""]]],
   "test availability of some parts of the API",
   "\
This command is used to check the availability of some
groups of functionality in the appliance, which not all builds of
the libguestfs appliance will be able to provide.

The libguestfs groups, and the functions that those
groups correspond to, are listed in L<guestfs(3)/AVAILABILITY>.

The argument C<groups> is a list of group names, eg:
C<[\"inotify\", \"augeas\"]> would check for the availability of
the Linux inotify functions and Augeas (configuration file
editing) functions.

The command returns no error if I<all> requested groups are available.

It fails with an error if one or more of the requested
groups is unavailable in the appliance.

If an unknown group name is included in the
list of groups then an error is always returned.

I<Notes:>

=over 4

=item *

You must call C<guestfs_launch> before calling this function.

The reason is because we don't know what groups are
supported by the appliance/daemon until it is running and can
be queried.

=item *

If a group of functions is available, this does not necessarily
mean that they will work.  You still have to check for errors
when calling individual API functions even if they are
available.

=item *

It is usually the job of distro packagers to build
complete functionality into the libguestfs appliance.
Upstream libguestfs, if built from source with all
requirements satisfied, will support everything.

=item *

This call was added in version C<1.0.80>.  In previous
versions of libguestfs all you could do would be to speculatively
execute a command to find out if the daemon implemented it.
See also C<guestfs_version>.

=back");

  ("dd", (RErr, [Dev_or_Path "src"; Dev_or_Path "dest"]), 217, [],
   [InitBasicFS, Always, TestOutputBuffer (
      [["write_file"; "/src"; "hello, world"; "0"];
       ["dd"; "/src"; "/dest"];
       ["read_file"; "/dest"]], "hello, world")],
   "copy from source to destination using dd",
   "\
This command copies from one source device or file C<src>
to another destination device or file C<dest>.  Normally you
would use this to copy to or from a device or partition, for
example to duplicate a filesystem.

If the destination is a device, it must be as large or larger
than the source file or device, otherwise the copy will fail.
This command cannot do partial copies.");

]

let all_functions = non_daemon_functions @ daemon_functions

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let all_functions_sorted =
  List.sort (fun (n1,_,_,_,_,_,_) (n2,_,_,_,_,_,_) ->
               compare n1 n2) all_functions

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

(* Because we generate extra parsing code for LVM command line tools,
 * we have to pull out the LVM columns separately here.
 *)
let lvm_pv_cols = [
  "pv_name", FString;
  "pv_uuid", FUUID;
  "pv_fmt", FString;
  "pv_size", FBytes;
  "dev_size", FBytes;
  "pv_free", FBytes;
  "pv_used", FBytes;
  "pv_attr", FString (* XXX *);
  "pv_pe_count", FInt64;
  "pv_pe_alloc_count", FInt64;
  "pv_tags", FString;
  "pe_start", FBytes;
  "pv_mda_count", FInt64;
  "pv_mda_free", FBytes;
  (* Not in Fedora 10:
     "pv_mda_size", FBytes;
  *)
]
let lvm_vg_cols = [
  "vg_name", FString;
  "vg_uuid", FUUID;
  "vg_fmt", FString;
  "vg_attr", FString (* XXX *);
  "vg_size", FBytes;
  "vg_free", FBytes;
  "vg_sysid", FString;
  "vg_extent_size", FBytes;
  "vg_extent_count", FInt64;
  "vg_free_count", FInt64;
  "max_lv", FInt64;
  "max_pv", FInt64;
  "pv_count", FInt64;
  "lv_count", FInt64;
  "snap_count", FInt64;
  "vg_seqno", FInt64;
  "vg_tags", FString;
  "vg_mda_count", FInt64;
  "vg_mda_free", FBytes;
  (* Not in Fedora 10:
     "vg_mda_size", FBytes;
  *)
]
let lvm_lv_cols = [
  "lv_name", FString;
  "lv_uuid", FUUID;
  "lv_attr", FString (* XXX *);
  "lv_major", FInt64;
  "lv_minor", FInt64;
  "lv_kernel_major", FInt64;
  "lv_kernel_minor", FInt64;
  "lv_size", FBytes;
  "seg_count", FInt64;
  "origin", FString;
  "snap_percent", FOptPercent;
  "copy_percent", FOptPercent;
  "move_pv", FString;
  "lv_tags", FString;
  "mirror_log", FString;
  "modules", FString;
]

(* Names and fields in all structures (in RStruct and RStructList)
 * that we support.
 *)
let structs = [
  (* The old RIntBool return type, only ever used for aug_defnode.  Do
   * not use this struct in any new code.
   *)
  "int_bool", [
    "i", FInt32;		(* for historical compatibility *)
    "b", FInt32;		(* for historical compatibility *)
  ];

  (* LVM PVs, VGs, LVs. *)
  "lvm_pv", lvm_pv_cols;
  "lvm_vg", lvm_vg_cols;
  "lvm_lv", lvm_lv_cols;

  (* Column names and types from stat structures.
   * NB. Can't use things like 'st_atime' because glibc header files
   * define some of these as macros.  Ugh.
   *)
  "stat", [
    "dev", FInt64;
    "ino", FInt64;
    "mode", FInt64;
    "nlink", FInt64;
    "uid", FInt64;
    "gid", FInt64;
    "rdev", FInt64;
    "size", FInt64;
    "blksize", FInt64;
    "blocks", FInt64;
    "atime", FInt64;
    "mtime", FInt64;
    "ctime", FInt64;
  ];
  "statvfs", [
    "bsize", FInt64;
    "frsize", FInt64;
    "blocks", FInt64;
    "bfree", FInt64;
    "bavail", FInt64;
    "files", FInt64;
    "ffree", FInt64;
    "favail", FInt64;
    "fsid", FInt64;
    "flag", FInt64;
    "namemax", FInt64;
  ];

  (* Column names in dirent structure. *)
  "dirent", [
    "ino", FInt64;
    (* 'b' 'c' 'd' 'f' (FIFO) 'l' 'r' (regular file) 's' 'u' '?' *)
    "ftyp", FChar;
    "name", FString;
  ];

  (* Version numbers. *)
  "version", [
    "major", FInt64;
    "minor", FInt64;
    "release", FInt64;
    "extra", FString;
  ];

  (* Extended attribute. *)
  "xattr", [
    "attrname", FString;
    "attrval", FBuffer;
  ];

  (* Inotify events. *)
  "inotify_event", [
    "in_wd", FInt64;
    "in_mask", FUInt32;
    "in_cookie", FUInt32;
    "in_name", FString;
  ];

  (* Partition table entry. *)
  "partition", [
    "part_num", FInt32;
    "part_start", FBytes;
    "part_end", FBytes;
    "part_size", FBytes;
  ];
] (* end of structs *)

(* Ugh, Java has to be different ..
 * These names are also used by the Haskell bindings.
 *)
let java_structs = [
  "int_bool", "IntBool";
  "lvm_pv", "PV";
  "lvm_vg", "VG";
  "lvm_lv", "LV";
  "stat", "Stat";
  "statvfs", "StatVFS";
  "dirent", "Dirent";
  "version", "Version";
  "xattr", "XAttr";
  "inotify_event", "INotifyEvent";
  "partition", "Partition";
]

(* What structs are actually returned. *)
type rstructs_used_t = RStructOnly | RStructListOnly | RStructAndList

(* Returns a list of RStruct/RStructList structs that are returned
 * by any function.  Each element of returned list is a pair:
 *
 * (structname, RStructOnly)
 *    == there exists function which returns RStruct (_, structname)
 * (structname, RStructListOnly)
 *    == there exists function which returns RStructList (_, structname)
 * (structname, RStructAndList)
 *    == there are functions returning both RStruct (_, structname)
 *                                      and RStructList (_, structname)
 *)
let rstructs_used_by functions =
  (* ||| is a "logical OR" for rstructs_used_t *)
  let (|||) a b =
    match a, b with
    | RStructAndList, _
    | _, RStructAndList -> RStructAndList
    | RStructOnly, RStructListOnly
    | RStructListOnly, RStructOnly -> RStructAndList
    | RStructOnly, RStructOnly -> RStructOnly
    | RStructListOnly, RStructListOnly -> RStructListOnly
  in

  let h = Hashtbl.create 13 in

  (* if elem->oldv exists, update entry using ||| operator,
   * else just add elem->newv to the hash
   *)
  let update elem newv =
    try  let oldv = Hashtbl.find h elem in
         Hashtbl.replace h elem (newv ||| oldv)
    with Not_found -> Hashtbl.add h elem newv
  in

  List.iter (
    fun (_, style, _, _, _, _, _) ->
      match fst style with
      | RStruct (_, structname) -> update structname RStructOnly
      | RStructList (_, structname) -> update structname RStructListOnly
      | _ -> ()
  ) functions;

  (* return key->values as a list of (key,value) *)
  Hashtbl.fold (fun key value xs -> (key, value) :: xs) h []

(* Used for testing language bindings. *)
type callt =
  | CallString of string
  | CallOptString of string option
  | CallStringList of string list
  | CallInt of int
  | CallInt64 of int64
  | CallBool of bool

(* Used to memoize the result of pod2text. *)
let pod2text_memo_filename = "src/.pod2text.data"
let pod2text_memo : ((int * string * string), string list) Hashtbl.t =
  try
    let chan = open_in pod2text_memo_filename in
    let v = input_value chan in
    close_in chan;
    v
  with
    _ -> Hashtbl.create 13
let pod2text_memo_updated () =
  let chan = open_out pod2text_memo_filename in
  output_value chan pod2text_memo;
  close_out chan

(* Useful functions.
 * Note we don't want to use any external OCaml libraries which
 * makes this a bit harder than it should be.
 *)
module StringMap = Map.Make (String)

let failwithf fs = ksprintf failwith fs

let unique = let i = ref 0 in fun () -> incr i; !i

let replace_char s c1 c2 =
  let s2 = String.copy s in
  let r = ref false in
  for i = 0 to String.length s2 - 1 do
    if String.unsafe_get s2 i = c1 then (
      String.unsafe_set s2 i c2;
      r := true
    )
  done;
  if not !r then s else s2

let isspace c =
  c = ' '
  (* || c = '\f' *) || c = '\n' || c = '\r' || c = '\t' (* || c = '\v' *)

let triml ?(test = isspace) str =
  let i = ref 0 in
  let n = ref (String.length str) in
  while !n > 0 && test str.[!i]; do
    decr n;
    incr i
  done;
  if !i = 0 then str
  else String.sub str !i !n

let trimr ?(test = isspace) str =
  let n = ref (String.length str) in
  while !n > 0 && test str.[!n-1]; do
    decr n
  done;
  if !n = String.length str then str
  else String.sub str 0 !n

let trim ?(test = isspace) str =
  trimr ~test (triml ~test str)

let rec find s sub =
  let len = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i <= len-sublen then (
      let rec loop2 j =
        if j < sublen then (
          if s.[i+j] = sub.[j] then loop2 (j+1)
          else -1
        ) else
          i (* found *)
      in
      let r = loop2 0 in
      if r = -1 then loop (i+1) else r
    ) else
      -1 (* not found *)
  in
  loop 0

let rec replace_str s s1 s2 =
  let len = String.length s in
  let sublen = String.length s1 in
  let i = find s s1 in
  if i = -1 then s
  else (
    let s' = String.sub s 0 i in
    let s'' = String.sub s (i+sublen) (len-i-sublen) in
    s' ^ s2 ^ replace_str s'' s1 s2
  )

let rec string_split sep str =
  let len = String.length str in
  let seplen = String.length sep in
  let i = find str sep in
  if i = -1 then [str]
  else (
    let s' = String.sub str 0 i in
    let s'' = String.sub str (i+seplen) (len-i-seplen) in
    s' :: string_split sep s''
  )

let files_equal n1 n2 =
  let cmd = sprintf "cmp -s %s %s" (Filename.quote n1) (Filename.quote n2) in
  match Sys.command cmd with
  | 0 -> true
  | 1 -> false
  | i -> failwithf "%s: failed with error code %d" cmd i

let rec filter_map f = function
  | [] -> []
  | x :: xs ->
      match f x with
      | Some y -> y :: filter_map f xs
      | None -> filter_map f xs

let rec find_map f = function
  | [] -> raise Not_found
  | x :: xs ->
      match f x with
      | Some y -> y
      | None -> find_map f xs

let iteri f xs =
  let rec loop i = function
    | [] -> ()
    | x :: xs -> f i x; loop (i+1) xs
  in
  loop 0 xs

let mapi f xs =
  let rec loop i = function
    | [] -> []
    | x :: xs -> let r = f i x in r :: loop (i+1) xs
  in
  loop 0 xs

let count_chars c str =
  let count = ref 0 in
  for i = 0 to String.length str - 1 do
    if c = String.unsafe_get str i then incr count
  done;
  !count

let name_of_argt = function
  | Pathname n | Device n | Dev_or_Path n | String n | OptString n
  | StringList n | DeviceList n | Bool n | Int n | Int64 n
  | FileIn n | FileOut n -> n

let java_name_of_struct typ =
  try List.assoc typ java_structs
  with Not_found ->
    failwithf
      "java_name_of_struct: no java_structs entry corresponding to %s" typ

let cols_of_struct typ =
  try List.assoc typ structs
  with Not_found ->
    failwithf "cols_of_struct: unknown struct %s" typ

let seq_of_test = function
  | TestRun s | TestOutput (s, _) | TestOutputList (s, _)
  | TestOutputListOfDevices (s, _)
  | TestOutputInt (s, _) | TestOutputIntOp (s, _, _)
  | TestOutputTrue s | TestOutputFalse s
  | TestOutputLength (s, _) | TestOutputBuffer (s, _)
  | TestOutputStruct (s, _)
  | TestLastFail s -> s

(* Handling for function flags. *)
let protocol_limit_warning =
  "Because of the message protocol, there is a transfer limit
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP."

let danger_will_robinson =
  "B<This command is dangerous.  Without careful use you
can easily destroy all your data>."

let deprecation_notice flags =
  try
    let alt =
      find_map (function DeprecatedBy str -> Some str | _ -> None) flags in
    let txt =
      sprintf "This function is deprecated.
In new code, use the C<%s> call instead.

Deprecated functions will not be removed from the API, but the
fact that they are deprecated indicates that there are problems
with correct use of these functions." alt in
    Some txt
  with
    Not_found -> None

(* Create list of optional groups. *)
let optgroups =
  let h = Hashtbl.create 13 in
  List.iter (
    fun (name, _, _, flags, _, _, _) ->
      List.iter (
        function
        | Optional group ->
            let names = try Hashtbl.find h group with Not_found -> [] in
            Hashtbl.replace h group (name :: names)
        | _ -> ()
      ) flags
  ) daemon_functions;
  let groups = Hashtbl.fold (fun k _ ks -> k :: ks) h [] in
  let groups =
    List.map (
      fun group -> group, List.sort compare (Hashtbl.find h group)
    ) groups in
  List.sort (fun x y -> compare (fst x) (fst y)) groups

(* Check function names etc. for consistency. *)
let check_functions () =
  let contains_uppercase str =
    let len = String.length str in
    let rec loop i =
      if i >= len then false
      else (
        let c = str.[i] in
        if c >= 'A' && c <= 'Z' then true
        else loop (i+1)
      )
    in
    loop 0
  in

  (* Check function names. *)
  List.iter (
    fun (name, _, _, _, _, _, _) ->
      if String.length name >= 7 && String.sub name 0 7 = "guestfs" then
        failwithf "function name %s does not need 'guestfs' prefix" name;
      if name = "" then
        failwithf "function name is empty";
      if name.[0] < 'a' || name.[0] > 'z' then
        failwithf "function name %s must start with lowercase a-z" name;
      if String.contains name '-' then
        failwithf "function name %s should not contain '-', use '_' instead."
          name
  ) all_functions;

  (* Check function parameter/return names. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      let check_arg_ret_name n =
        if contains_uppercase n then
          failwithf "%s param/ret %s should not contain uppercase chars"
            name n;
        if String.contains n '-' || String.contains n '_' then
          failwithf "%s param/ret %s should not contain '-' or '_'"
            name n;
        if n = "value" then
          failwithf "%s has a param/ret called 'value', which causes conflicts in the OCaml bindings, use something like 'val' or a more descriptive name" name;
        if n = "int" || n = "char" || n = "short" || n = "long" then
          failwithf "%s has a param/ret which conflicts with a C type (eg. 'int', 'char' etc.)" name;
        if n = "i" || n = "n" then
          failwithf "%s has a param/ret called 'i' or 'n', which will cause some conflicts in the generated code" name;
        if n = "argv" || n = "args" then
          failwithf "%s has a param/ret called 'argv' or 'args', which will cause some conflicts in the generated code" name;

        (* List Haskell, OCaml and C keywords here.
         * http://www.haskell.org/haskellwiki/Keywords
         * http://caml.inria.fr/pub/docs/manual-ocaml/lex.html#operator-char
         * http://en.wikipedia.org/wiki/C_syntax#Reserved_keywords
         * Formatted via: cat c haskell ocaml|sort -u|grep -vE '_|^val$' \
         *   |perl -pe 's/(.+)/"$1";/'|fmt -70
         * Omitting _-containing words, since they're handled above.
         * Omitting the OCaml reserved word, "val", is ok,
         * and saves us from renaming several parameters.
         *)
        let reserved = [
          "and"; "as"; "asr"; "assert"; "auto"; "begin"; "break"; "case";
          "char"; "class"; "const"; "constraint"; "continue"; "data";
          "default"; "deriving"; "do"; "done"; "double"; "downto"; "else";
          "end"; "enum"; "exception"; "extern"; "external"; "false"; "float";
          "for"; "forall"; "foreign"; "fun"; "function"; "functor"; "goto";
          "hiding"; "if"; "import"; "in"; "include"; "infix"; "infixl";
          "infixr"; "inherit"; "initializer"; "inline"; "instance"; "int";
          "land"; "lazy"; "let"; "long"; "lor"; "lsl"; "lsr"; "lxor";
          "match"; "mdo"; "method"; "mod"; "module"; "mutable"; "new";
          "newtype"; "object"; "of"; "open"; "or"; "private"; "qualified";
          "rec"; "register"; "restrict"; "return"; "short"; "sig"; "signed";
          "sizeof"; "static"; "struct"; "switch"; "then"; "to"; "true"; "try";
          "type"; "typedef"; "union"; "unsigned"; "virtual"; "void";
          "volatile"; "when"; "where"; "while";
          ] in
        if List.mem n reserved then
          failwithf "%s has param/ret using reserved word %s" name n;
      in

      (match fst style with
       | RErr -> ()
       | RInt n | RInt64 n | RBool n
       | RConstString n | RConstOptString n | RString n
       | RStringList n | RStruct (n, _) | RStructList (n, _)
       | RHashtable n | RBufferOut n ->
           check_arg_ret_name n
      );
      List.iter (fun arg -> check_arg_ret_name (name_of_argt arg)) (snd style)
  ) all_functions;

  (* Check short descriptions. *)
  List.iter (
    fun (name, _, _, _, _, shortdesc, _) ->
      if shortdesc.[0] <> Char.lowercase shortdesc.[0] then
        failwithf "short description of %s should begin with lowercase." name;
      let c = shortdesc.[String.length shortdesc-1] in
      if c = '\n' || c = '.' then
        failwithf "short description of %s should not end with . or \\n." name
  ) all_functions;

  (* Check long dscriptions. *)
  List.iter (
    fun (name, _, _, _, _, _, longdesc) ->
      if longdesc.[String.length longdesc-1] = '\n' then
        failwithf "long description of %s should not end with \\n." name
  ) all_functions;

  (* Check proc_nrs. *)
  List.iter (
    fun (name, _, proc_nr, _, _, _, _) ->
      if proc_nr <= 0 then
        failwithf "daemon function %s should have proc_nr > 0" name
  ) daemon_functions;

  List.iter (
    fun (name, _, proc_nr, _, _, _, _) ->
      if proc_nr <> -1 then
        failwithf "non-daemon function %s should have proc_nr -1" name
  ) non_daemon_functions;

  let proc_nrs =
    List.map (fun (name, _, proc_nr, _, _, _, _) -> name, proc_nr)
      daemon_functions in
  let proc_nrs =
    List.sort (fun (_,nr1) (_,nr2) -> compare nr1 nr2) proc_nrs in
  let rec loop = function
    | [] -> ()
    | [_] -> ()
    | (name1,nr1) :: ((name2,nr2) :: _ as rest) when nr1 < nr2 ->
        loop rest
    | (name1,nr1) :: (name2,nr2) :: _ ->
        failwithf "%s and %s have conflicting procedure numbers (%d, %d)"
          name1 name2 nr1 nr2
  in
  loop proc_nrs;

  (* Check tests. *)
  List.iter (
    function
      (* Ignore functions that have no tests.  We generate a
       * warning when the user does 'make check' instead.
       *)
    | name, _, _, _, [], _, _ -> ()
    | name, _, _, _, tests, _, _ ->
        let funcs =
          List.map (
            fun (_, _, test) ->
              match seq_of_test test with
              | [] ->
                  failwithf "%s has a test containing an empty sequence" name
              | cmds -> List.map List.hd cmds
          ) tests in
        let funcs = List.flatten funcs in

        let tested = List.mem name funcs in

        if not tested then
          failwithf "function %s has tests but does not test itself" name
  ) all_functions

(* 'pr' prints to the current output file. *)
let chan = ref Pervasives.stdout
let lines = ref 0
let pr fs =
  ksprintf
    (fun str ->
       let i = count_chars '\n' str in
       lines := !lines + i;
       output_string !chan str
    ) fs

let copyright_years =
  let this_year = 1900 + (localtime (time ())).tm_year in
  if this_year > 2009 then sprintf "2009-%04d" this_year else "2009"

(* Generate a header block in a number of standard styles. *)
type comment_style =
    CStyle | CPlusPlusStyle | HashStyle | OCamlStyle | HaskellStyle
type license = GPLv2plus | LGPLv2plus

let generate_header ?(extra_inputs = []) comment license =
  let inputs = "src/generator.ml" :: extra_inputs in
  let c = match comment with
    | CStyle ->         pr "/* "; " *"
    | CPlusPlusStyle -> pr "// "; "//"
    | HashStyle ->      pr "# ";  "#"
    | OCamlStyle ->     pr "(* "; " *"
    | HaskellStyle ->   pr "{- "; "  " in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED FROM:\n" c;
  List.iter (pr "%s   %s\n" c) inputs;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) %s Red Hat Inc.\n" c copyright_years;
  pr "%s\n" c;
  (match license with
   | GPLv2plus ->
       pr "%s This program is free software; you can redistribute it and/or modify\n" c;
       pr "%s it under the terms of the GNU General Public License as published by\n" c;
       pr "%s the Free Software Foundation; either version 2 of the License, or\n" c;
       pr "%s (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This program is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n" c;
       pr "%s GNU General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU General Public License along\n" c;
       pr "%s with this program; if not, write to the Free Software Foundation, Inc.,\n" c;
       pr "%s 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.\n" c;

   | LGPLv2plus ->
       pr "%s This library is free software; you can redistribute it and/or\n" c;
       pr "%s modify it under the terms of the GNU Lesser General Public\n" c;
       pr "%s License as published by the Free Software Foundation; either\n" c;
       pr "%s version 2 of the License, or (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This library is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU\n" c;
       pr "%s Lesser General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU Lesser General Public\n" c;
       pr "%s License along with this library; if not, write to the Free Software\n" c;
       pr "%s Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA\n" c;
  );
  (match comment with
   | CStyle -> pr " */\n"
   | CPlusPlusStyle
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
   | HaskellStyle -> pr "-}\n"
  );
  pr "\n"

(* Start of main code generation functions below this line. *)

(* Generate the pod documentation for the C API. *)
let rec generate_actions_pod () =
  List.iter (
    fun (shortname, style, _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let name = "guestfs_" ^ shortname in
        pr "=head2 %s\n\n" name;
        pr " ";
        generate_prototype ~extern:false ~handle:"handle" name style;
        pr "\n\n";
        pr "%s\n\n" longdesc;
        (match fst style with
         | RErr ->
             pr "This function returns 0 on success or -1 on error.\n\n"
         | RInt _ ->
             pr "On error this function returns -1.\n\n"
         | RInt64 _ ->
             pr "On error this function returns -1.\n\n"
         | RBool _ ->
             pr "This function returns a C truth value on success or -1 on error.\n\n"
         | RConstString _ ->
             pr "This function returns a string, or NULL on error.
The string is owned by the guest handle and must I<not> be freed.\n\n"
         | RConstOptString _ ->
             pr "This function returns a string which may be NULL.
There is way to return an error from this function.
The string is owned by the guest handle and must I<not> be freed.\n\n"
         | RString _ ->
             pr "This function returns a string, or NULL on error.
I<The caller must free the returned string after use>.\n\n"
         | RStringList _ ->
             pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
         | RStruct (_, typ) ->
             pr "This function returns a C<struct guestfs_%s *>,
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s> after use>.\n\n" typ typ
         | RStructList (_, typ) ->
             pr "This function returns a C<struct guestfs_%s_list *>
(see E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<guestfs_free_%s_list> after use>.\n\n" typ typ
         | RHashtable _ ->
             pr "This function returns a NULL-terminated array of
strings, or NULL if there was an error.
The array of strings will always have length C<2n+1>, where
C<n> keys and values alternate, followed by the trailing NULL entry.
I<The caller must free the strings and the array after use>.\n\n"
         | RBufferOut _ ->
             pr "This function returns a buffer, or NULL on error.
The size of the returned buffer is written to C<*size_r>.
I<The caller must free the returned buffer after use>.\n\n"
        );
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        if List.mem DangerWillRobinson flags then
          pr "%s\n\n" danger_will_robinson;
        match deprecation_notice flags with
        | None -> ()
        | Some txt -> pr "%s\n\n" txt
      )
  ) all_functions_sorted

and generate_structs_pod () =
  (* Structs documentation. *)
  List.iter (
    fun (typ, cols) ->
      pr "=head2 guestfs_%s\n" typ;
      pr "\n";
      pr " struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "   char %s;\n" name
        | name, FUInt32 -> pr "   uint32_t %s;\n" name
        | name, FInt32 -> pr "   int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "   uint64_t %s;\n" name
        | name, FInt64 -> pr "   int64_t %s;\n" name
        | name, FString -> pr "   char *%s;\n" name
        | name, FBuffer ->
            pr "   /* The next two fields describe a byte array. */\n";
            pr "   uint32_t %s_len;\n" name;
            pr "   char *%s;\n" name
        | name, FUUID ->
            pr "   /* The next field is NOT nul-terminated, be careful when printing it: */\n";
            pr "   char %s[32];\n" name
        | name, FOptPercent ->
            pr "   /* The next field is [0..100] or -1 meaning 'not present': */\n";
            pr "   float %s;\n" name
      ) cols;
      pr " };\n";
      pr " \n";
      pr " struct guestfs_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr " \n";
      pr " void guestfs_free_%s (struct guestfs_free_%s *);\n" typ typ;
      pr " void guestfs_free_%s_list (struct guestfs_free_%s_list *);\n"
        typ typ;
      pr "\n"
  ) structs

and generate_availability_pod () =
  (* Availability documentation. *)
  pr "=over 4\n";
  pr "\n";
  List.iter (
    fun (group, functions) ->
      pr "=item B<%s>\n" group;
      pr "\n";
      pr "The following functions:\n";
      List.iter (pr "L</guestfs_%s>\n") functions;
      pr "\n"
  ) optgroups;
  pr "=back\n";
  pr "\n"

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.
 *
 * We have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
and generate_xdr () =
  generate_header CStyle LGPLv2plus;

  (* This has to be defined to get around a limitation in Sun's rpcgen. *)
  pr "typedef string str<>;\n";
  pr "\n";

  (* Internal structures. *)
  List.iter (
    function
    | typ, cols ->
        pr "struct guestfs_int_%s {\n" typ;
        List.iter (function
                   | name, FChar -> pr "  char %s;\n" name
                   | name, FString -> pr "  string %s<>;\n" name
                   | name, FBuffer -> pr "  opaque %s<>;\n" name
                   | name, FUUID -> pr "  opaque %s[32];\n" name
                   | name, (FInt32|FUInt32) -> pr "  int %s;\n" name
                   | name, (FInt64|FUInt64|FBytes) -> pr "  hyper %s;\n" name
                   | name, FOptPercent -> pr "  float %s;\n" name
                  ) cols;
        pr "};\n";
        pr "\n";
        pr "typedef struct guestfs_int_%s guestfs_int_%s_list<>;\n" typ typ;
        pr "\n";
  ) structs;

  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (match snd style with
       | [] -> ()
       | args ->
           pr "struct %s_args {\n" name;
           List.iter (
             function
             | Pathname n | Device n | Dev_or_Path n | String n ->
                 pr "  string %s<>;\n" n
             | OptString n -> pr "  str *%s;\n" n
             | StringList n | DeviceList n -> pr "  str %s<>;\n" n
             | Bool n -> pr "  bool %s;\n" n
             | Int n -> pr "  int %s;\n" n
             | Int64 n -> pr "  hyper %s;\n" n
             | FileIn _ | FileOut _ -> ()
           ) args;
           pr "};\n\n"
      );
      (match fst style with
       | RErr -> ()
       | RInt n ->
           pr "struct %s_ret {\n" name;
           pr "  int %s;\n" n;
           pr "};\n\n"
       | RInt64 n ->
           pr "struct %s_ret {\n" name;
           pr "  hyper %s;\n" n;
           pr "};\n\n"
       | RBool n ->
           pr "struct %s_ret {\n" name;
           pr "  bool %s;\n" n;
           pr "};\n\n"
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString n ->
           pr "struct %s_ret {\n" name;
           pr "  string %s<>;\n" n;
           pr "};\n\n"
       | RStringList n ->
           pr "struct %s_ret {\n" name;
           pr "  str %s<>;\n" n;
           pr "};\n\n"
       | RStruct (n, typ) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_int_%s %s;\n" typ n;
           pr "};\n\n"
       | RStructList (n, typ) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_int_%s_list %s;\n" typ n;
           pr "};\n\n"
       | RHashtable n ->
           pr "struct %s_ret {\n" name;
           pr "  str %s<>;\n" n;
           pr "};\n\n"
       | RBufferOut n ->
           pr "struct %s_ret {\n" name;
           pr "  opaque %s<>;\n" n;
           pr "};\n\n"
      );
  ) daemon_functions;

  (* Table of procedure numbers. *)
  pr "enum guestfs_procedure {\n";
  List.iter (
    fun (shortname, _, proc_nr, _, _, _, _) ->
      pr "  GUESTFS_PROC_%s = %d,\n" (String.uppercase shortname) proc_nr
  ) daemon_functions;
  pr "  GUESTFS_PROC_NR_PROCS\n";
  pr "};\n";
  pr "\n";

  (* Having to choose a maximum message size is annoying for several
   * reasons (it limits what we can do in the API), but it (a) makes
   * the protocol a lot simpler, and (b) provides a bound on the size
   * of the daemon which operates in limited memory space.  For large
   * file transfers you should use FTP.
   *)
  pr "const GUESTFS_MESSAGE_MAX = %d;\n" (4 * 1024 * 1024);
  pr "\n";

  (* Message header, etc. *)
  pr "\
/* The communication protocol is now documented in the guestfs(3)
 * manpage.
 */

const GUESTFS_PROGRAM = 0x2000F5F5;
const GUESTFS_PROTOCOL_VERSION = 1;

/* These constants must be larger than any possible message length. */
const GUESTFS_LAUNCH_FLAG = 0xf5f55ff5;
const GUESTFS_CANCEL_FLAG = 0xffffeeee;

enum guestfs_message_direction {
  GUESTFS_DIRECTION_CALL = 0,        /* client -> daemon */
  GUESTFS_DIRECTION_REPLY = 1        /* daemon -> client */
};

enum guestfs_message_status {
  GUESTFS_STATUS_OK = 0,
  GUESTFS_STATUS_ERROR = 1
};

const GUESTFS_ERROR_LEN = 256;

struct guestfs_message_error {
  string error_message<GUESTFS_ERROR_LEN>;
};

struct guestfs_message_header {
  unsigned prog;                     /* GUESTFS_PROGRAM */
  unsigned vers;                     /* GUESTFS_PROTOCOL_VERSION */
  guestfs_procedure proc;            /* GUESTFS_PROC_x */
  guestfs_message_direction direction;
  unsigned serial;                   /* message serial number */
  guestfs_message_status status;
};

const GUESTFS_MAX_CHUNK_SIZE = 8192;

struct guestfs_chunk {
  int cancel;			     /* if non-zero, transfer is cancelled */
  /* data size is 0 bytes if the transfer has finished successfully */
  opaque data<GUESTFS_MAX_CHUNK_SIZE>;
};
"

(* Generate the guestfs-structs.h file. *)
and generate_structs_h () =
  generate_header CStyle LGPLv2plus;

  (* This is a public exported header file containing various
   * structures.  The structures are carefully written to have
   * exactly the same in-memory format as the XDR structures that
   * we use on the wire to the daemon.  The reason for creating
   * copies of these structures here is just so we don't have to
   * export the whole of guestfs_protocol.h (which includes much
   * unrelated and XDR-dependent stuff that we don't want to be
   * public, or required by clients).
   *
   * To reiterate, we will pass these structures to and from the
   * client with a simple assignment or memcpy, so the format
   * must be identical to what rpcgen / the RFC defines.
   *)

  (* Public structures. *)
  List.iter (
    fun (typ, cols) ->
      pr "struct guestfs_%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "  char %s;\n" name
        | name, FString -> pr "  char *%s;\n" name
        | name, FBuffer ->
            pr "  uint32_t %s_len;\n" name;
            pr "  char *%s;\n" name
        | name, FUUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
        | name, FUInt32 -> pr "  uint32_t %s;\n" name
        | name, FInt32 -> pr "  int32_t %s;\n" name
        | name, (FUInt64|FBytes) -> pr "  uint64_t %s;\n" name
        | name, FInt64 -> pr "  int64_t %s;\n" name
        | name, FOptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
      ) cols;
      pr "};\n";
      pr "\n";
      pr "struct guestfs_%s_list {\n" typ;
      pr "  uint32_t len;\n";
      pr "  struct guestfs_%s *val;\n" typ;
      pr "};\n";
      pr "\n";
      pr "extern void guestfs_free_%s (struct guestfs_%s *);\n" typ typ;
      pr "extern void guestfs_free_%s_list (struct guestfs_%s_list *);\n" typ typ;
      pr "\n"
  ) structs

(* Generate the guestfs-actions.h file. *)
and generate_actions_h () =
  generate_header CStyle LGPLv2plus;
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"handle"
        name style
  ) all_functions

(* Generate the guestfs-internal-actions.h file. *)
and generate_internal_actions_h () =
  generate_header CStyle LGPLv2plus;
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs__" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"handle"
        name style
  ) non_daemon_functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"

#define error guestfs_error
//#define perrorf guestfs_perrorf
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
//#define safe_strdup guestfs_safe_strdup
#define safe_memdup guestfs_safe_memdup

/* Check the return message from a call for validity. */
static int
check_reply_header (guestfs_h *g,
                    const struct guestfs_message_header *hdr,
                    unsigned int proc_nr, unsigned int serial)
{
  if (hdr->prog != GUESTFS_PROGRAM) {
    error (g, \"wrong program (%%d/%%d)\", hdr->prog, GUESTFS_PROGRAM);
    return -1;
  }
  if (hdr->vers != GUESTFS_PROTOCOL_VERSION) {
    error (g, \"wrong protocol version (%%d/%%d)\",
           hdr->vers, GUESTFS_PROTOCOL_VERSION);
    return -1;
  }
  if (hdr->direction != GUESTFS_DIRECTION_REPLY) {
    error (g, \"unexpected message direction (%%d/%%d)\",
           hdr->direction, GUESTFS_DIRECTION_REPLY);
    return -1;
  }
  if (hdr->proc != proc_nr) {
    error (g, \"unexpected procedure number (%%d/%%d)\", hdr->proc, proc_nr);
    return -1;
  }
  if (hdr->serial != serial) {
    error (g, \"unexpected serial (%%d/%%d)\", hdr->serial, serial);
    return -1;
  }

  return 0;
}

/* Check we are in the right state to run a high-level action. */
static int
check_state (guestfs_h *g, const char *caller)
{
  if (!guestfs__is_ready (g)) {
    if (guestfs__is_config (g) || guestfs__is_launching (g))
      error (g, \"%%s: call launch before using this function\\n(in guestfish, don't forget to use the 'run' command)\",
        caller);
    else
      error (g, \"%%s called from the wrong state, %%d != READY\",
        caller, guestfs__get_state (g));
    return -1;
  }
  return 0;
}

";

  (* Generate code to generate guestfish call traces. *)
  let trace_call shortname style =
    pr "  if (guestfs__get_trace (g)) {\n";

    let needs_i =
      List.exists (function
                   | StringList _ | DeviceList _ -> true
                   | _ -> false) (snd style) in
    if needs_i then (
      pr "    int i;\n";
      pr "\n"
    );

    pr "    printf (\"%s\");\n" shortname;
    List.iter (
      function
      | String n			(* strings *)
      | Device n
      | Pathname n
      | Dev_or_Path n
      | FileIn n
      | FileOut n ->
          (* guestfish doesn't support string escaping, so neither do we *)
          pr "    printf (\" \\\"%%s\\\"\", %s);\n" n
      | OptString n ->			(* string option *)
          pr "    if (%s) printf (\" \\\"%%s\\\"\", %s);\n" n n;
          pr "    else printf (\" null\");\n"
      | StringList n
      | DeviceList n ->			(* string list *)
          pr "    putchar (' ');\n";
          pr "    putchar ('\"');\n";
          pr "    for (i = 0; %s[i]; ++i) {\n" n;
          pr "      if (i > 0) putchar (' ');\n";
          pr "      fputs (%s[i], stdout);\n" n;
          pr "    }\n";
          pr "    putchar ('\"');\n";
      | Bool n ->			(* boolean *)
          pr "    fputs (%s ? \" true\" : \" false\", stdout);\n" n
      | Int n ->			(* int *)
          pr "    printf (\" %%d\", %s);\n" n
      | Int64 n ->
          pr "    printf (\" %%\" PRIi64, %s);\n" n
    ) (snd style);
    pr "    putchar ('\\n');\n";
    pr "  }\n";
    pr "\n";
  in

  (* For non-daemon functions, generate a wrapper around each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" name style;
      pr "{\n";
      trace_call shortname style;
      pr "  return guestfs__%s " shortname;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      pr "}\n";
      pr "\n"
  ) non_daemon_functions;

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (* Generate the action stub. *)
      generate_prototype ~extern:false ~semicolon:false ~newline:true
        ~handle:"g" name style;

      let error_code =
        match fst style with
        | RErr | RInt _ | RInt64 _ | RBool _ -> "-1"
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RString _ | RStringList _
        | RStruct _ | RStructList _
        | RHashtable _ | RBufferOut _ ->
            "NULL" in

      pr "{\n";

      (match snd style with
       | [] -> ()
       | _ -> pr "  struct %s_args args;\n" name
      );

      pr "  guestfs_message_header hdr;\n";
      pr "  guestfs_message_error err;\n";
      let has_ret =
        match fst style with
        | RErr -> false
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RInt _ | RInt64 _
        | RBool _ | RString _ | RStringList _
        | RStruct _ | RStructList _
        | RHashtable _ | RBufferOut _ ->
            pr "  struct %s_ret ret;\n" name;
            true in

      pr "  int serial;\n";
      pr "  int r;\n";
      pr "\n";
      trace_call shortname style;
      pr "  if (check_state (g, \"%s\") == -1) return %s;\n" name error_code;
      pr "  guestfs___set_busy (g);\n";
      pr "\n";

      (* Send the main header and arguments. *)
      (match snd style with
       | [] ->
           pr "  serial = guestfs___send (g, GUESTFS_PROC_%s, NULL, NULL);\n"
             (String.uppercase shortname)
       | args ->
           List.iter (
             function
             | Pathname n | Device n | Dev_or_Path n | String n ->
                 pr "  args.%s = (char *) %s;\n" n n
             | OptString n ->
                 pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
             | StringList n | DeviceList n ->
                 pr "  args.%s.%s_val = (char **) %s;\n" n n n;
                 pr "  for (args.%s.%s_len = 0; %s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
             | Bool n ->
                 pr "  args.%s = %s;\n" n n
             | Int n ->
                 pr "  args.%s = %s;\n" n n
             | Int64 n ->
                 pr "  args.%s = %s;\n" n n
             | FileIn _ | FileOut _ -> ()
           ) args;
           pr "  serial = guestfs___send (g, GUESTFS_PROC_%s,\n"
             (String.uppercase shortname);
           pr "        (xdrproc_t) xdr_%s_args, (char *) &args);\n"
             name;
      );
      pr "  if (serial == -1) {\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Send any additional files (FileIn) requested. *)
      let need_read_reply_label = ref false in
      List.iter (
        function
        | FileIn n ->
            pr "  r = guestfs___send_file (g, %s);\n" n;
            pr "  if (r == -1) {\n";
            pr "    guestfs___end_busy (g);\n";
            pr "    return %s;\n" error_code;
            pr "  }\n";
            pr "  if (r == -2) /* daemon cancelled */\n";
            pr "    goto read_reply;\n";
            need_read_reply_label := true;
            pr "\n";
        | _ -> ()
      ) (snd style);

      (* Wait for the reply from the remote end. *)
      if !need_read_reply_label then pr " read_reply:\n";
      pr "  memset (&hdr, 0, sizeof hdr);\n";
      pr "  memset (&err, 0, sizeof err);\n";
      if has_ret then pr "  memset (&ret, 0, sizeof ret);\n";
      pr "\n";
      pr "  r = guestfs___recv (g, \"%s\", &hdr, &err,\n        " shortname;
      if not has_ret then
        pr "NULL, NULL"
      else
        pr "(xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret" shortname;
      pr ");\n";

      pr "  if (r == -1) {\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &hdr, GUESTFS_PROC_%s, serial) == -1) {\n"
        (String.uppercase shortname);
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    error (g, \"%%s: %%s\", \"%s\", err.error_message);\n" shortname;
      pr "    free (err.error_message);\n";
      pr "    guestfs___end_busy (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Expecting to receive further files (FileOut)? *)
      List.iter (
        function
        | FileOut n ->
            pr "  if (guestfs___recv_file (g, %s) == -1) {\n" n;
            pr "    guestfs___end_busy (g);\n";
            pr "    return %s;\n" error_code;
            pr "  }\n";
            pr "\n";
        | _ -> ()
      ) (snd style);

      pr "  guestfs___end_busy (g);\n";

      (match fst style with
       | RErr -> pr "  return 0;\n"
       | RInt n | RInt64 n | RBool n ->
           pr "  return ret.%s;\n" n
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString n ->
           pr "  return ret.%s; /* caller will free */\n" n
       | RStringList n | RHashtable n ->
           pr "  /* caller will free this, but we need to add a NULL entry */\n";
           pr "  ret.%s.%s_val =\n" n n;
           pr "    safe_realloc (g, ret.%s.%s_val,\n" n n;
           pr "                  sizeof (char *) * (ret.%s.%s_len + 1));\n"
             n n;
           pr "  ret.%s.%s_val[ret.%s.%s_len] = NULL;\n" n n n n;
           pr "  return ret.%s.%s_val;\n" n n
       | RStruct (n, _) ->
           pr "  /* caller will free this */\n";
           pr "  return safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
       | RStructList (n, _) ->
           pr "  /* caller will free this */\n";
           pr "  return safe_memdup (g, &ret.%s, sizeof (ret.%s));\n" n n
       | RBufferOut n ->
           pr "  /* RBufferOut is tricky: If the buffer is zero-length, then\n";
           pr "   * _val might be NULL here.  To make the API saner for\n";
           pr "   * callers, we turn this case into a unique pointer (using\n";
           pr "   * malloc(1)).\n";
           pr "   */\n";
           pr "  if (ret.%s.%s_len > 0) {\n" n n;
           pr "    *size_r = ret.%s.%s_len;\n" n n;
           pr "    return ret.%s.%s_val; /* caller will free */\n" n n;
           pr "  } else {\n";
           pr "    free (ret.%s.%s_val);\n" n n;
           pr "    char *p = safe_malloc (g, 1);\n";
           pr "    *size_r = ret.%s.%s_len;\n" n n;
           pr "    return p;\n";
           pr "  }\n";
      );

      pr "}\n\n"
  ) daemon_functions;

  (* Functions to free structures. *)
  pr "/* Structure-freeing functions.  These rely on the fact that the\n";
  pr " * structure format is identical to the XDR format.  See note in\n";
  pr " * generator.ml.\n";
  pr " */\n";
  pr "\n";

  List.iter (
    fun (typ, _) ->
      pr "void\n";
      pr "guestfs_free_%s (struct guestfs_%s *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

      pr "void\n";
      pr "guestfs_free_%s_list (struct guestfs_%s_list *x)\n" typ typ;
      pr "{\n";
      pr "  xdr_free ((xdrproc_t) xdr_guestfs_int_%s_list, (char *) x);\n" typ;
      pr "  free (x);\n";
      pr "}\n";
      pr "\n";

  ) structs;

(* Generate daemon/actions.h. *)
and generate_daemon_actions_h () =
  generate_header CStyle GPLv2plus;

  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      generate_prototype
        ~single_line:true ~newline:true ~in_daemon:true ~prefix:"do_"
        name style;
  ) daemon_functions

(* Generate the server-side stubs. *)
and generate_daemon_actions () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <rpc/types.h>\n";
  pr "#include <rpc/xdr.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"c-ctype.h\"\n";
  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "#include \"actions.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      (* Generate server-side stubs. *)
      pr "static void %s_stub (XDR *xdr_in)\n" name;
      pr "{\n";
      let error_code =
        match fst style with
        | RErr | RInt _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RBool _ -> pr "  int r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
        | RStruct (_, typ) -> pr "  guestfs_int_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) -> pr "  guestfs_int_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "  size_t size = 1;\n";
            pr "  char *r;\n";
            "NULL" in

      (match snd style with
       | [] -> ()
       | args ->
           pr "  struct guestfs_%s_args args;\n" name;
           List.iter (
             function
             | Device n | Dev_or_Path n
             | Pathname n
             | String n -> ()
             | OptString n -> pr "  char *%s;\n" n
             | StringList n | DeviceList n -> pr "  char **%s;\n" n
             | Bool n -> pr "  int %s;\n" n
             | Int n -> pr "  int %s;\n" n
             | Int64 n -> pr "  int64_t %s;\n" n
             | FileIn _ | FileOut _ -> ()
           ) args
      );
      pr "\n";

      (match snd style with
       | [] -> ()
       | args ->
           pr "  memset (&args, 0, sizeof args);\n";
           pr "\n";
           pr "  if (!xdr_guestfs_%s_args (xdr_in, &args)) {\n" name;
           pr "    reply_with_error (\"%%s: daemon failed to decode procedure arguments\", \"%s\");\n" name;
           pr "    return;\n";
           pr "  }\n";
           let pr_args n =
             pr "  char *%s = args.%s;\n" n n
           in
           let pr_list_handling_code n =
             pr "  %s = realloc (args.%s.%s_val,\n" n n n;
             pr "                sizeof (char *) * (args.%s.%s_len+1));\n" n n;
             pr "  if (%s == NULL) {\n" n;
             pr "    reply_with_perror (\"realloc\");\n";
             pr "    goto done;\n";
             pr "  }\n";
             pr "  %s[args.%s.%s_len] = NULL;\n" n n n;
             pr "  args.%s.%s_val = %s;\n" n n n;
           in
           List.iter (
             function
             | Pathname n ->
                 pr_args n;
                 pr "  ABS_PATH (%s, goto done);\n" n;
             | Device n ->
                 pr_args n;
                 pr "  RESOLVE_DEVICE (%s, goto done);\n" n;
             | Dev_or_Path n ->
                 pr_args n;
                 pr "  REQUIRE_ROOT_OR_RESOLVE_DEVICE (%s, goto done);\n" n;
             | String n -> pr_args n
             | OptString n -> pr "  %s = args.%s ? *args.%s : NULL;\n" n n n
             | StringList n ->
                 pr_list_handling_code n;
             | DeviceList n ->
                 pr_list_handling_code n;
                 pr "  /* Ensure that each is a device,\n";
                 pr "   * and perform device name translation. */\n";
                 pr "  { int pvi; for (pvi = 0; physvols[pvi] != NULL; ++pvi)\n";
                 pr "    RESOLVE_DEVICE (physvols[pvi], goto done);\n";
                 pr "  }\n";
             | Bool n -> pr "  %s = args.%s;\n" n n
             | Int n -> pr "  %s = args.%s;\n" n n
             | Int64 n -> pr "  %s = args.%s;\n" n n
             | FileIn _ | FileOut _ -> ()
           ) args;
           pr "\n"
      );


      (* this is used at least for do_equal *)
      if List.exists (function Pathname _ -> true | _ -> false) (snd style) then (
        (* Emit NEED_ROOT just once, even when there are two or
           more Pathname args *)
        pr "  NEED_ROOT (goto done);\n";
      );

      (* Don't want to call the impl with any FileIn or FileOut
       * parameters, since these go "outside" the RPC protocol.
       *)
      let args' =
        List.filter (function FileIn _ | FileOut _ -> false | _ -> true)
          (snd style) in
      pr "  r = do_%s " name;
      generate_c_call_args (fst style, args');
      pr ";\n";

      (match fst style with
       | RErr | RInt _ | RInt64 _ | RBool _
       | RConstString _ | RConstOptString _
       | RString _ | RStringList _ | RHashtable _
       | RStruct (_, _) | RStructList (_, _) ->
           pr "  if (r == %s)\n" error_code;
           pr "    /* do_%s has already called reply_with_error */\n" name;
           pr "    goto done;\n";
           pr "\n"
       | RBufferOut _ ->
           pr "  /* size == 0 && r == NULL could be a non-error case (just\n";
           pr "   * an ordinary zero-length buffer), so be careful ...\n";
           pr "   */\n";
           pr "  if (size == 1 && r == %s)\n" error_code;
           pr "    /* do_%s has already called reply_with_error */\n" name;
           pr "    goto done;\n";
           pr "\n"
      );

      (* If there are any FileOut parameters, then the impl must
       * send its own reply.
       *)
      let no_reply =
        List.exists (function FileOut _ -> true | _ -> false) (snd style) in
      if no_reply then
        pr "  /* do_%s has already sent a reply */\n" name
      else (
        match fst style with
        | RErr -> pr "  reply (NULL, NULL);\n"
        | RInt n | RInt64 n | RBool n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = r;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RConstString _ | RConstOptString _ ->
            failwithf "RConstString|RConstOptString cannot be used by daemon functions"
        | RString n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = r;\n" n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free (r);\n"
        | RStringList n | RHashtable n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_len = count_strings (r);\n" n n;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free_strings (r);\n"
        | RStruct (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RStructList (n, _) ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s = *r;\n" n;
            pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
              name
        | RBufferOut n ->
            pr "  struct guestfs_%s_ret ret;\n" name;
            pr "  ret.%s.%s_val = r;\n" n n;
            pr "  ret.%s.%s_len = size;\n" n n;
            pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n"
              name;
            pr "  free (r);\n"
      );

      (* Free the args. *)
      (match snd style with
       | [] ->
           pr "done: ;\n";
       | _ ->
           pr "done:\n";
           pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_args, (char *) &args);\n"
             name
      );

      pr "}\n\n";
  ) daemon_functions;

  (* Dispatch function. *)
  pr "void dispatch_incoming_message (XDR *xdr_in)\n";
  pr "{\n";
  pr "  switch (proc_nr) {\n";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "    case GUESTFS_PROC_%s:\n" (String.uppercase name);
      pr "      %s_stub (xdr_in);\n" name;
      pr "      break;\n"
  ) daemon_functions;

  pr "    default:\n";
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d, set LIBGUESTFS_PATH to point to the matching libguestfs appliance directory\", proc_nr);\n";
  pr "  }\n";
  pr "}\n";
  pr "\n";

  (* LVM columns and tokenization functions. *)
  (* XXX This generates crap code.  We should rethink how we
   * do this parsing.
   *)
  List.iter (
    function
    | typ, cols ->
        pr "static const char *lvm_%s_cols = \"%s\";\n"
          typ (String.concat "," (List.map fst cols));
        pr "\n";

        pr "static int lvm_tokenize_%s (char *str, guestfs_int_lvm_%s *r)\n" typ typ;
        pr "{\n";
        pr "  char *tok, *p, *next;\n";
        pr "  int i, j;\n";
        pr "\n";
        (*
          pr "  fprintf (stderr, \"%%s: <<%%s>>\\n\", __func__, str);\n";
          pr "\n";
        *)
        pr "  if (!str) {\n";
        pr "    fprintf (stderr, \"%%s: failed: passed a NULL string\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  if (!*str || c_isspace (*str)) {\n";
        pr "    fprintf (stderr, \"%%s: failed: passed a empty string or one beginning with whitespace\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  tok = str;\n";
        List.iter (
          fun (name, coltype) ->
            pr "  if (!tok) {\n";
            pr "    fprintf (stderr, \"%%s: failed: string finished early, around token %%s\\n\", __func__, \"%s\");\n" name;
            pr "    return -1;\n";
            pr "  }\n";
            pr "  p = strchrnul (tok, ',');\n";
            pr "  if (*p) next = p+1; else next = NULL;\n";
            pr "  *p = '\\0';\n";
            (match coltype with
             | FString ->
                 pr "  r->%s = strdup (tok);\n" name;
                 pr "  if (r->%s == NULL) {\n" name;
                 pr "    perror (\"strdup\");\n";
                 pr "    return -1;\n";
                 pr "  }\n"
             | FUUID ->
                 pr "  for (i = j = 0; i < 32; ++j) {\n";
                 pr "    if (tok[j] == '\\0') {\n";
                 pr "      fprintf (stderr, \"%%s: failed to parse UUID from '%%s'\\n\", __func__, tok);\n";
                 pr "      return -1;\n";
                 pr "    } else if (tok[j] != '-')\n";
                 pr "      r->%s[i++] = tok[j];\n" name;
                 pr "  }\n";
             | FBytes ->
                 pr "  if (sscanf (tok, \"%%\"SCNu64, &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FInt64 ->
                 pr "  if (sscanf (tok, \"%%\"SCNi64, &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse int '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FOptPercent ->
                 pr "  if (tok[0] == '\\0')\n";
                 pr "    r->%s = -1;\n" name;
                 pr "  else if (sscanf (tok, \"%%f\", &r->%s) != 1) {\n" name;
                 pr "    fprintf (stderr, \"%%s: failed to parse float '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
                 pr "    return -1;\n";
                 pr "  }\n";
             | FBuffer | FInt32 | FUInt32 | FUInt64 | FChar ->
                 assert false (* can never be an LVM column *)
            );
            pr "  tok = next;\n";
        ) cols;

        pr "  if (tok != NULL) {\n";
        pr "    fprintf (stderr, \"%%s: failed: extra tokens at end of string\\n\", __func__);\n";
        pr "    return -1;\n";
        pr "  }\n";
        pr "  return 0;\n";
        pr "}\n";
        pr "\n";

        pr "guestfs_int_lvm_%s_list *\n" typ;
        pr "parse_command_line_%ss (void)\n" typ;
        pr "{\n";
        pr "  char *out, *err;\n";
        pr "  char *p, *pend;\n";
        pr "  int r, i;\n";
        pr "  guestfs_int_lvm_%s_list *ret;\n" typ;
        pr "  void *newp;\n";
        pr "\n";
        pr "  ret = malloc (sizeof *ret);\n";
        pr "  if (!ret) {\n";
        pr "    reply_with_perror (\"malloc\");\n";
        pr "    return NULL;\n";
        pr "  }\n";
        pr "\n";
        pr "  ret->guestfs_int_lvm_%s_list_len = 0;\n" typ;
        pr "  ret->guestfs_int_lvm_%s_list_val = NULL;\n" typ;
        pr "\n";
        pr "  r = command (&out, &err,\n";
        pr "	       \"/sbin/lvm\", \"%ss\",\n" typ;
        pr "	       \"-o\", lvm_%s_cols, \"--unbuffered\", \"--noheadings\",\n" typ;
        pr "	       \"--nosuffix\", \"--separator\", \",\", \"--units\", \"b\", NULL);\n";
        pr "  if (r == -1) {\n";
        pr "    reply_with_error (\"%%s\", err);\n";
        pr "    free (out);\n";
        pr "    free (err);\n";
        pr "    free (ret);\n";
        pr "    return NULL;\n";
        pr "  }\n";
        pr "\n";
        pr "  free (err);\n";
        pr "\n";
        pr "  /* Tokenize each line of the output. */\n";
        pr "  p = out;\n";
        pr "  i = 0;\n";
        pr "  while (p) {\n";
        pr "    pend = strchr (p, '\\n');	/* Get the next line of output. */\n";
        pr "    if (pend) {\n";
        pr "      *pend = '\\0';\n";
        pr "      pend++;\n";
        pr "    }\n";
        pr "\n";
        pr "    while (*p && c_isspace (*p))	/* Skip any leading whitespace. */\n";
        pr "      p++;\n";
        pr "\n";
        pr "    if (!*p) {			/* Empty line?  Skip it. */\n";
        pr "      p = pend;\n";
        pr "      continue;\n";
        pr "    }\n";
        pr "\n";
        pr "    /* Allocate some space to store this next entry. */\n";
        pr "    newp = realloc (ret->guestfs_int_lvm_%s_list_val,\n" typ;
        pr "		    sizeof (guestfs_int_lvm_%s) * (i+1));\n" typ;
        pr "    if (newp == NULL) {\n";
        pr "      reply_with_perror (\"realloc\");\n";
        pr "      free (ret->guestfs_int_lvm_%s_list_val);\n" typ;
        pr "      free (ret);\n";
        pr "      free (out);\n";
        pr "      return NULL;\n";
        pr "    }\n";
        pr "    ret->guestfs_int_lvm_%s_list_val = newp;\n" typ;
        pr "\n";
        pr "    /* Tokenize the next entry. */\n";
        pr "    r = lvm_tokenize_%s (p, &ret->guestfs_int_lvm_%s_list_val[i]);\n" typ typ;
        pr "    if (r == -1) {\n";
        pr "      reply_with_error (\"failed to parse output of '%ss' command\");\n" typ;
        pr "      free (ret->guestfs_int_lvm_%s_list_val);\n" typ;
        pr "      free (ret);\n";
        pr "      free (out);\n";
        pr "      return NULL;\n";
        pr "    }\n";
        pr "\n";
        pr "    ++i;\n";
        pr "    p = pend;\n";
        pr "  }\n";
        pr "\n";
        pr "  ret->guestfs_int_lvm_%s_list_len = i;\n" typ;
        pr "\n";
        pr "  free (out);\n";
        pr "  return ret;\n";
        pr "}\n"

  ) ["pv", lvm_pv_cols; "vg", lvm_vg_cols; "lv", lvm_lv_cols]

(* Generate a list of function names, for debugging in the daemon.. *)
and generate_daemon_names () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "\n";

  pr "/* This array is indexed by proc_nr.  See guestfs_protocol.x. */\n";
  pr "const char *function_names[] = {\n";
  List.iter (
    fun (name, _, proc_nr, _, _, _, _) -> pr "  [%d] = \"%s\",\n" proc_nr name
  ) daemon_functions;
  pr "};\n";

(* Generate the optional groups for the daemon to implement
 * guestfs_available.
 *)
and generate_daemon_optgroups_c () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"optgroups.h\"\n";
  pr "\n";

  pr "struct optgroup optgroups[] = {\n";
  List.iter (
    fun (group, _) ->
      pr "  { \"%s\", optgroup_%s_available },\n" group group
  ) optgroups;
  pr "  { NULL, NULL }\n";
  pr "};\n"

and generate_daemon_optgroups_h () =
  generate_header CStyle GPLv2plus;

  List.iter (
    fun (group, _) ->
      pr "extern int optgroup_%s_available (void);\n" group
  ) optgroups

(* Generate the tests. *)
and generate_tests () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <fcntl.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"

static guestfs_h *g;
static int suppress_error = 0;

static void print_error (guestfs_h *g, void *data, const char *msg)
{
  if (!suppress_error)
    fprintf (stderr, \"%%s\\n\", msg);
}

/* FIXME: nearly identical code appears in fish.c */
static void print_strings (char *const *argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf (\"\\t%%s\\n\", argv[argc]);
}

/*
static void print_table (char const *const *argv)
{
  int i;

  for (i = 0; argv[i] != NULL; i += 2)
    printf (\"%%s: %%s\\n\", argv[i], argv[i+1]);
}
*/

";

  (* Generate a list of commands which are not tested anywhere. *)
  pr "static void no_test_warnings (void)\n";
  pr "{\n";

  let hash : (string, bool) Hashtbl.t = Hashtbl.create 13 in
  List.iter (
    fun (_, _, _, _, tests, _, _) ->
      let tests = filter_map (
        function
        | (_, (Always|If _|Unless _), test) -> Some test
        | (_, Disabled, _) -> None
      ) tests in
      let seq = List.concat (List.map seq_of_test tests) in
      let cmds_tested = List.map List.hd seq in
      List.iter (fun cmd -> Hashtbl.replace hash cmd true) cmds_tested
  ) all_functions;

  List.iter (
    fun (name, _, _, _, _, _, _) ->
      if not (Hashtbl.mem hash name) then
        pr "  fprintf (stderr, \"warning: \\\"guestfs_%s\\\" has no tests\\n\");\n" name
  ) all_functions;

  pr "}\n";
  pr "\n";

  (* Generate the actual tests.  Note that we generate the tests
   * in reverse order, deliberately, so that (in general) the
   * newest tests run first.  This makes it quicker and easier to
   * debug them.
   *)
  let test_names =
    List.map (
      fun (name, _, _, flags, tests, _, _) ->
        mapi (generate_one_test name flags) tests
    ) (List.rev all_functions) in
  let test_names = List.concat test_names in
  let nr_tests = List.length test_names in

  pr "\
int main (int argc, char *argv[])
{
  char c = 0;
  unsigned long int n_failed = 0;
  const char *filename;
  int fd;
  int nr_tests, test_num = 0;

  setbuf (stdout, NULL);

  no_test_warnings ();

  g = guestfs_create ();
  if (g == NULL) {
    printf (\"guestfs_create FAILED\\n\");
    exit (EXIT_FAILURE);
  }

  guestfs_set_error_handler (g, print_error, NULL);

  guestfs_set_path (g, \"../appliance\");

  filename = \"test1.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (EXIT_FAILURE);
  }

  filename = \"test2.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (EXIT_FAILURE);
  }

  filename = \"test3.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_ro (g, \"../images/test.iso\") == -1) {
    printf (\"guestfs_add_drive_ro ../images/test.iso FAILED\\n\");
    exit (EXIT_FAILURE);
  }

  if (guestfs_launch (g) == -1) {
    printf (\"guestfs_launch FAILED\\n\");
    exit (EXIT_FAILURE);
  }

  /* Set a timeout in case qemu hangs during launch (RHBZ#505329). */
  alarm (600);

  /* Cancel previous alarm. */
  alarm (0);

  nr_tests = %d;

" (500 * 1024 * 1024) (50 * 1024 * 1024) (10 * 1024 * 1024) nr_tests;

  iteri (
    fun i test_name ->
      pr "  test_num++;\n";
      pr "  printf (\"%%3d/%%3d %s\\n\", test_num, nr_tests);\n" test_name;
      pr "  if (%s () == -1) {\n" test_name;
      pr "    printf (\"%s FAILED\\n\");\n" test_name;
      pr "    n_failed++;\n";
      pr "  }\n";
  ) test_names;
  pr "\n";

  pr "  guestfs_close (g);\n";
  pr "  unlink (\"test1.img\");\n";
  pr "  unlink (\"test2.img\");\n";
  pr "  unlink (\"test3.img\");\n";
  pr "\n";

  pr "  if (n_failed > 0) {\n";
  pr "    printf (\"***** %%lu / %%d tests FAILED *****\\n\", n_failed, nr_tests);\n";
  pr "    exit (EXIT_FAILURE);\n";
  pr "  }\n";
  pr "\n";

  pr "  exit (EXIT_SUCCESS);\n";
  pr "}\n"

and generate_one_test name flags i (init, prereq, test) =
  let test_name = sprintf "test_%s_%d" name i in

  pr "\
static int %s_skip (void)
{
  const char *str;

  str = getenv (\"TEST_ONLY\");
  if (str)
    return strstr (str, \"%s\") == NULL;
  str = getenv (\"SKIP_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  str = getenv (\"SKIP_TEST_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  return 0;
}

" test_name name (String.uppercase test_name) (String.uppercase name);

  (match prereq with
   | Disabled | Always -> ()
   | If code | Unless code ->
       pr "static int %s_prereq (void)\n" test_name;
       pr "{\n";
       pr "  %s\n" code;
       pr "}\n";
       pr "\n";
  );

  pr "\
static int %s (void)
{
  if (%s_skip ()) {
    printf (\"        %%s skipped (reason: environment variable set)\\n\", \"%s\");
    return 0;
  }

" test_name test_name test_name;

  (* Optional functions should only be tested if the relevant
   * support is available in the daemon.
   *)
  List.iter (
    function
    | Optional group ->
        pr "  {\n";
        pr "    const char *groups[] = { \"%s\", NULL };\n" group;
        pr "    int r;\n";
        pr "    suppress_error = 1;\n";
        pr "    r = guestfs_available (g, (char **) groups);\n";
        pr "    suppress_error = 0;\n";
        pr "    if (r == -1) {\n";
        pr "      printf (\"        %%s skipped (reason: group %%s not available in daemon)\\n\", \"%s\", groups[0]);\n" test_name;
        pr "      return 0;\n";
        pr "    }\n";
        pr "  }\n";
    | _ -> ()
  ) flags;

  (match prereq with
   | Disabled ->
       pr "  printf (\"        %%s skipped (reason: test disabled in generator)\\n\", \"%s\");\n" test_name
   | If _ ->
       pr "  if (! %s_prereq ()) {\n" test_name;
       pr "    printf (\"        %%s skipped (reason: test prerequisite)\\n\", \"%s\");\n" test_name;
       pr "    return 0;\n";
       pr "  }\n";
       pr "\n";
       generate_one_test_body name i test_name init test;
   | Unless _ ->
       pr "  if (%s_prereq ()) {\n" test_name;
       pr "    printf (\"        %%s skipped (reason: test prerequisite)\\n\", \"%s\");\n" test_name;
       pr "    return 0;\n";
       pr "  }\n";
       pr "\n";
       generate_one_test_body name i test_name init test;
   | Always ->
       generate_one_test_body name i test_name init test
  );

  pr "  return 0;\n";
  pr "}\n";
  pr "\n";
  test_name

and generate_one_test_body name i test_name init test =
  (match init with
   | InitNone (* XXX at some point, InitNone and InitEmpty became
               * folded together as the same thing.  Really we should
               * make InitNone do nothing at all, but the tests may
               * need to be checked to make sure this is OK.
               *)
   | InitEmpty ->
       pr "  /* InitNone|InitEmpty for %s */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"]]
   | InitPartition ->
       pr "  /* InitPartition for %s: create /dev/sda1 */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"]]
   | InitBasicFS ->
       pr "  /* InitBasicFS for %s: create ext2 on /dev/sda1 */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"];
          ["mkfs"; "ext2"; "/dev/sda1"];
          ["mount"; "/dev/sda1"; "/"]]
   | InitBasicFSonLVM ->
       pr "  /* InitBasicFSonLVM for %s: create ext2 on /dev/VG/LV */\n"
         test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"];
          ["pvcreate"; "/dev/sda1"];
          ["vgcreate"; "VG"; "/dev/sda1"];
          ["lvcreate"; "LV"; "VG"; "8"];
          ["mkfs"; "ext2"; "/dev/VG/LV"];
          ["mount"; "/dev/VG/LV"; "/"]]
   | InitISOFS ->
       pr "  /* InitISOFS for %s */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["mount_ro"; "/dev/sdd"; "/"]]
  );

  let get_seq_last = function
    | [] ->
        failwithf "%s: you cannot use [] (empty list) when expecting a command"
          test_name
    | seq ->
        let seq = List.rev seq in
        List.rev (List.tl seq), List.hd seq
  in

  match test with
  | TestRun seq ->
      pr "  /* TestRun for %s (%d) */\n" name i;
      List.iter (generate_test_command_call test_name) seq
  | TestOutput (seq, expected) ->
      pr "  /* TestOutput for %s (%d) */\n" name i;
      pr "  const char *expected = \"%s\";\n" (c_quote expected);
      let seq, last = get_seq_last seq in
      let test () =
        pr "    if (STRNEQ (r, expected)) {\n";
        pr "      fprintf (stderr, \"%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", expected, r);\n" test_name;
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputList (seq, expected) ->
      pr "  /* TestOutputList for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        iteri (
          fun i str ->
            pr "    if (!r[%d]) {\n" i;
            pr "      fprintf (stderr, \"%s: short list returned from command\\n\");\n" test_name;
            pr "      print_strings (r);\n";
            pr "      return -1;\n";
            pr "    }\n";
            pr "    {\n";
            pr "      const char *expected = \"%s\";\n" (c_quote str);
            pr "      if (STRNEQ (r[%d], expected)) {\n" i;
            pr "        fprintf (stderr, \"%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", expected, r[%d]);\n" test_name i;
            pr "        return -1;\n";
            pr "      }\n";
            pr "    }\n"
        ) expected;
        pr "    if (r[%d] != NULL) {\n" (List.length expected);
        pr "      fprintf (stderr, \"%s: extra elements returned from command\\n\");\n"
          test_name;
        pr "      print_strings (r);\n";
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputListOfDevices (seq, expected) ->
      pr "  /* TestOutputListOfDevices for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        iteri (
          fun i str ->
            pr "    if (!r[%d]) {\n" i;
            pr "      fprintf (stderr, \"%s: short list returned from command\\n\");\n" test_name;
            pr "      print_strings (r);\n";
            pr "      return -1;\n";
            pr "    }\n";
            pr "    {\n";
            pr "      const char *expected = \"%s\";\n" (c_quote str);
            pr "      r[%d][5] = 's';\n" i;
            pr "      if (STRNEQ (r[%d], expected)) {\n" i;
            pr "        fprintf (stderr, \"%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", expected, r[%d]);\n" test_name i;
            pr "        return -1;\n";
            pr "      }\n";
            pr "    }\n"
        ) expected;
        pr "    if (r[%d] != NULL) {\n" (List.length expected);
        pr "      fprintf (stderr, \"%s: extra elements returned from command\\n\");\n"
          test_name;
        pr "      print_strings (r);\n";
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputInt (seq, expected) ->
      pr "  /* TestOutputInt for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        pr "    if (r != %d) {\n" expected;
        pr "      fprintf (stderr, \"%s: expected %d but got %%d\\n\","
          test_name expected;
        pr "               (int) r);\n";
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputIntOp (seq, op, expected) ->
      pr "  /* TestOutputIntOp for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        pr "    if (! (r %s %d)) {\n" op expected;
        pr "      fprintf (stderr, \"%s: expected %s %d but got %%d\\n\","
          test_name op expected;
        pr "               (int) r);\n";
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputTrue seq ->
      pr "  /* TestOutputTrue for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        pr "    if (!r) {\n";
        pr "      fprintf (stderr, \"%s: expected true, got false\\n\");\n"
          test_name;
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputFalse seq ->
      pr "  /* TestOutputFalse for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        pr "    if (r) {\n";
        pr "      fprintf (stderr, \"%s: expected false, got true\\n\");\n"
          test_name;
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputLength (seq, expected) ->
      pr "  /* TestOutputLength for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        pr "    int j;\n";
        pr "    for (j = 0; j < %d; ++j)\n" expected;
        pr "      if (r[j] == NULL) {\n";
        pr "        fprintf (stderr, \"%s: short list returned\\n\");\n"
          test_name;
        pr "        print_strings (r);\n";
        pr "        return -1;\n";
        pr "      }\n";
        pr "    if (r[j] != NULL) {\n";
        pr "      fprintf (stderr, \"%s: long list returned\\n\");\n"
          test_name;
        pr "      print_strings (r);\n";
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputBuffer (seq, expected) ->
      pr "  /* TestOutputBuffer for %s (%d) */\n" name i;
      pr "  const char *expected = \"%s\";\n" (c_quote expected);
      let seq, last = get_seq_last seq in
      let len = String.length expected in
      let test () =
        pr "    if (size != %d) {\n" len;
        pr "      fprintf (stderr, \"%s: returned size of buffer wrong, expected %d but got %%zu\\n\", size);\n" test_name len;
        pr "      return -1;\n";
        pr "    }\n";
        pr "    if (STRNEQLEN (r, expected, size)) {\n";
        pr "      fprintf (stderr, \"%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", expected, r);\n" test_name;
        pr "      return -1;\n";
        pr "    }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputStruct (seq, checks) ->
      pr "  /* TestOutputStruct for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test () =
        List.iter (
          function
          | CompareWithInt (field, expected) ->
              pr "    if (r->%s != %d) {\n" field expected;
              pr "      fprintf (stderr, \"%s: %s was %%d, expected %d\\n\",\n"
                test_name field expected;
              pr "               (int) r->%s);\n" field;
              pr "      return -1;\n";
              pr "    }\n"
          | CompareWithIntOp (field, op, expected) ->
              pr "    if (!(r->%s %s %d)) {\n" field op expected;
              pr "      fprintf (stderr, \"%s: %s was %%d, expected %s %d\\n\",\n"
                test_name field op expected;
              pr "               (int) r->%s);\n" field;
              pr "      return -1;\n";
              pr "    }\n"
          | CompareWithString (field, expected) ->
              pr "    if (STRNEQ (r->%s, \"%s\")) {\n" field expected;
              pr "      fprintf (stderr, \"%s: %s was \"%%s\", expected \"%s\"\\n\",\n"
                test_name field expected;
              pr "               r->%s);\n" field;
              pr "      return -1;\n";
              pr "    }\n"
          | CompareFieldsIntEq (field1, field2) ->
              pr "    if (r->%s != r->%s) {\n" field1 field2;
              pr "      fprintf (stderr, \"%s: %s (%%d) <> %s (%%d)\\n\",\n"
                test_name field1 field2;
              pr "               (int) r->%s, (int) r->%s);\n" field1 field2;
              pr "      return -1;\n";
              pr "    }\n"
          | CompareFieldsStrEq (field1, field2) ->
              pr "    if (STRNEQ (r->%s, r->%s)) {\n" field1 field2;
              pr "      fprintf (stderr, \"%s: %s (\"%%s\") <> %s (\"%%s\")\\n\",\n"
                test_name field1 field2;
              pr "               r->%s, r->%s);\n" field1 field2;
              pr "      return -1;\n";
              pr "    }\n"
        ) checks
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestLastFail seq ->
      pr "  /* TestLastFail for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call test_name ~expect_error:true last

(* Generate the code to run a command, leaving the result in 'r'.
 * If you expect to get an error then you should set expect_error:true.
 *)
and generate_test_command_call ?(expect_error = false) ?test test_name cmd =
  match cmd with
  | [] -> assert false
  | name :: args ->
      (* Look up the command to find out what args/ret it has. *)
      let style =
        try
          let _, style, _, _, _, _, _ =
            List.find (fun (n, _, _, _, _, _, _) -> n = name) all_functions in
          style
        with Not_found ->
          failwithf "%s: in test, command %s was not found" test_name name in

      if List.length (snd style) <> List.length args then
        failwithf "%s: in test, wrong number of args given to %s"
          test_name name;

      pr "  {\n";

      List.iter (
        function
        | OptString n, "NULL" -> ()
        | Pathname n, arg
        | Device n, arg
        | Dev_or_Path n, arg
        | String n, arg
        | OptString n, arg ->
            pr "    const char *%s = \"%s\";\n" n (c_quote arg);
        | Int _, _
        | Int64 _, _
        | Bool _, _
        | FileIn _, _ | FileOut _, _ -> ()
        | StringList n, "" | DeviceList n, "" ->
	    pr "    const char *const %s[1] = { NULL };\n" n
        | StringList n, arg | DeviceList n, arg ->
            let strs = string_split " " arg in
            iteri (
              fun i str ->
                pr "    const char *%s_%d = \"%s\";\n" n i (c_quote str);
            ) strs;
            pr "    const char *const %s[] = {\n" n;
            iteri (
              fun i _ -> pr "      %s_%d,\n" n i
            ) strs;
            pr "      NULL\n";
            pr "    };\n";
      ) (List.combine (snd style) args);

      let error_code =
        match fst style with
        | RErr | RInt _ | RBool _ -> pr "    int r;\n"; "-1"
        | RInt64 _ -> pr "    int64_t r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "    const char *r;\n"; "NULL"
        | RString _ -> pr "    char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ ->
            pr "    char **r;\n";
            pr "    int i;\n";
            "NULL"
        | RStruct (_, typ) ->
            pr "    struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "    struct guestfs_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "    char *r;\n";
            pr "    size_t size;\n";
            "NULL" in

      pr "    suppress_error = %d;\n" (if expect_error then 1 else 0);
      pr "    r = guestfs_%s (g" name;

      (* Generate the parameters. *)
      List.iter (
        function
        | OptString _, "NULL" -> pr ", NULL"
        | Pathname n, _
        | Device n, _ | Dev_or_Path n, _
        | String n, _
        | OptString n, _ ->
            pr ", %s" n
        | FileIn _, arg | FileOut _, arg ->
            pr ", \"%s\"" (c_quote arg)
        | StringList n, _ | DeviceList n, _ ->
            pr ", (char **) %s" n
        | Int _, arg ->
            let i =
              try int_of_string arg
              with Failure "int_of_string" ->
                failwithf "%s: expecting an int, but got '%s'" test_name arg in
            pr ", %d" i
        | Int64 _, arg ->
            let i =
              try Int64.of_string arg
              with Failure "int_of_string" ->
                failwithf "%s: expecting an int64, but got '%s'" test_name arg in
            pr ", %Ld" i
        | Bool _, arg ->
            let b = bool_of_string arg in pr ", %d" (if b then 1 else 0)
      ) (List.combine (snd style) args);

      (match fst style with
       | RBufferOut _ -> pr ", &size"
       | _ -> ()
      );

      pr ");\n";

      if not expect_error then
        pr "    if (r == %s)\n" error_code
      else
        pr "    if (r != %s)\n" error_code;
      pr "      return -1;\n";

      (* Insert the test code. *)
      (match test with
       | None -> ()
       | Some f -> f ()
      );

      (match fst style with
       | RErr | RInt _ | RInt64 _ | RBool _
       | RConstString _ | RConstOptString _ -> ()
       | RString _ | RBufferOut _ -> pr "    free (r);\n"
       | RStringList _ | RHashtable _ ->
           pr "    for (i = 0; r[i] != NULL; ++i)\n";
           pr "      free (r[i]);\n";
           pr "    free (r);\n"
       | RStruct (_, typ) ->
           pr "    guestfs_free_%s (r);\n" typ
       | RStructList (_, typ) ->
           pr "    guestfs_free_%s_list (r);\n" typ
      );

      pr "  }\n"

and c_quote str =
  let str = replace_str str "\r" "\\r" in
  let str = replace_str str "\n" "\\n" in
  let str = replace_str str "\t" "\\t" in
  let str = replace_str str "\000" "\\0" in
  str

(* Generate a lot of different functions for guestfish. *)
and generate_fish_cmds () =
  generate_header CStyle GPLv2plus;

  let all_functions =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions in
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "#include \"c-ctype.h\"\n";
  pr "#include \"fish.h\"\n";
  pr "\n";

  (* list_commands function, which implements guestfish -h *)
  pr "void list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", _(\"Command\"), _(\"Description\"));\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, flags, _, shortdesc, _) ->
      let name = replace_char name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", _(\"%s\"));\n"
        name shortdesc
  ) all_functions_sorted;
  pr "  printf (\"    %%s\\n\",";
  pr "          _(\"Use -h <cmd> / help <cmd> to show detailed help for a command.\"));\n";
  pr "}\n";
  pr "\n";

  (* display_command function, which implements guestfish -h cmd *)
  pr "void display_command (const char *cmd)\n";
  pr "{\n";
  List.iter (
    fun (name, style, _, flags, _, shortdesc, longdesc) ->
      let name2 = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in
      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
      let synopsis =
        match snd style with
        | [] -> name2
        | args ->
            sprintf "%s %s"
              name2 (String.concat " " (List.map name_of_argt args)) in

      let warnings =
        if List.mem ProtocolLimitWarning flags then
          ("\n\n" ^ protocol_limit_warning)
        else "" in

      (* For DangerWillRobinson commands, we should probably have
       * guestfish prompt before allowing you to use them (especially
       * in interactive mode). XXX
       *)
      let warnings =
        warnings ^
          if List.mem DangerWillRobinson flags then
            ("\n\n" ^ danger_will_robinson)
          else "" in

      let warnings =
        warnings ^
          match deprecation_notice flags with
          | None -> ""
          | Some txt -> "\n\n" ^ txt in

      let describe_alias =
        if name <> alias then
          sprintf "\n\nYou can use '%s' as an alias for this command." alias
        else "" in

      pr "  if (";
      pr "STRCASEEQ (cmd, \"%s\")" name;
      if name <> name2 then
        pr " || STRCASEEQ (cmd, \"%s\")" name2;
      if name <> alias then
        pr " || STRCASEEQ (cmd, \"%s\")" alias;
      pr ")\n";
      pr "    pod2text (\"%s\", _(\"%s\"), %S);\n"
        name2 shortdesc
        ("=head1 SYNOPSIS\n\n " ^ synopsis ^ "\n\n" ^
         "=head1 DESCRIPTION\n\n" ^
         longdesc ^ warnings ^ describe_alias);
      pr "  else\n"
  ) all_functions;
  pr "    display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  let emit_print_list_function typ =
    pr "static void print_%s_list (struct guestfs_%s_list *%ss)\n"
      typ typ typ;
    pr "{\n";
    pr "  unsigned int i;\n";
    pr "\n";
    pr "  for (i = 0; i < %ss->len; ++i) {\n" typ;
    pr "    printf (\"[%%d] = {\\n\", i);\n";
    pr "    print_%s_indent (&%ss->val[i], \"  \");\n" typ typ;
    pr "    printf (\"}\\n\");\n";
    pr "  }\n";
    pr "}\n";
    pr "\n";
  in

  (* print_* functions *)
  List.iter (
    fun (typ, cols) ->
      let needs_i =
        List.exists (function (_, (FUUID|FBuffer)) -> true | _ -> false) cols in

      pr "static void print_%s_indent (struct guestfs_%s *%s, const char *indent)\n" typ typ typ;
      pr "{\n";
      if needs_i then (
        pr "  unsigned int i;\n";
        pr "\n"
      );
      List.iter (
        function
        | name, FString ->
            pr "  printf (\"%%s%s: %%s\\n\", indent, %s->%s);\n" name typ name
        | name, FUUID ->
            pr "  printf (\"%%s%s: \", indent);\n" name;
            pr "  for (i = 0; i < 32; ++i)\n";
            pr "    printf (\"%%c\", %s->%s[i]);\n" typ name;
            pr "  printf (\"\\n\");\n"
        | name, FBuffer ->
            pr "  printf (\"%%s%s: \", indent);\n" name;
            pr "  for (i = 0; i < %s->%s_len; ++i)\n" typ name;
            pr "    if (c_isprint (%s->%s[i]))\n" typ name;
            pr "      printf (\"%%c\", %s->%s[i]);\n" typ name;
            pr "    else\n";
            pr "      printf (\"\\\\x%%02x\", %s->%s[i]);\n" typ name;
            pr "  printf (\"\\n\");\n"
        | name, (FUInt64|FBytes) ->
            pr "  printf (\"%%s%s: %%\" PRIu64 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FInt64 ->
            pr "  printf (\"%%s%s: %%\" PRIi64 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FUInt32 ->
            pr "  printf (\"%%s%s: %%\" PRIu32 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FInt32 ->
            pr "  printf (\"%%s%s: %%\" PRIi32 \"\\n\", indent, %s->%s);\n"
              name typ name
        | name, FChar ->
            pr "  printf (\"%%s%s: %%c\\n\", indent, %s->%s);\n"
              name typ name
        | name, FOptPercent ->
            pr "  if (%s->%s >= 0) printf (\"%%s%s: %%g %%%%\\n\", indent, %s->%s);\n"
              typ name name typ name;
            pr "  else printf (\"%%s%s: \\n\", indent);\n" name
      ) cols;
      pr "}\n";
      pr "\n";
  ) structs;

  (* Emit a print_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_print_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* Emit a print_TYPE function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructOnly | RStructAndList) ->
        pr "static void print_%s (struct guestfs_%s *%s)\n" typ typ typ;
        pr "{\n";
        pr "  print_%s_indent (%s, \"\");\n" typ typ;
        pr "}\n";
        pr "\n";
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* run_<action> actions *)
  List.iter (
    fun (name, style, _, flags, _, _, _) ->
      pr "static int run_%s (const char *cmd, int argc, char *argv[])\n" name;
      pr "{\n";
      (match fst style with
       | RErr
       | RInt _
       | RBool _ -> pr "  int r;\n"
       | RInt64 _ -> pr "  int64_t r;\n"
       | RConstString _ | RConstOptString _ -> pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ
       | RStructList (_, typ) -> pr "  struct guestfs_%s_list *r;\n" typ
       | RBufferOut _ ->
           pr "  char *r;\n";
           pr "  size_t size;\n";
      );
      List.iter (
        function
        | Device n
        | String n
        | OptString n
        | FileIn n
        | FileOut n -> pr "  const char *%s;\n" n
        | Pathname n
        | Dev_or_Path n -> pr "  char *%s;\n" n
        | StringList n | DeviceList n -> pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  int64_t %s;\n" n
      ) (snd style);

      (* Check and convert parameters. *)
      let argc_expected = List.length (snd style) in
      pr "  if (argc != %d) {\n" argc_expected;
      pr "    fprintf (stderr, _(\"%%s should have %%d parameter(s)\\n\"), cmd, %d);\n"
        argc_expected;
      pr "    fprintf (stderr, _(\"type 'help %%s' for help on %%s\\n\"), cmd, cmd);\n";
      pr "    return -1;\n";
      pr "  }\n";
      iteri (
        fun i ->
          function
          | Device name
          | String name ->
              pr "  %s = argv[%d];\n" name i
          | Pathname name
          | Dev_or_Path name ->
              pr "  %s = resolve_win_path (argv[%d]);\n" name i;
              pr "  if (%s == NULL) return -1;\n" name
          | OptString name ->
              pr "  %s = STRNEQ (argv[%d], \"\") ? argv[%d] : NULL;\n"
                name i i
          | FileIn name ->
              pr "  %s = STRNEQ (argv[%d], \"-\") ? argv[%d] : \"/dev/stdin\";\n"
                name i i
          | FileOut name ->
              pr "  %s = STRNEQ (argv[%d], \"-\") ? argv[%d] : \"/dev/stdout\";\n"
                name i i
          | StringList name | DeviceList name ->
              pr "  %s = parse_string_list (argv[%d]);\n" name i;
              pr "  if (%s == NULL) return -1;\n" name;
          | Bool name ->
              pr "  %s = is_true (argv[%d]) ? 1 : 0;\n" name i
          | Int name ->
              pr "  %s = atoi (argv[%d]);\n" name i
          | Int64 name ->
              pr "  %s = atoll (argv[%d]);\n" name i
      ) (snd style);

      (* Call C API function. *)
      let fn =
        try find_map (function FishAction n -> Some n | _ -> None) flags
        with Not_found -> sprintf "guestfs_%s" name in
      pr "  r = %s " fn;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Device name | String name
        | OptString name | FileIn name | FileOut name | Bool name
        | Int name | Int64 name -> ()
        | Pathname name | Dev_or_Path name ->
            pr "  free (%s);\n" name
        | StringList name | DeviceList name ->
            pr "  free_strings (%s);\n" name
      ) (snd style);

      (* Check return value for errors and display command results. *)
      (match fst style with
       | RErr -> pr "  return r;\n"
       | RInt _ ->
           pr "  if (r == -1) return -1;\n";
           pr "  printf (\"%%d\\n\", r);\n";
           pr "  return 0;\n"
       | RInt64 _ ->
           pr "  if (r == -1) return -1;\n";
           pr "  printf (\"%%\" PRIi64 \"\\n\", r);\n";
           pr "  return 0;\n"
       | RBool _ ->
           pr "  if (r == -1) return -1;\n";
           pr "  if (r) printf (\"true\\n\"); else printf (\"false\\n\");\n";
           pr "  return 0;\n"
       | RConstString _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  printf (\"%%s\\n\", r);\n";
           pr "  return 0;\n"
       | RConstOptString _ ->
           pr "  printf (\"%%s\\n\", r ? : \"(null)\");\n";
           pr "  return 0;\n"
       | RString _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  printf (\"%%s\\n\", r);\n";
           pr "  free (r);\n";
           pr "  return 0;\n"
       | RStringList _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_strings (r);\n";
           pr "  free_strings (r);\n";
           pr "  return 0;\n"
       | RStruct (_, typ) ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ;
           pr "  return 0;\n"
       | RStructList (_, typ) ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ;
           pr "  return 0;\n"
       | RHashtable _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  print_table (r);\n";
           pr "  free_strings (r);\n";
           pr "  return 0;\n"
       | RBufferOut _ ->
           pr "  if (r == NULL) return -1;\n";
           pr "  fwrite (r, size, 1, stdout);\n";
           pr "  free (r);\n";
           pr "  return 0;\n"
      );
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* run_action function *)
  pr "int run_action (const char *cmd, int argc, char *argv[])\n";
  pr "{\n";
  List.iter (
    fun (name, _, _, flags, _, _, _) ->
      let name2 = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in
      pr "  if (";
      pr "STRCASEEQ (cmd, \"%s\")" name;
      if name <> name2 then
        pr " || STRCASEEQ (cmd, \"%s\")" name2;
      if name <> alias then
        pr " || STRCASEEQ (cmd, \"%s\")" alias;
      pr ")\n";
      pr "    return run_%s (cmd, argc, argv);\n" name;
      pr "  else\n";
  ) all_functions;
  pr "    {\n";
  pr "      fprintf (stderr, _(\"%%s: unknown command\\n\"), cmd);\n";
  pr "      return -1;\n";
  pr "    }\n";
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

(* Readline completion for guestfish. *)
and generate_fish_completion () =
  generate_header CStyle GPLv2plus;

  let all_functions =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions in

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#endif

#include \"fish.h\"

#ifdef HAVE_LIBREADLINE

static const char *const commands[] = {
  BUILTIN_COMMANDS_FOR_COMPLETION,
";

  (* Get the commands, including the aliases.  They don't need to be
   * sorted - the generator() function just does a dumb linear search.
   *)
  let commands =
    List.map (
      fun (name, _, _, flags, _, _, _) ->
        let name2 = replace_char name '_' '-' in
        let alias =
          try find_map (function FishAlias n -> Some n | _ -> None) flags
          with Not_found -> name in

        if name <> alias then [name2; alias] else [name2]
    ) all_functions in
  let commands = List.flatten commands in

  List.iter (pr "  \"%s\",\n") commands;

  pr "  NULL
};

static char *
generator (const char *text, int state)
{
  static int index, len;
  const char *name;

  if (!state) {
    index = 0;
    len = strlen (text);
  }

  rl_attempted_completion_over = 1;

  while ((name = commands[index]) != NULL) {
    index++;
    if (STRCASEEQLEN (name, text, len))
      return strdup (name);
  }

  return NULL;
}

#endif /* HAVE_LIBREADLINE */

char **do_completion (const char *text, int start, int end)
{
  char **matches = NULL;

#ifdef HAVE_LIBREADLINE
  rl_completion_append_character = ' ';

  if (start == 0)
    matches = rl_completion_matches (text, generator);
  else if (complete_dest_paths)
    matches = rl_completion_matches (text, complete_dest_paths_generator);
#endif

  return matches;
}
";

(* Generate the POD documentation for guestfish. *)
and generate_fish_actions_pod () =
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) ->
        not (List.mem NotInFish flags || List.mem NotInDocs flags)
    ) all_functions_sorted in

  let rex = Str.regexp "C<guestfs_\\([^>]+\\)>" in

  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      let longdesc =
        Str.global_substitute rex (
          fun s ->
            let sub =
              try Str.matched_group 1 s
              with Not_found ->
                failwithf "error substituting C<guestfs_...> in longdesc of function %s" name in
            "C<" ^ replace_char sub '_' '-' ^ ">"
        ) longdesc in
      let name = replace_char name '_' '-' in
      let alias =
        try find_map (function FishAlias n -> Some n | _ -> None) flags
        with Not_found -> name in

      pr "=head2 %s" name;
      if name <> alias then
        pr " | %s" alias;
      pr "\n";
      pr "\n";
      pr " %s" name;
      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n -> pr " %s" n
        | OptString n -> pr " %s" n
        | StringList n | DeviceList n -> pr " '%s ...'" n
        | Bool _ -> pr " true|false"
        | Int n -> pr " %s" n
        | Int64 n -> pr " %s" n
        | FileIn n | FileOut n -> pr " (%s|-)" n
      ) (snd style);
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc;

      if List.exists (function FileIn _ | FileOut _ -> true
                      | _ -> false) (snd style) then
        pr "Use C<-> instead of a filename to read/write from stdin/stdout.\n\n";

      if List.mem ProtocolLimitWarning flags then
        pr "%s\n\n" protocol_limit_warning;

      if List.mem DangerWillRobinson flags then
        pr "%s\n\n" danger_will_robinson;

      match deprecation_notice flags with
      | None -> ()
      | Some txt -> pr "%s\n\n" txt
  ) all_functions_sorted

(* Generate a C function prototype. *)
and generate_prototype ?(extern = true) ?(static = false) ?(semicolon = true)
    ?(single_line = false) ?(newline = false) ?(in_daemon = false)
    ?(prefix = "")
    ?handle name style =
  if extern then pr "extern ";
  if static then pr "static ";
  (match fst style with
   | RErr -> pr "int "
   | RInt _ -> pr "int "
   | RInt64 _ -> pr "int64_t "
   | RBool _ -> pr "int "
   | RConstString _ | RConstOptString _ -> pr "const char *"
   | RString _ | RBufferOut _ -> pr "char *"
   | RStringList _ | RHashtable _ -> pr "char **"
   | RStruct (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s *" typ
       else pr "guestfs_int_%s *" typ
   | RStructList (_, typ) ->
       if not in_daemon then pr "struct guestfs_%s_list *" typ
       else pr "guestfs_int_%s_list *" typ
  );
  let is_RBufferOut = match fst style with RBufferOut _ -> true | _ -> false in
  pr "%s%s (" prefix name;
  if handle = None && List.length (snd style) = 0 && not is_RBufferOut then
    pr "void"
  else (
    let comma = ref false in
    (match handle with
     | None -> ()
     | Some handle -> pr "guestfs_h *%s" handle; comma := true
    );
    let next () =
      if !comma then (
        if single_line then pr ", " else pr ",\n\t\t"
      );
      comma := true
    in
    List.iter (
      function
      | Pathname n
      | Device n | Dev_or_Path n
      | String n
      | OptString n ->
          next ();
          pr "const char *%s" n
      | StringList n | DeviceList n ->
          next ();
          pr "char *const *%s" n
      | Bool n -> next (); pr "int %s" n
      | Int n -> next (); pr "int %s" n
      | Int64 n -> next (); pr "int64_t %s" n
      | FileIn n
      | FileOut n ->
          if not in_daemon then (next (); pr "const char *%s" n)
    ) (snd style);
    if is_RBufferOut then (next (); pr "size_t *size_r");
  );
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_c_call_args ?handle ?(decl = false) style =
  pr "(";
  let comma = ref false in
  let next () =
    if !comma then pr ", ";
    comma := true
  in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  List.iter (
    fun arg ->
      next ();
      pr "%s" (name_of_argt arg)
  ) (snd style);
  (* For RBufferOut calls, add implicit &size parameter. *)
  if not decl then (
    match fst style with
    | RBufferOut _ ->
        next ();
        pr "&size"
    | _ -> ()
  );
  pr ")"

(* Generate the OCaml bindings interface. *)
and generate_ocaml_mli () =
  generate_header OCamlStyle LGPLv2plus;

  pr "\
(** For API documentation you should refer to the C API
    in the guestfs(3) manual page.  The OCaml API uses almost
    exactly the same calls. *)

type t
(** A [guestfs_h] handle. *)

exception Error of string
(** This exception is raised when there is an error. *)

exception Handle_closed of string
(** This exception is raised if you use a {!Guestfs.t} handle
    after calling {!close} on it.  The string is the name of
    the function. *)

val create : unit -> t
(** Create a {!Guestfs.t} handle. *)

val close : t -> unit
(** Close the {!Guestfs.t} handle and free up all resources used
    by it immediately.

    Handles are closed by the garbage collector when they become
    unreferenced, but callers can call this in order to provide
    predictable cleanup. *)

";
  generate_ocaml_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, _, shortdesc, _) ->
      generate_ocaml_prototype name style;
      pr "(** %s *)\n" shortdesc;
      pr "\n"
  ) all_functions_sorted

(* Generate the OCaml bindings implementation. *)
and generate_ocaml_ml () =
  generate_header OCamlStyle LGPLv2plus;

  pr "\
type t

exception Error of string
exception Handle_closed of string

external create : unit -> t = \"ocaml_guestfs_create\"
external close : t -> unit = \"ocaml_guestfs_close\"

(* Give the exceptions names, so they can be raised from the C code. *)
let () =
  Callback.register_exception \"ocaml_guestfs_error\" (Error \"\");
  Callback.register_exception \"ocaml_guestfs_closed\" (Handle_closed \"\")

";

  generate_ocaml_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, _, shortdesc, _) ->
      generate_ocaml_prototype ~is_external:true name style;
  ) all_functions_sorted

(* Generate the OCaml bindings C implementation. *)
and generate_ocaml_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <caml/config.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>

#include <guestfs.h>

#include \"guestfs_c.h\"

/* Copy a hashtable of string pairs into an assoc-list.  We return
 * the list in reverse order, but hashtables aren't supposed to be
 * ordered anyway.
 */
static CAMLprim value
copy_table (char * const * argv)
{
  CAMLparam0 ();
  CAMLlocal5 (rv, pairv, kv, vv, cons);
  int i;

  rv = Val_int (0);
  for (i = 0; argv[i] != NULL; i += 2) {
    kv = caml_copy_string (argv[i]);
    vv = caml_copy_string (argv[i+1]);
    pairv = caml_alloc (2, 0);
    Store_field (pairv, 0, kv);
    Store_field (pairv, 1, vv);
    cons = caml_alloc (2, 0);
    Store_field (cons, 1, rv);
    rv = cons;
    Store_field (cons, 0, pairv);
  }

  CAMLreturn (rv);
}

";

  (* Struct copy functions. *)

  let emit_ocaml_copy_list_function typ =
    pr "static CAMLprim value\n";
    pr "copy_%s_list (const struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  CAMLparam0 ();\n";
    pr "  CAMLlocal2 (rv, v);\n";
    pr "  unsigned int i;\n";
    pr "\n";
    pr "  if (%ss->len == 0)\n" typ;
    pr "    CAMLreturn (Atom (0));\n";
    pr "  else {\n";
    pr "    rv = caml_alloc (%ss->len, 0);\n" typ;
    pr "    for (i = 0; i < %ss->len; ++i) {\n" typ;
    pr "      v = copy_%s (&%ss->val[i]);\n" typ typ;
    pr "      caml_modify (&Field (rv, i), v);\n";
    pr "    }\n";
    pr "    CAMLreturn (rv);\n";
    pr "  }\n";
    pr "}\n";
    pr "\n";
  in

  List.iter (
    fun (typ, cols) ->
      let has_optpercent_col =
        List.exists (function (_, FOptPercent) -> true | _ -> false) cols in

      pr "static CAMLprim value\n";
      pr "copy_%s (const struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  CAMLparam0 ();\n";
      if has_optpercent_col then
        pr "  CAMLlocal3 (rv, v, v2);\n"
      else
        pr "  CAMLlocal2 (rv, v);\n";
      pr "\n";
      pr "  rv = caml_alloc (%d, 0);\n" (List.length cols);
      iteri (
        fun i col ->
          (match col with
           | name, FString ->
               pr "  v = caml_copy_string (%s->%s);\n" typ name
           | name, FBuffer ->
               pr "  v = caml_alloc_string (%s->%s_len);\n" typ name;
               pr "  memcpy (String_val (v), %s->%s, %s->%s_len);\n"
                 typ name typ name
           | name, FUUID ->
               pr "  v = caml_alloc_string (32);\n";
               pr "  memcpy (String_val (v), %s->%s, 32);\n" typ name
           | name, (FBytes|FInt64|FUInt64) ->
               pr "  v = caml_copy_int64 (%s->%s);\n" typ name
           | name, (FInt32|FUInt32) ->
               pr "  v = caml_copy_int32 (%s->%s);\n" typ name
           | name, FOptPercent ->
               pr "  if (%s->%s >= 0) { /* Some %s */\n" typ name name;
               pr "    v2 = caml_copy_double (%s->%s);\n" typ name;
               pr "    v = caml_alloc (1, 0);\n";
               pr "    Store_field (v, 0, v2);\n";
               pr "  } else /* None */\n";
               pr "    v = Val_int (0);\n";
           | name, FChar ->
               pr "  v = Val_int (%s->%s);\n" typ name
          );
          pr "  Store_field (rv, %d, v);\n" i
      ) cols;
      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";
  ) structs;

  (* Emit a copy_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_ocaml_copy_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* The wrappers. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "/* Automatically generated wrapper for function\n";
      pr " * ";
      generate_ocaml_prototype name style;
      pr " */\n";
      pr "\n";

      let params =
        "gv" :: List.map (fun arg -> name_of_argt arg ^ "v") (snd style) in

      let needs_extra_vs =
        match fst style with RConstOptString _ -> true | _ -> false in

      pr "/* Emit prototype to appease gcc's -Wmissing-prototypes. */\n";
      pr "CAMLprim value ocaml_guestfs_%s (value %s" name (List.hd params);
      List.iter (pr ", value %s") (List.tl params); pr ");\n";
      pr "\n";

      pr "CAMLprim value\n";
      pr "ocaml_guestfs_%s (value %s" name (List.hd params);
      List.iter (pr ", value %s") (List.tl params);
      pr ")\n";
      pr "{\n";

      (match params with
       | [p1; p2; p3; p4; p5] ->
           pr "  CAMLparam5 (%s);\n" (String.concat ", " params)
       | p1 :: p2 :: p3 :: p4 :: p5 :: rest ->
           pr "  CAMLparam5 (%s);\n" (String.concat ", " [p1; p2; p3; p4; p5]);
           pr "  CAMLxparam%d (%s);\n"
             (List.length rest) (String.concat ", " rest)
       | ps ->
           pr "  CAMLparam%d (%s);\n" (List.length ps) (String.concat ", " ps)
      );
      if not needs_extra_vs then
        pr "  CAMLlocal1 (rv);\n"
      else
        pr "  CAMLlocal3 (rv, v, v2);\n";
      pr "\n";

      pr "  guestfs_h *g = Guestfs_val (gv);\n";
      pr "  if (g == NULL)\n";
      pr "    ocaml_guestfs_raise_closed (\"%s\");\n" name;
      pr "\n";

      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | FileIn n
        | FileOut n ->
            pr "  const char *%s = String_val (%sv);\n" n n
        | OptString n ->
            pr "  const char *%s =\n" n;
            pr "    %sv != Val_int (0) ? String_val (Field (%sv, 0)) : NULL;\n"
              n n
        | StringList n | DeviceList n ->
            pr "  char **%s = ocaml_guestfs_strings_val (g, %sv);\n" n n
        | Bool n ->
            pr "  int %s = Bool_val (%sv);\n" n n
        | Int n ->
            pr "  int %s = Int_val (%sv);\n" n n
        | Int64 n ->
            pr "  int64_t %s = Int64_val (%sv);\n" n n
      ) (snd style);
      let error_code =
        match fst style with
        | RErr -> pr "  int r;\n"; "-1"
        | RInt _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RBool _ -> pr "  int r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "  const char *r;\n"; "NULL"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ ->
            pr "  int i;\n";
            pr "  char **r;\n";
            "NULL"
        | RStruct (_, typ) ->
            pr "  struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL"
        | RHashtable _ ->
            pr "  int i;\n";
            pr "  char **r;\n";
            "NULL"
        | RBufferOut _ ->
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL" in
      pr "\n";

      pr "  caml_enter_blocking_section ();\n";
      pr "  r = guestfs_%s " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";
      pr "  caml_leave_blocking_section ();\n";

      List.iter (
        function
        | StringList n | DeviceList n ->
            pr "  ocaml_guestfs_free_strings (%s);\n" n;
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | OptString _
        | Bool _ | Int _ | Int64 _
        | FileIn _ | FileOut _ -> ()
      ) (snd style);

      pr "  if (r == %s)\n" error_code;
      pr "    ocaml_guestfs_raise_error (g, \"%s\");\n" name;
      pr "\n";

      (match fst style with
       | RErr -> pr "  rv = Val_unit;\n"
       | RInt _ -> pr "  rv = Val_int (r);\n"
       | RInt64 _ ->
           pr "  rv = caml_copy_int64 (r);\n"
       | RBool _ -> pr "  rv = Val_bool (r);\n"
       | RConstString _ ->
           pr "  rv = caml_copy_string (r);\n"
       | RConstOptString _ ->
           pr "  if (r) { /* Some string */\n";
           pr "    v = caml_alloc (1, 0);\n";
           pr "    v2 = caml_copy_string (r);\n";
           pr "    Store_field (v, 0, v2);\n";
           pr "  } else /* None */\n";
           pr "    v = Val_int (0);\n";
       | RString _ ->
           pr "  rv = caml_copy_string (r);\n";
           pr "  free (r);\n"
       | RStringList _ ->
           pr "  rv = caml_copy_string_array ((const char **) r);\n";
           pr "  for (i = 0; r[i] != NULL; ++i) free (r[i]);\n";
           pr "  free (r);\n"
       | RStruct (_, typ) ->
           pr "  rv = copy_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ;
       | RStructList (_, typ) ->
           pr "  rv = copy_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ;
       | RHashtable _ ->
           pr "  rv = copy_table (r);\n";
           pr "  for (i = 0; r[i] != NULL; ++i) free (r[i]);\n";
           pr "  free (r);\n";
       | RBufferOut _ ->
           pr "  rv = caml_alloc_string (size);\n";
           pr "  memcpy (String_val (rv), r, size);\n";
      );

      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";

      if List.length params > 5 then (
        pr "/* Emit prototype to appease gcc's -Wmissing-prototypes. */\n";
        pr "CAMLprim value ";
        pr "ocaml_guestfs_%s_byte (value *argv, int argn);\n" name;
        pr "CAMLprim value\n";
        pr "ocaml_guestfs_%s_byte (value *argv, int argn)\n" name;
        pr "{\n";
        pr "  return ocaml_guestfs_%s (argv[0]" name;
        iteri (fun i _ -> pr ", argv[%d]" i) (List.tl params);
        pr ");\n";
        pr "}\n";
        pr "\n"
      )
  ) all_functions_sorted

and generate_ocaml_structure_decls () =
  List.iter (
    fun (typ, cols) ->
      pr "type %s = {\n" typ;
      List.iter (
        function
        | name, FString -> pr "  %s : string;\n" name
        | name, FBuffer -> pr "  %s : string;\n" name
        | name, FUUID -> pr "  %s : string;\n" name
        | name, (FBytes|FInt64|FUInt64) -> pr "  %s : int64;\n" name
        | name, (FInt32|FUInt32) -> pr "  %s : int32;\n" name
        | name, FChar -> pr "  %s : char;\n" name
        | name, FOptPercent -> pr "  %s : float option;\n" name
      ) cols;
      pr "}\n";
      pr "\n"
  ) structs

and generate_ocaml_prototype ?(is_external = false) name style =
  if is_external then pr "external " else pr "val ";
  pr "%s : t -> " name;
  List.iter (
    function
    | Pathname _ | Device _ | Dev_or_Path _ | String _ | FileIn _ | FileOut _ -> pr "string -> "
    | OptString _ -> pr "string option -> "
    | StringList _ | DeviceList _ -> pr "string array -> "
    | Bool _ -> pr "bool -> "
    | Int _ -> pr "int -> "
    | Int64 _ -> pr "int64 -> "
  ) (snd style);
  (match fst style with
   | RErr -> pr "unit" (* all errors are turned into exceptions *)
   | RInt _ -> pr "int"
   | RInt64 _ -> pr "int64"
   | RBool _ -> pr "bool"
   | RConstString _ -> pr "string"
   | RConstOptString _ -> pr "string option"
   | RString _ | RBufferOut _ -> pr "string"
   | RStringList _ -> pr "string array"
   | RStruct (_, typ) -> pr "%s" typ
   | RStructList (_, typ) -> pr "%s array" typ
   | RHashtable _ -> pr "(string * string) list"
  );
  if is_external then (
    pr " = ";
    if List.length (snd style) + 1 > 5 then
      pr "\"ocaml_guestfs_%s_byte\" " name;
    pr "\"ocaml_guestfs_%s\"" name
  );
  pr "\n"

(* Generate Perl xs code, a sort of crazy variation of C with macros. *)
and generate_perl_xs () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include \"EXTERN.h\"
#include \"perl.h\"
#include \"XSUB.h\"

#include <guestfs.h>

#ifndef PRId64
#define PRId64 \"lld\"
#endif

static SV *
my_newSVll(long long val) {
#ifdef USE_64_BIT_ALL
  return newSViv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRId64, val);
  return newSVpv(buf, len);
#endif
}

#ifndef PRIu64
#define PRIu64 \"llu\"
#endif

static SV *
my_newSVull(unsigned long long val) {
#ifdef USE_64_BIT_ALL
  return newSVuv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRIu64, val);
  return newSVpv(buf, len);
#endif
}

/* http://www.perlmonks.org/?node_id=680842 */
static char **
XS_unpack_charPtrPtr (SV *arg) {
  char **ret;
  AV *av;
  I32 i;

  if (!arg || !SvOK (arg) || !SvROK (arg) || SvTYPE (SvRV (arg)) != SVt_PVAV)
    croak (\"array reference expected\");

  av = (AV *)SvRV (arg);
  ret = malloc ((av_len (av) + 1 + 1) * sizeof (char *));
  if (!ret)
    croak (\"malloc failed\");

  for (i = 0; i <= av_len (av); i++) {
    SV **elem = av_fetch (av, i, 0);

    if (!elem || !*elem)
      croak (\"missing element in list\");

    ret[i] = SvPV_nolen (*elem);
  }

  ret[i] = NULL;

  return ret;
}

MODULE = Sys::Guestfs  PACKAGE = Sys::Guestfs

PROTOTYPES: ENABLE

guestfs_h *
_create ()
   CODE:
      RETVAL = guestfs_create ();
      if (!RETVAL)
        croak (\"could not create guestfs handle\");
      guestfs_set_error_handler (RETVAL, NULL, NULL);
 OUTPUT:
      RETVAL

void
DESTROY (g)
      guestfs_h *g;
 PPCODE:
      guestfs_close (g);

";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      (match fst style with
       | RErr -> pr "void\n"
       | RInt _ -> pr "SV *\n"
       | RInt64 _ -> pr "SV *\n"
       | RBool _ -> pr "SV *\n"
       | RConstString _ -> pr "SV *\n"
       | RConstOptString _ -> pr "SV *\n"
       | RString _ -> pr "SV *\n"
       | RBufferOut _ -> pr "SV *\n"
       | RStringList _
       | RStruct _ | RStructList _
       | RHashtable _ ->
           pr "void\n" (* all lists returned implictly on the stack *)
      );
      (* Call and arguments. *)
      pr "%s " name;
      generate_c_call_args ~handle:"g" ~decl:true style;
      pr "\n";
      pr "      guestfs_h *g;\n";
      iteri (
        fun i ->
          function
          | Pathname n | Device n | Dev_or_Path n | String n | FileIn n | FileOut n ->
              pr "      char *%s;\n" n
          | OptString n ->
              (* http://www.perlmonks.org/?node_id=554277
               * Note that the implicit handle argument means we have
               * to add 1 to the ST(x) operator.
               *)
              pr "      char *%s = SvOK(ST(%d)) ? SvPV_nolen(ST(%d)) : NULL;\n" n (i+1) (i+1)
          | StringList n | DeviceList n -> pr "      char **%s;\n" n
          | Bool n -> pr "      int %s;\n" n
          | Int n -> pr "      int %s;\n" n
          | Int64 n -> pr "      int64_t %s;\n" n
      ) (snd style);

      let do_cleanups () =
        List.iter (
          function
          | Pathname _ | Device _ | Dev_or_Path _ | String _ | OptString _
          | Bool _ | Int _ | Int64 _
          | FileIn _ | FileOut _ -> ()
          | StringList n | DeviceList n -> pr "      free (%s);\n" n
        ) (snd style)
      in

      (* Code. *)
      (match fst style with
       | RErr ->
           pr "PREINIT:\n";
           pr "      int r;\n";
           pr " PPCODE:\n";
           pr "      r = guestfs_%s " name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (r == -1)\n";
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
       | RInt n
       | RBool n ->
           pr "PREINIT:\n";
           pr "      int %s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == -1)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      RETVAL = newSViv (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RInt64 n ->
           pr "PREINIT:\n";
           pr "      int64_t %s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == -1)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      RETVAL = my_newSVll (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstString n ->
           pr "PREINIT:\n";
           pr "      const char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      RETVAL = newSVpv (%s, 0);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RConstOptString n ->
           pr "PREINIT:\n";
           pr "      const char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        RETVAL = &PL_sv_undef;\n";
           pr "      else\n";
           pr "        RETVAL = newSVpv (%s, 0);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RString n ->
           pr "PREINIT:\n";
           pr "      char *%s;\n" n;
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      RETVAL = newSVpv (%s, 0);\n" n;
           pr "      free (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
       | RStringList n | RHashtable n ->
           pr "PREINIT:\n";
           pr "      char **%s;\n" n;
           pr "      int i, n;\n";
           pr " PPCODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      for (n = 0; %s[n] != NULL; ++n) /**/;\n" n;
           pr "      EXTEND (SP, n);\n";
           pr "      for (i = 0; i < n; ++i) {\n";
           pr "        PUSHs (sv_2mortal (newSVpv (%s[i], 0)));\n" n;
           pr "        free (%s[i]);\n" n;
           pr "      }\n";
           pr "      free (%s);\n" n;
       | RStruct (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_code typ cols name style n do_cleanups
       | RStructList (n, typ) ->
           let cols = cols_of_struct typ in
           generate_perl_struct_list_code typ cols name style n do_cleanups
       | RBufferOut n ->
           pr "PREINIT:\n";
           pr "      char *%s;\n" n;
           pr "      size_t size;\n";
           pr "   CODE:\n";
           pr "      %s = guestfs_%s " n name;
           generate_c_call_args ~handle:"g" style;
           pr ";\n";
           do_cleanups ();
           pr "      if (%s == NULL)\n" n;
           pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
           pr "      RETVAL = newSVpv (%s, size);\n" n;
           pr "      free (%s);\n" n;
           pr " OUTPUT:\n";
           pr "      RETVAL\n"
      );

      pr "\n"
  ) all_functions

and generate_perl_struct_list_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_%s_list *%s;\n" typ n;
  pr "      int i;\n";
  pr "      HV *hv;\n";
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_c_call_args ~handle:"g" style;
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
  pr "      EXTEND (SP, %s->len);\n" n;
  pr "      for (i = 0; i < %s->len; ++i) {\n" n;
  pr "        hv = newHV ();\n";
  List.iter (
    function
    | name, FString ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 0), 0);\n"
          name (String.length name) n name
    | name, FUUID ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 32), 0);\n"
          name (String.length name) n name
    | name, FBuffer ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, %s->val[i].%s_len), 0);\n"
          name (String.length name) n name n name
    | name, (FBytes|FUInt64) ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVull (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, FInt64 ->
        pr "        (void) hv_store (hv, \"%s\", %d, my_newSVll (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, (FInt32|FUInt32) ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
          name (String.length name) n name
    | name, FChar ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (&%s->val[i].%s, 1), 0);\n"
          name (String.length name) n name
    | name, FOptPercent ->
        pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
          name (String.length name) n name
  ) cols;
  pr "        PUSHs (sv_2mortal (newRV ((SV *) hv)));\n";
  pr "      }\n";
  pr "      guestfs_free_%s_list (%s);\n" typ n

and generate_perl_struct_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_%s *%s;\n" typ n;
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_c_call_args ~handle:"g" style;
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
  pr "      EXTEND (SP, 2 * %d);\n" (List.length cols);
  List.iter (
    fun ((name, _) as col) ->
      pr "      PUSHs (sv_2mortal (newSVpv (\"%s\", 0)));\n" name;

      match col with
      | name, FString ->
          pr "      PUSHs (sv_2mortal (newSVpv (%s->%s, 0)));\n"
            n name
      | name, FBuffer ->
          pr "      PUSHs (sv_2mortal (newSVpv (%s->%s, %s->%s_len)));\n"
            n name n name
      | name, FUUID ->
          pr "      PUSHs (sv_2mortal (newSVpv (%s->%s, 32)));\n"
            n name
      | name, (FBytes|FUInt64) ->
          pr "      PUSHs (sv_2mortal (my_newSVull (%s->%s)));\n"
            n name
      | name, FInt64 ->
          pr "      PUSHs (sv_2mortal (my_newSVll (%s->%s)));\n"
            n name
      | name, (FInt32|FUInt32) ->
          pr "      PUSHs (sv_2mortal (newSVnv (%s->%s)));\n"
            n name
      | name, FChar ->
          pr "      PUSHs (sv_2mortal (newSVpv (&%s->%s, 1)));\n"
            n name
      | name, FOptPercent ->
          pr "      PUSHs (sv_2mortal (newSVnv (%s->%s)));\n"
            n name
  ) cols;
  pr "      free (%s);\n" n

(* Generate Sys/Guestfs.pm. *)
and generate_perl_pm () =
  generate_header HashStyle LGPLv2plus;

  pr "\
=pod

=head1 NAME

Sys::Guestfs - Perl bindings for libguestfs

=head1 SYNOPSIS

 use Sys::Guestfs;

 my $h = Sys::Guestfs->new ();
 $h->add_drive ('guest.img');
 $h->launch ();
 $h->mount ('/dev/sda1', '/');
 $h->touch ('/hello');
 $h->sync ();

=head1 DESCRIPTION

The C<Sys::Guestfs> module provides a Perl XS binding to the
libguestfs API for examining and modifying virtual machine
disk images.

Amongst the things this is good for: making batch configuration
changes to guests, getting disk used/free statistics (see also:
virt-df), migrating between virtualization systems (see also:
virt-p2v), performing partial backups, performing partial guest
clones, cloning guests and changing registry/UUID/hostname info, and
much else besides.

Libguestfs uses Linux kernel and qemu code, and can access any type of
guest filesystem that Linux and qemu can, including but not limited
to: ext2/3/4, btrfs, FAT and NTFS, LVM, many different disk partition
schemes, qcow, qcow2, vmdk.

Libguestfs provides ways to enumerate guest storage (eg. partitions,
LVs, what filesystem is in each LV, etc.).  It can also run commands
in the context of the guest.  Also you can access filesystems over FTP.

See also L<Sys::Guestfs::Lib(3)> for a set of useful library
functions for using libguestfs from Perl, including integration
with libvirt.

=head1 ERRORS

All errors turn into calls to C<croak> (see L<Carp(3)>).

=head1 METHODS

=over 4

=cut

package Sys::Guestfs;

use strict;
use warnings;

require XSLoader;
XSLoader::load ('Sys::Guestfs');

=item $h = Sys::Guestfs->new ();

Create a new guestfs handle.

=cut

sub new {
  my $proto = shift;
  my $class = ref ($proto) || $proto;

  my $self = Sys::Guestfs::_create ();
  bless $self, $class;
  return $self;
}

";

  (* Actions.  We only need to print documentation for these as
   * they are pulled in from the XS code automatically.
   *)
  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      if not (List.mem NotInDocs flags) then (
        let longdesc = replace_str longdesc "C<guestfs_" "C<$h-E<gt>" in
        pr "=item ";
        generate_perl_prototype name style;
        pr "\n\n";
        pr "%s\n\n" longdesc;
        if List.mem ProtocolLimitWarning flags then
          pr "%s\n\n" protocol_limit_warning;
        if List.mem DangerWillRobinson flags then
          pr "%s\n\n" danger_will_robinson;
        match deprecation_notice flags with
        | None -> ()
        | Some txt -> pr "%s\n\n" txt
      )
  ) all_functions_sorted;

  (* End of file. *)
  pr "\
=cut

1;

=back

=head1 COPYRIGHT

Copyright (C) %s Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<http://libguestfs.org>,
L<Sys::Guestfs::Lib(3)>.

=cut
" copyright_years

and generate_perl_prototype name style =
  (match fst style with
   | RErr -> ()
   | RBool n
   | RInt n
   | RInt64 n
   | RConstString n
   | RConstOptString n
   | RString n
   | RBufferOut n -> pr "$%s = " n
   | RStruct (n,_)
   | RHashtable n -> pr "%%%s = " n
   | RStringList n
   | RStructList (n,_) -> pr "@%s = " n
  );
  pr "$h->%s (" name;
  let comma = ref false in
  List.iter (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | Pathname n | Device n | Dev_or_Path n | String n
      | OptString n | Bool n | Int n | Int64 n | FileIn n | FileOut n ->
          pr "$%s" n
      | StringList n | DeviceList n ->
          pr "\\@%s" n
  ) (snd style);
  pr ");"

(* Generate Python C module. *)
and generate_python_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <Python.h>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include \"guestfs.h\"

typedef struct {
  PyObject_HEAD
  guestfs_h *g;
} Pyguestfs_Object;

static guestfs_h *
get_handle (PyObject *obj)
{
  assert (obj);
  assert (obj != Py_None);
  return ((Pyguestfs_Object *) obj)->g;
}

static PyObject *
put_handle (guestfs_h *g)
{
  assert (g);
  return
    PyCObject_FromVoidPtrAndDesc ((void *) g, (char *) \"guestfs_h\", NULL);
}

/* This list should be freed (but not the strings) after use. */
static char **
get_string_list (PyObject *obj)
{
  int i, len;
  char **r;

  assert (obj);

  if (!PyList_Check (obj)) {
    PyErr_SetString (PyExc_RuntimeError, \"expecting a list parameter\");
    return NULL;
  }

  len = PyList_Size (obj);
  r = malloc (sizeof (char *) * (len+1));
  if (r == NULL) {
    PyErr_SetString (PyExc_RuntimeError, \"get_string_list: out of memory\");
    return NULL;
  }

  for (i = 0; i < len; ++i)
    r[i] = PyString_AsString (PyList_GetItem (obj, i));
  r[len] = NULL;

  return r;
}

static PyObject *
put_string_list (char * const * const argv)
{
  PyObject *list;
  int argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc);
  for (i = 0; i < argc; ++i)
    PyList_SetItem (list, i, PyString_FromString (argv[i]));

  return list;
}

static PyObject *
put_table (char * const * const argv)
{
  PyObject *list, *item;
  int argc, i;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  list = PyList_New (argc >> 1);
  for (i = 0; i < argc; i += 2) {
    item = PyTuple_New (2);
    PyTuple_SetItem (item, 0, PyString_FromString (argv[i]));
    PyTuple_SetItem (item, 1, PyString_FromString (argv[i+1]));
    PyList_SetItem (list, i >> 1, item);
  }

  return list;
}

static void
free_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

static PyObject *
py_guestfs_create (PyObject *self, PyObject *args)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL) {
    PyErr_SetString (PyExc_RuntimeError,
                     \"guestfs.create: failed to allocate handle\");
    return NULL;
  }
  guestfs_set_error_handler (g, NULL, NULL);
  return put_handle (g);
}

static PyObject *
py_guestfs_close (PyObject *self, PyObject *args)
{
  PyObject *py_g;
  guestfs_h *g;

  if (!PyArg_ParseTuple (args, (char *) \"O:guestfs_close\", &py_g))
    return NULL;
  g = get_handle (py_g);

  guestfs_close (g);

  Py_INCREF (Py_None);
  return Py_None;
}

";

  let emit_put_list_function typ =
    pr "static PyObject *\n";
    pr "put_%s_list (struct guestfs_%s_list *%ss)\n" typ typ typ;
    pr "{\n";
    pr "  PyObject *list;\n";
    pr "  int i;\n";
    pr "\n";
    pr "  list = PyList_New (%ss->len);\n" typ;
    pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
    pr "    PyList_SetItem (list, i, put_%s (&%ss->val[i]));\n" typ typ;
    pr "  return list;\n";
    pr "};\n";
    pr "\n"
  in

  (* Structures, turned into Python dictionaries. *)
  List.iter (
    fun (typ, cols) ->
      pr "static PyObject *\n";
      pr "put_%s (struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  PyObject *dict;\n";
      pr "\n";
      pr "  dict = PyDict_New ();\n";
      List.iter (
        function
        | name, FString ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromString (%s->%s));\n"
              typ name
        | name, FBuffer ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (%s->%s, %s->%s_len));\n"
              typ name typ name
        | name, FUUID ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (%s->%s, 32));\n"
              typ name
        | name, (FBytes|FUInt64) ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromUnsignedLongLong (%s->%s));\n"
              typ name
        | name, FInt64 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromLongLong (%s->%s));\n"
              typ name
        | name, FUInt32 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromUnsignedLong (%s->%s));\n"
              typ name
        | name, FInt32 ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyLong_FromLong (%s->%s));\n"
              typ name
        | name, FOptPercent ->
            pr "  if (%s->%s >= 0)\n" typ name;
            pr "    PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                          PyFloat_FromDouble ((double) %s->%s));\n"
              typ name;
            pr "  else {\n";
            pr "    Py_INCREF (Py_None);\n";
            pr "    PyDict_SetItemString (dict, \"%s\", Py_None);\n" name;
            pr "  }\n"
        | name, FChar ->
            pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
            pr "                        PyString_FromStringAndSize (&dirent->%s, 1));\n" name
      ) cols;
      pr "  return dict;\n";
      pr "};\n";
      pr "\n";

  ) structs;

  (* Emit a put_TYPE_list function definition only if that function is used. *)
  List.iter (
    function
    | typ, (RStructListOnly | RStructAndList) ->
        (* generate the function for typ *)
        emit_put_list_function typ
    | typ, _ -> () (* empty *)
  ) (rstructs_used_by all_functions);

  (* Python wrapper functions. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "static PyObject *\n";
      pr "py_guestfs_%s (PyObject *self, PyObject *args)\n" name;
      pr "{\n";

      pr "  PyObject *py_g;\n";
      pr "  guestfs_h *g;\n";
      pr "  PyObject *py_r;\n";

      let error_code =
        match fst style with
        | RErr | RInt _ | RBool _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "  const char *r;\n"; "NULL"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
        | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL" in

      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | FileIn n | FileOut n ->
            pr "  const char *%s;\n" n
        | OptString n -> pr "  const char *%s;\n" n
        | StringList n | DeviceList n ->
            pr "  PyObject *py_%s;\n" n;
            pr "  char **%s;\n" n
        | Bool n -> pr "  int %s;\n" n
        | Int n -> pr "  int %s;\n" n
        | Int64 n -> pr "  long long %s;\n" n
      ) (snd style);

      pr "\n";

      (* Convert the parameters. *)
      pr "  if (!PyArg_ParseTuple (args, (char *) \"O";
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _ | FileIn _ | FileOut _ -> pr "s"
        | OptString _ -> pr "z"
        | StringList _ | DeviceList _ -> pr "O"
        | Bool _ -> pr "i" (* XXX Python has booleans? *)
        | Int _ -> pr "i"
        | Int64 _ -> pr "L" (* XXX Whoever thought it was a good idea to
                             * emulate C's int/long/long long in Python?
                             *)
      ) (snd style);
      pr ":guestfs_%s\",\n" name;
      pr "                         &py_g";
      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | FileIn n | FileOut n -> pr ", &%s" n
        | OptString n -> pr ", &%s" n
        | StringList n | DeviceList n -> pr ", &py_%s" n
        | Bool n -> pr ", &%s" n
        | Int n -> pr ", &%s" n
        | Int64 n -> pr ", &%s" n
      ) (snd style);

      pr "))\n";
      pr "    return NULL;\n";

      pr "  g = get_handle (py_g);\n";
      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _ -> ()
        | StringList n | DeviceList n ->
            pr "  %s = get_string_list (py_%s);\n" n n;
            pr "  if (!%s) return NULL;\n" n
      ) (snd style);

      pr "\n";

      pr "  r = guestfs_%s " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _ -> ()
        | StringList n | DeviceList n ->
            pr "  free (%s);\n" n
      ) (snd style);

      pr "  if (r == %s) {\n" error_code;
      pr "    PyErr_SetString (PyExc_RuntimeError, guestfs_last_error (g));\n";
      pr "    return NULL;\n";
      pr "  }\n";
      pr "\n";

      (match fst style with
       | RErr ->
           pr "  Py_INCREF (Py_None);\n";
           pr "  py_r = Py_None;\n"
       | RInt _
       | RBool _ -> pr "  py_r = PyInt_FromLong ((long) r);\n"
       | RInt64 _ -> pr "  py_r = PyLong_FromLongLong (r);\n"
       | RConstString _ -> pr "  py_r = PyString_FromString (r);\n"
       | RConstOptString _ ->
           pr "  if (r)\n";
           pr "    py_r = PyString_FromString (r);\n";
           pr "  else {\n";
           pr "    Py_INCREF (Py_None);\n";
           pr "    py_r = Py_None;\n";
           pr "  }\n"
       | RString _ ->
           pr "  py_r = PyString_FromString (r);\n";
           pr "  free (r);\n"
       | RStringList _ ->
           pr "  py_r = put_string_list (r);\n";
           pr "  free_strings (r);\n"
       | RStruct (_, typ) ->
           pr "  py_r = put_%s (r);\n" typ;
           pr "  guestfs_free_%s (r);\n" typ
       | RStructList (_, typ) ->
           pr "  py_r = put_%s_list (r);\n" typ;
           pr "  guestfs_free_%s_list (r);\n" typ
       | RHashtable n ->
           pr "  py_r = put_table (r);\n";
           pr "  free_strings (r);\n"
       | RBufferOut _ ->
           pr "  py_r = PyString_FromStringAndSize (r, size);\n";
           pr "  free (r);\n"
      );

      pr "  return py_r;\n";
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* Table of functions. *)
  pr "static PyMethodDef methods[] = {\n";
  pr "  { (char *) \"create\", py_guestfs_create, METH_VARARGS, NULL },\n";
  pr "  { (char *) \"close\", py_guestfs_close, METH_VARARGS, NULL },\n";
  List.iter (
    fun (name, _, _, _, _, _, _) ->
      pr "  { (char *) \"%s\", py_guestfs_%s, METH_VARARGS, NULL },\n"
        name name
  ) all_functions;
  pr "  { NULL, NULL, 0, NULL }\n";
  pr "};\n";
  pr "\n";

  (* Init function. *)
  pr "\
void
initlibguestfsmod (void)
{
  static int initialized = 0;

  if (initialized) return;
  Py_InitModule ((char *) \"libguestfsmod\", methods);
  initialized = 1;
}
"

(* Generate Python module. *)
and generate_python_py () =
  generate_header HashStyle LGPLv2plus;

  pr "\
u\"\"\"Python bindings for libguestfs

import guestfs
g = guestfs.GuestFS ()
g.add_drive (\"guest.img\")
g.launch ()
parts = g.list_partitions ()

The guestfs module provides a Python binding to the libguestfs API
for examining and modifying virtual machine disk images.

Amongst the things this is good for: making batch configuration
changes to guests, getting disk used/free statistics (see also:
virt-df), migrating between virtualization systems (see also:
virt-p2v), performing partial backups, performing partial guest
clones, cloning guests and changing registry/UUID/hostname info, and
much else besides.

Libguestfs uses Linux kernel and qemu code, and can access any type of
guest filesystem that Linux and qemu can, including but not limited
to: ext2/3/4, btrfs, FAT and NTFS, LVM, many different disk partition
schemes, qcow, qcow2, vmdk.

Libguestfs provides ways to enumerate guest storage (eg. partitions,
LVs, what filesystem is in each LV, etc.).  It can also run commands
in the context of the guest.  Also you can access filesystems over FTP.

Errors which happen while using the API are turned into Python
RuntimeError exceptions.

To create a guestfs handle you usually have to perform the following
sequence of calls:

# Create the handle, call add_drive at least once, and possibly
# several times if the guest has multiple block devices:
g = guestfs.GuestFS ()
g.add_drive (\"guest.img\")

# Launch the qemu subprocess and wait for it to become ready:
g.launch ()

# Now you can issue commands, for example:
logvols = g.lvs ()

\"\"\"

import libguestfsmod

class GuestFS:
    \"\"\"Instances of this class are libguestfs API handles.\"\"\"

    def __init__ (self):
        \"\"\"Create a new libguestfs handle.\"\"\"
        self._o = libguestfsmod.create ()

    def __del__ (self):
        libguestfsmod.close (self._o)

";

  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      pr "    def %s " name;
      generate_py_call_args ~handle:"self" (snd style);
      pr ":\n";

      if not (List.mem NotInDocs flags) then (
        let doc = replace_str longdesc "C<guestfs_" "C<g." in
        let doc =
          match fst style with
          | RErr | RInt _ | RInt64 _ | RBool _
          | RConstOptString _ | RConstString _
          | RString _ | RBufferOut _ -> doc
          | RStringList _ ->
              doc ^ "\n\nThis function returns a list of strings."
          | RStruct (_, typ) ->
              doc ^ sprintf "\n\nThis function returns a dictionary, with keys matching the various fields in the guestfs_%s structure." typ
          | RStructList (_, typ) ->
              doc ^ sprintf "\n\nThis function returns a list of %ss.  Each %s is represented as a dictionary." typ typ
          | RHashtable _ ->
              doc ^ "\n\nThis function returns a dictionary." in
        let doc =
          if List.mem ProtocolLimitWarning flags then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          if List.mem DangerWillRobinson flags then
            doc ^ "\n\n" ^ danger_will_robinson
          else doc in
        let doc =
          match deprecation_notice flags with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 name doc in
        let doc = List.map (fun line -> replace_str line "\\" "\\\\") doc in
        let doc = String.concat "\n        " doc in
        pr "        u\"\"\"%s\"\"\"\n" doc;
      );
      pr "        return libguestfsmod.%s " name;
      generate_py_call_args ~handle:"self._o" (snd style);
      pr "\n";
      pr "\n";
  ) all_functions

(* Generate Python call arguments, eg "(handle, foo, bar)" *)
and generate_py_call_args ~handle args =
  pr "(%s" handle;
  List.iter (fun arg -> pr ", %s" (name_of_argt arg)) args;
  pr ")"

(* Useful if you need the longdesc POD text as plain text.  Returns a
 * list of lines.
 *
 * Because this is very slow (the slowest part of autogeneration),
 * we memoize the results.
 *)
and pod2text ~width name longdesc =
  let key = width, name, longdesc in
  try Hashtbl.find pod2text_memo key
  with Not_found ->
    let filename, chan = Filename.open_temp_file "gen" ".tmp" in
    fprintf chan "=head1 %s\n\n%s\n" name longdesc;
    close_out chan;
    let cmd = sprintf "pod2text -w %d %s" width (Filename.quote filename) in
    let chan = open_process_in cmd in
    let lines = ref [] in
    let rec loop i =
      let line = input_line chan in
      if i = 1 then		(* discard the first line of output *)
        loop (i+1)
      else (
        let line = triml line in
        lines := line :: !lines;
        loop (i+1)
      ) in
    let lines = try loop 1 with End_of_file -> List.rev !lines in
    unlink filename;
    (match close_process_in chan with
     | WEXITED 0 -> ()
     | WEXITED i ->
         failwithf "pod2text: process exited with non-zero status (%d)" i
     | WSIGNALED i | WSTOPPED i ->
         failwithf "pod2text: process signalled or stopped by signal %d" i
    );
    Hashtbl.add pod2text_memo key lines;
    pod2text_memo_updated ();
    lines

(* Generate ruby bindings. *)
and generate_ruby_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>

#include <ruby.h>

#include \"guestfs.h\"

#include \"extconf.h\"

/* For Ruby < 1.9 */
#ifndef RARRAY_LEN
#define RARRAY_LEN(r) (RARRAY((r))->len)
#endif

static VALUE m_guestfs;			/* guestfs module */
static VALUE c_guestfs;			/* guestfs_h handle */
static VALUE e_Error;			/* used for all errors */

static void ruby_guestfs_free (void *p)
{
  if (!p) return;
  guestfs_close ((guestfs_h *) p);
}

static VALUE ruby_guestfs_create (VALUE m)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (!g)
    rb_raise (e_Error, \"failed to create guestfs handle\");

  /* Don't print error messages to stderr by default. */
  guestfs_set_error_handler (g, NULL, NULL);

  /* Wrap it, and make sure the close function is called when the
   * handle goes away.
   */
  return Data_Wrap_Struct (c_guestfs, NULL, ruby_guestfs_free, g);
}

static VALUE ruby_guestfs_close (VALUE gv)
{
  guestfs_h *g;
  Data_Get_Struct (gv, guestfs_h, g);

  ruby_guestfs_free (g);
  DATA_PTR (gv) = NULL;

  return Qnil;
}

";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "static VALUE ruby_guestfs_%s (VALUE gv" name;
      List.iter (fun arg -> pr ", VALUE %sv" (name_of_argt arg)) (snd style);
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g;\n";
      pr "  Data_Get_Struct (gv, guestfs_h, g);\n";
      pr "  if (!g)\n";
      pr "    rb_raise (rb_eArgError, \"%%s: used handle after closing it\", \"%s\");\n"
        name;
      pr "\n";

      List.iter (
        function
        | Pathname n | Device n | Dev_or_Path n | String n | FileIn n | FileOut n ->
            pr "  Check_Type (%sv, T_STRING);\n" n;
            pr "  const char *%s = StringValueCStr (%sv);\n" n n;
            pr "  if (!%s)\n" n;
            pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
            pr "              \"%s\", \"%s\");\n" n name
        | OptString n ->
            pr "  const char *%s = !NIL_P (%sv) ? StringValueCStr (%sv) : NULL;\n" n n n
        | StringList n | DeviceList n ->
            pr "  char **%s;\n" n;
            pr "  Check_Type (%sv, T_ARRAY);\n" n;
            pr "  {\n";
            pr "    int i, len;\n";
            pr "    len = RARRAY_LEN (%sv);\n" n;
            pr "    %s = guestfs_safe_malloc (g, sizeof (char *) * (len+1));\n"
              n;
            pr "    for (i = 0; i < len; ++i) {\n";
            pr "      VALUE v = rb_ary_entry (%sv, i);\n" n;
            pr "      %s[i] = StringValueCStr (v);\n" n;
            pr "    }\n";
            pr "    %s[len] = NULL;\n" n;
            pr "  }\n";
        | Bool n ->
            pr "  int %s = RTEST (%sv);\n" n n
        | Int n ->
            pr "  int %s = NUM2INT (%sv);\n" n n
        | Int64 n ->
            pr "  long long %s = NUM2LL (%sv);\n" n n
      ) (snd style);
      pr "\n";

      let error_code =
        match fst style with
        | RErr | RInt _ | RBool _ -> pr "  int r;\n"; "-1"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1"
        | RConstString _ | RConstOptString _ ->
            pr "  const char *r;\n"; "NULL"
        | RString _ -> pr "  char *r;\n"; "NULL"
        | RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
        | RStruct (_, typ) -> pr "  struct guestfs_%s *r;\n" typ; "NULL"
        | RStructList (_, typ) ->
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL"
        | RBufferOut _ ->
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL" in
      pr "\n";

      pr "  r = guestfs_%s " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      List.iter (
        function
        | Pathname _ | Device _ | Dev_or_Path _ | String _
        | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ | Int64 _ -> ()
        | StringList n | DeviceList n ->
            pr "  free (%s);\n" n
      ) (snd style);

      pr "  if (r == %s)\n" error_code;
      pr "    rb_raise (e_Error, \"%%s\", guestfs_last_error (g));\n";
      pr "\n";

      (match fst style with
       | RErr ->
           pr "  return Qnil;\n"
       | RInt _ | RBool _ ->
           pr "  return INT2NUM (r);\n"
       | RInt64 _ ->
           pr "  return ULL2NUM (r);\n"
       | RConstString _ ->
           pr "  return rb_str_new2 (r);\n";
       | RConstOptString _ ->
           pr "  if (r)\n";
           pr "    return rb_str_new2 (r);\n";
           pr "  else\n";
           pr "    return Qnil;\n";
       | RString _ ->
           pr "  VALUE rv = rb_str_new2 (r);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
       | RStringList _ ->
           pr "  int i, len = 0;\n";
           pr "  for (i = 0; r[i] != NULL; ++i) len++;\n";
           pr "  VALUE rv = rb_ary_new2 (len);\n";
           pr "  for (i = 0; r[i] != NULL; ++i) {\n";
           pr "    rb_ary_push (rv, rb_str_new2 (r[i]));\n";
           pr "    free (r[i]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RStruct (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_code typ cols
       | RStructList (_, typ) ->
           let cols = cols_of_struct typ in
           generate_ruby_struct_list_code typ cols
       | RHashtable _ ->
           pr "  VALUE rv = rb_hash_new ();\n";
           pr "  int i;\n";
           pr "  for (i = 0; r[i] != NULL; i+=2) {\n";
           pr "    rb_hash_aset (rv, rb_str_new2 (r[i]), rb_str_new2 (r[i+1]));\n";
           pr "    free (r[i]);\n";
           pr "    free (r[i+1]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return rv;\n"
       | RBufferOut _ ->
           pr "  VALUE rv = rb_str_new (r, size);\n";
           pr "  free (r);\n";
           pr "  return rv;\n";
      );

      pr "}\n";
      pr "\n"
  ) all_functions;

  pr "\
/* Initialize the module. */
void Init__guestfs ()
{
  m_guestfs = rb_define_module (\"Guestfs\");
  c_guestfs = rb_define_class_under (m_guestfs, \"Guestfs\", rb_cObject);
  e_Error = rb_define_class_under (m_guestfs, \"Error\", rb_eStandardError);

  rb_define_module_function (m_guestfs, \"create\", ruby_guestfs_create, 0);
  rb_define_method (c_guestfs, \"close\", ruby_guestfs_close, 0);

";
  (* Define the rest of the methods. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "  rb_define_method (c_guestfs, \"%s\",\n" name;
      pr "        ruby_guestfs_%s, %d);\n" name (List.length (snd style))
  ) all_functions;

  pr "}\n"

(* Ruby code to return a struct. *)
and generate_ruby_struct_code typ cols =
  pr "  VALUE rv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new2 (r->%s));\n" name name
    | name, FBuffer ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, r->%s_len));\n" name name name
    | name, FUUID ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
    | name, FInt64 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), LL2NUM (r->%s));\n" name name
    | name, FUInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), UINT2NUM (r->%s));\n" name name
    | name, FInt32 ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), INT2NUM (r->%s));\n" name name
    | name, FOptPercent ->
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_dbl2big (r->%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
  ) cols;
  pr "  guestfs_free_%s (r);\n" typ;
  pr "  return rv;\n"

(* Ruby code to return a struct list. *)
and generate_ruby_struct_list_code typ cols =
  pr "  VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  int i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    VALUE hv = rb_hash_new ();\n";
  List.iter (
    function
    | name, FString ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new2 (r->val[i].%s));\n" name name
    | name, FBuffer ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, r->val[i].%s_len));\n" name name name
    | name, FUUID ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, 32));\n" name name
    | name, (FBytes|FUInt64) ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
    | name, FInt64 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), LL2NUM (r->val[i].%s));\n" name name
    | name, FUInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), UINT2NUM (r->val[i].%s));\n" name name
    | name, FInt32 ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), INT2NUM (r->val[i].%s));\n" name name
    | name, FOptPercent ->
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), rb_dbl2big (r->val[i].%s));\n" name name
    | name, FChar -> (* XXX wrong? *)
        pr "    rb_hash_aset (hv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
  ) cols;
  pr "    rb_ary_push (rv, hv);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ;
  pr "  return rv;\n"

(* Generate Java bindings GuestFS.java file. *)
and generate_java_java () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

import java.util.HashMap;
import com.redhat.et.libguestfs.LibGuestFSException;
import com.redhat.et.libguestfs.PV;
import com.redhat.et.libguestfs.VG;
import com.redhat.et.libguestfs.LV;
import com.redhat.et.libguestfs.Stat;
import com.redhat.et.libguestfs.StatVFS;
import com.redhat.et.libguestfs.IntBool;
import com.redhat.et.libguestfs.Dirent;

/**
 * The GuestFS object is a libguestfs handle.
 *
 * @author rjones
 */
public class GuestFS {
  // Load the native code.
  static {
    System.loadLibrary (\"guestfs_jni\");
  }

  /**
   * The native guestfs_h pointer.
   */
  long g;

  /**
   * Create a libguestfs handle.
   *
   * @throws LibGuestFSException
   */
  public GuestFS () throws LibGuestFSException
  {
    g = _create ();
  }
  private native long _create () throws LibGuestFSException;

  /**
   * Close a libguestfs handle.
   *
   * You can also leave handles to be collected by the garbage
   * collector, but this method ensures that the resources used
   * by the handle are freed up immediately.  If you call any
   * other methods after closing the handle, you will get an
   * exception.
   *
   * @throws LibGuestFSException
   */
  public void close () throws LibGuestFSException
  {
    if (g != 0)
      _close (g);
    g = 0;
  }
  private native void _close (long g) throws LibGuestFSException;

  public void finalize () throws LibGuestFSException
  {
    close ();
  }

";

  List.iter (
    fun (name, style, _, flags, _, shortdesc, longdesc) ->
      if not (List.mem NotInDocs flags); then (
        let doc = replace_str longdesc "C<guestfs_" "C<g." in
        let doc =
          if List.mem ProtocolLimitWarning flags then
            doc ^ "\n\n" ^ protocol_limit_warning
          else doc in
        let doc =
          if List.mem DangerWillRobinson flags then
            doc ^ "\n\n" ^ danger_will_robinson
          else doc in
        let doc =
          match deprecation_notice flags with
          | None -> doc
          | Some txt -> doc ^ "\n\n" ^ txt in
        let doc = pod2text ~width:60 name doc in
        let doc = List.map (		(* RHBZ#501883 *)
          function
          | "" -> "<p>"
          | nonempty -> nonempty
        ) doc in
        let doc = String.concat "\n   * " doc in

        pr "  /**\n";
        pr "   * %s\n" shortdesc;
        pr "   * <p>\n";
        pr "   * %s\n" doc;
        pr "   * @throws LibGuestFSException\n";
        pr "   */\n";
        pr "  ";
      );
      generate_java_prototype ~public:true ~semicolon:false name style;
      pr "\n";
      pr "  {\n";
      pr "    if (g == 0)\n";
      pr "      throw new LibGuestFSException (\"%s: handle is closed\");\n"
        name;
      pr "    ";
      if fst style <> RErr then pr "return ";
      pr "_%s " name;
      generate_java_call_args ~handle:"g" (snd style);
      pr ";\n";
      pr "  }\n";
      pr "  ";
      generate_java_prototype ~privat:true ~native:true name style;
      pr "\n";
      pr "\n";
  ) all_functions;

  pr "}\n"

(* Generate Java call arguments, eg "(handle, foo, bar)" *)
and generate_java_call_args ~handle args =
  pr "(%s" handle;
  List.iter (fun arg -> pr ", %s" (name_of_argt arg)) args;
  pr ")"

and generate_java_prototype ?(public=false) ?(privat=false) ?(native=false)
    ?(semicolon=true) name style =
  if privat then pr "private ";
  if public then pr "public ";
  if native then pr "native ";

  (* return type *)
  (match fst style with
   | RErr -> pr "void ";
   | RInt _ -> pr "int ";
   | RInt64 _ -> pr "long ";
   | RBool _ -> pr "boolean ";
   | RConstString _ | RConstOptString _ | RString _
   | RBufferOut _ -> pr "String ";
   | RStringList _ -> pr "String[] ";
   | RStruct (_, typ) ->
       let name = java_name_of_struct typ in
       pr "%s " name;
   | RStructList (_, typ) ->
       let name = java_name_of_struct typ in
       pr "%s[] " name;
   | RHashtable _ -> pr "HashMap<String,String> ";
  );

  if native then pr "_%s " name else pr "%s " name;
  pr "(";
  let needs_comma = ref false in
  if native then (
    pr "long g";
    needs_comma := true
  );

  (* args *)
  List.iter (
    fun arg ->
      if !needs_comma then pr ", ";
      needs_comma := true;

      match arg with
      | Pathname n
      | Device n | Dev_or_Path n
      | String n
      | OptString n
      | FileIn n
      | FileOut n ->
          pr "String %s" n
      | StringList n | DeviceList n ->
          pr "String[] %s" n
      | Bool n ->
          pr "boolean %s" n
      | Int n ->
          pr "int %s" n
      | Int64 n ->
          pr "long %s" n
  ) (snd style);

  pr ")\n";
  pr "    throws LibGuestFSException";
  if semicolon then pr ";"

and generate_java_struct jtyp cols () =
  generate_header CStyle LGPLv2plus;

  pr "\
package com.redhat.et.libguestfs;

/**
 * Libguestfs %s structure.
 *
 * @author rjones
 * @see GuestFS
 */
public class %s {
" jtyp jtyp;

  List.iter (
    function
    | name, FString
    | name, FUUID
    | name, FBuffer -> pr "  public String %s;\n" name
    | name, (FBytes|FUInt64|FInt64) -> pr "  public long %s;\n" name
    | name, (FUInt32|FInt32) -> pr "  public int %s;\n" name
    | name, FChar -> pr "  public char %s;\n" name
    | name, FOptPercent ->
        pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
        pr "  public float %s;\n" name
  ) cols;

  pr "}\n"

and generate_java_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include \"com_redhat_et_libguestfs_GuestFS.h\"
#include \"guestfs.h\"

/* Note that this function returns.  The exception is not thrown
 * until after the wrapper function returns.
 */
static void
throw_exception (JNIEnv *env, const char *msg)
{
  jclass cl;
  cl = (*env)->FindClass (env,
                          \"com/redhat/et/libguestfs/LibGuestFSException\");
  (*env)->ThrowNew (env, cl, msg);
}

JNIEXPORT jlong JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1create
  (JNIEnv *env, jobject obj)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL) {
    throw_exception (env, \"GuestFS.create: failed to allocate handle\");
    return 0;
  }
  guestfs_set_error_handler (g, NULL, NULL);
  return (jlong) (long) g;
}

JNIEXPORT void JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1close
  (JNIEnv *env, jobject obj, jlong jg)
{
  guestfs_h *g = (guestfs_h *) (long) jg;
  guestfs_close (g);
}

";

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      pr "JNIEXPORT ";
      (match fst style with
       | RErr -> pr "void ";
       | RInt _ -> pr "jint ";
       | RInt64 _ -> pr "jlong ";
       | RBool _ -> pr "jboolean ";
       | RConstString _ | RConstOptString _ | RString _
       | RBufferOut _ -> pr "jstring ";
       | RStruct _ | RHashtable _ ->
           pr "jobject ";
       | RStringList _ | RStructList _ ->
           pr "jobjectArray ";
      );
      pr "JNICALL\n";
      pr "Java_com_redhat_et_libguestfs_GuestFS_";
      pr "%s" (replace_str ("_" ^ name) "_" "_1");
      pr "\n";
      pr "  (JNIEnv *env, jobject obj, jlong jg";
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n ->
            pr ", jstring j%s" n
        | StringList n | DeviceList n ->
            pr ", jobjectArray j%s" n
        | Bool n ->
            pr ", jboolean j%s" n
        | Int n ->
            pr ", jint j%s" n
        | Int64 n ->
            pr ", jlong j%s" n
      ) (snd style);
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g = (guestfs_h *) (long) jg;\n";
      let error_code, no_ret =
        match fst style with
        | RErr -> pr "  int r;\n"; "-1", ""
        | RBool _
        | RInt _ -> pr "  int r;\n"; "-1", "0"
        | RInt64 _ -> pr "  int64_t r;\n"; "-1", "0"
        | RConstString _ -> pr "  const char *r;\n"; "NULL", "NULL"
        | RConstOptString _ -> pr "  const char *r;\n"; "NULL", "NULL"
        | RString _ ->
            pr "  jstring jr;\n";
            pr "  char *r;\n"; "NULL", "NULL"
        | RStringList _ ->
            pr "  jobjectArray jr;\n";
            pr "  int r_len;\n";
            pr "  jclass cl;\n";
            pr "  jstring jstr;\n";
            pr "  char **r;\n"; "NULL", "NULL"
        | RStruct (_, typ) ->
            pr "  jobject jr;\n";
            pr "  jclass cl;\n";
            pr "  jfieldID fl;\n";
            pr "  struct guestfs_%s *r;\n" typ; "NULL", "NULL"
        | RStructList (_, typ) ->
            pr "  jobjectArray jr;\n";
            pr "  jclass cl;\n";
            pr "  jfieldID fl;\n";
            pr "  jobject jfl;\n";
            pr "  struct guestfs_%s_list *r;\n" typ; "NULL", "NULL"
        | RHashtable _ -> pr "  char **r;\n"; "NULL", "NULL"
        | RBufferOut _ ->
            pr "  jstring jr;\n";
            pr "  char *r;\n";
            pr "  size_t size;\n";
            "NULL", "NULL" in
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | OptString n
        | FileIn n
        | FileOut n ->
            pr "  const char *%s;\n" n
        | StringList n | DeviceList n ->
            pr "  int %s_len;\n" n;
            pr "  const char **%s;\n" n
        | Bool n
        | Int n ->
            pr "  int %s;\n" n
        | Int64 n ->
            pr "  int64_t %s;\n" n
      ) (snd style);

      let needs_i =
        (match fst style with
         | RStringList _ | RStructList _ -> true
         | RErr | RBool _ | RInt _ | RInt64 _ | RConstString _
         | RConstOptString _
         | RString _ | RBufferOut _ | RStruct _ | RHashtable _ -> false) ||
          List.exists (function
                       | StringList _ -> true
                       | DeviceList _ -> true
                       | _ -> false) (snd style) in
      if needs_i then
        pr "  int i;\n";

      pr "\n";

      (* Get the parameters. *)
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | FileIn n
        | FileOut n ->
            pr "  %s = (*env)->GetStringUTFChars (env, j%s, NULL);\n" n n
        | OptString n ->
            (* This is completely undocumented, but Java null becomes
             * a NULL parameter.
             *)
            pr "  %s = j%s ? (*env)->GetStringUTFChars (env, j%s, NULL) : NULL;\n" n n n
        | StringList n | DeviceList n ->
            pr "  %s_len = (*env)->GetArrayLength (env, j%s);\n" n n;
            pr "  %s = guestfs_safe_malloc (g, sizeof (char *) * (%s_len+1));\n" n n;
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    %s[i] = (*env)->GetStringUTFChars (env, o, NULL);\n" n;
            pr "  }\n";
            pr "  %s[%s_len] = NULL;\n" n n;
        | Bool n
        | Int n
        | Int64 n ->
            pr "  %s = j%s;\n" n n
      ) (snd style);

      (* Make the call. *)
      pr "  r = guestfs_%s " name;
      generate_c_call_args ~handle:"g" style;
      pr ";\n";

      (* Release the parameters. *)
      List.iter (
        function
        | Pathname n
        | Device n | Dev_or_Path n
        | String n
        | FileIn n
        | FileOut n ->
            pr "  (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | OptString n ->
            pr "  if (j%s)\n" n;
            pr "    (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
        | StringList n | DeviceList n ->
            pr "  for (i = 0; i < %s_len; ++i) {\n" n;
            pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
              n;
            pr "    (*env)->ReleaseStringUTFChars (env, o, %s[i]);\n" n;
            pr "  }\n";
            pr "  free (%s);\n" n
        | Bool n
        | Int n
        | Int64 n -> ()
      ) (snd style);

      (* Check for errors. *)
      pr "  if (r == %s) {\n" error_code;
      pr "    throw_exception (env, guestfs_last_error (g));\n";
      pr "    return %s;\n" no_ret;
      pr "  }\n";

      (* Return value. *)
      (match fst style with
       | RErr -> ()
       | RInt _ -> pr "  return (jint) r;\n"
       | RBool _ -> pr "  return (jboolean) r;\n"
       | RInt64 _ -> pr "  return (jlong) r;\n"
       | RConstString _ -> pr "  return (*env)->NewStringUTF (env, r);\n"
       | RConstOptString _ ->
           pr "  return (*env)->NewStringUTF (env, r); /* XXX r NULL? */\n"
       | RString _ ->
           pr "  jr = (*env)->NewStringUTF (env, r);\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
       | RStringList _ ->
           pr "  for (r_len = 0; r[r_len] != NULL; ++r_len) ;\n";
           pr "  cl = (*env)->FindClass (env, \"java/lang/String\");\n";
           pr "  jstr = (*env)->NewStringUTF (env, \"\");\n";
           pr "  jr = (*env)->NewObjectArray (env, r_len, cl, jstr);\n";
           pr "  for (i = 0; i < r_len; ++i) {\n";
           pr "    jstr = (*env)->NewStringUTF (env, r[i]);\n";
           pr "    (*env)->SetObjectArrayElement (env, jr, i, jstr);\n";
           pr "    free (r[i]);\n";
           pr "  }\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
       | RStruct (_, typ) ->
           let jtyp = java_name_of_struct typ in
           let cols = cols_of_struct typ in
           generate_java_struct_return typ jtyp cols
       | RStructList (_, typ) ->
           let jtyp = java_name_of_struct typ in
           let cols = cols_of_struct typ in
           generate_java_struct_list_return typ jtyp cols
       | RHashtable _ ->
           (* XXX *)
           pr "  throw_exception (env, \"%s: internal error: please let us know how to make a Java HashMap from JNI bindings!\");\n" name;
           pr "  return NULL;\n"
       | RBufferOut _ ->
           pr "  jr = (*env)->NewStringUTF (env, r); /* XXX size */\n";
           pr "  free (r);\n";
           pr "  return jr;\n"
      );

      pr "}\n";
      pr "\n"
  ) all_functions

and generate_java_struct_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->AllocObject (env, cl);\n";
  List.iter (
    function
    | name, FString ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "  (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, r->%s));\n" name;
    | name, FUUID ->
        pr "  {\n";
        pr "    char s[33];\n";
        pr "    memcpy (s, r->%s, 32);\n" name;
        pr "    s[32] = 0;\n";
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, s));\n";
        pr "  }\n";
    | name, FBuffer ->
        pr "  {\n";
        pr "    int len = r->%s_len;\n" name;
        pr "    char s[len+1];\n";
        pr "    memcpy (s, r->%s, len);\n" name;
        pr "    s[len] = 0;\n";
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jr, fl, (*env)->NewStringUTF (env, s));\n";
        pr "  }\n";
    | name, (FBytes|FUInt64|FInt64) ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n" name;
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
    | name, (FUInt32|FInt32) ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"I\");\n" name;
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
    | name, FOptPercent ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
        pr "  (*env)->SetFloatField (env, jr, fl, r->%s);\n" name;
    | name, FChar ->
        pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"C\");\n" name;
        pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
  ) cols;
  pr "  free (r);\n";
  pr "  return jr;\n"

and generate_java_struct_list_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->NewObjectArray (env, r->len, cl, NULL);\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    jfl = (*env)->AllocObject (env, cl);\n";
  List.iter (
    function
    | name, FString ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "    (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, r->val[i].%s));\n" name;
    | name, FUUID ->
        pr "    {\n";
        pr "      char s[33];\n";
        pr "      memcpy (s, r->val[i].%s, 32);\n" name;
        pr "      s[32] = 0;\n";
        pr "      fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "      (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
    | name, FBuffer ->
        pr "    {\n";
        pr "      int len = r->val[i].%s_len;\n" name;
        pr "      char s[len+1];\n";
        pr "      memcpy (s, r->val[i].%s, len);\n" name;
        pr "      s[len] = 0;\n";
        pr "      fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
        pr "      (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, s));\n";
        pr "    }\n";
    | name, (FBytes|FUInt64|FInt64) ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, (FUInt32|FInt32) ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"I\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, FOptPercent ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
        pr "    (*env)->SetFloatField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, FChar ->
        pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"C\");\n" name;
        pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
  ) cols;
  pr "    (*env)->SetObjectArrayElement (env, jfl, i, jfl);\n";
  pr "  }\n";
  pr "  guestfs_free_%s_list (r);\n" typ;
  pr "  return jr;\n"

and generate_java_makefile_inc () =
  generate_header HashStyle GPLv2plus;

  pr "java_built_sources = \\\n";
  List.iter (
    fun (typ, jtyp) ->
        pr "\tcom/redhat/et/libguestfs/%s.java \\\n" jtyp;
  ) java_structs;
  pr "\tcom/redhat/et/libguestfs/GuestFS.java\n"

and generate_haskell_hs () =
  generate_header HaskellStyle LGPLv2plus;

  (* XXX We only know how to generate partial FFI for Haskell
   * at the moment.  Please help out!
   *)
  let can_generate style =
    match style with
    | RErr, _
    | RInt _, _
    | RInt64 _, _ -> true
    | RBool _, _
    | RConstString _, _
    | RConstOptString _, _
    | RString _, _
    | RStringList _, _
    | RStruct _, _
    | RStructList _, _
    | RHashtable _, _
    | RBufferOut _, _ -> false in

  pr "\
{-# INCLUDE <guestfs.h> #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module Guestfs (
  create";

  (* List out the names of the actions we want to export. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      if can_generate style then pr ",\n  %s" name
  ) all_functions;

  pr "
  ) where

-- Unfortunately some symbols duplicate ones already present
-- in Prelude.  We don't know which, so we hard-code a list
-- here.
import Prelude hiding (truncate)

import Foreign
import Foreign.C
import Foreign.C.Types
import IO
import Control.Exception
import Data.Typeable

data GuestfsS = GuestfsS            -- represents the opaque C struct
type GuestfsP = Ptr GuestfsS        -- guestfs_h *
type GuestfsH = ForeignPtr GuestfsS -- guestfs_h * with attached finalizer

-- XXX define properly later XXX
data PV = PV
data VG = VG
data LV = LV
data IntBool = IntBool
data Stat = Stat
data StatVFS = StatVFS
data Hashtable = Hashtable

foreign import ccall unsafe \"guestfs_create\" c_create
  :: IO GuestfsP
foreign import ccall unsafe \"&guestfs_close\" c_close
  :: FunPtr (GuestfsP -> IO ())
foreign import ccall unsafe \"guestfs_set_error_handler\" c_set_error_handler
  :: GuestfsP -> Ptr CInt -> Ptr CInt -> IO ()

create :: IO GuestfsH
create = do
  p <- c_create
  c_set_error_handler p nullPtr nullPtr
  h <- newForeignPtr c_close p
  return h

foreign import ccall unsafe \"guestfs_last_error\" c_last_error
  :: GuestfsP -> IO CString

-- last_error :: GuestfsH -> IO (Maybe String)
-- last_error h = do
--   str <- withForeignPtr h (\\p -> c_last_error p)
--   maybePeek peekCString str

last_error :: GuestfsH -> IO (String)
last_error h = do
  str <- withForeignPtr h (\\p -> c_last_error p)
  if (str == nullPtr)
    then return \"no error\"
    else peekCString str

";

  (* Generate wrappers for each foreign function. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      if can_generate style then (
        pr "foreign import ccall unsafe \"guestfs_%s\" c_%s\n" name name;
        pr "  :: ";
        generate_haskell_prototype ~handle:"GuestfsP" style;
        pr "\n";
        pr "\n";
        pr "%s :: " name;
        generate_haskell_prototype ~handle:"GuestfsH" ~hs:true style;
        pr "\n";
        pr "%s %s = do\n" name
          (String.concat " " ("h" :: List.map name_of_argt (snd style)));
        pr "  r <- ";
        (* Convert pointer arguments using with* functions. *)
        List.iter (
          function
          | FileIn n
          | FileOut n
          | Pathname n | Device n | Dev_or_Path n | String n -> pr "withCString %s $ \\%s -> " n n
          | OptString n -> pr "maybeWith withCString %s $ \\%s -> " n n
          | StringList n | DeviceList n -> pr "withMany withCString %s $ \\%s -> withArray0 nullPtr %s $ \\%s -> " n n n n
          | Bool _ | Int _ | Int64 _ -> ()
        ) (snd style);
        (* Convert integer arguments. *)
        let args =
          List.map (
            function
            | Bool n -> sprintf "(fromBool %s)" n
            | Int n -> sprintf "(fromIntegral %s)" n
            | Int64 n -> sprintf "(fromIntegral %s)" n
            | FileIn n | FileOut n
            | Pathname n | Device n | Dev_or_Path n | String n | OptString n | StringList n | DeviceList n -> n
          ) (snd style) in
        pr "withForeignPtr h (\\p -> c_%s %s)\n" name
          (String.concat " " ("p" :: args));
        (match fst style with
         | RErr | RInt _ | RInt64 _ | RBool _ ->
             pr "  if (r == -1)\n";
             pr "    then do\n";
             pr "      err <- last_error h\n";
             pr "      fail err\n";
         | RConstString _ | RConstOptString _ | RString _
         | RStringList _ | RStruct _
         | RStructList _ | RHashtable _ | RBufferOut _ ->
             pr "  if (r == nullPtr)\n";
             pr "    then do\n";
             pr "      err <- last_error h\n";
             pr "      fail err\n";
        );
        (match fst style with
         | RErr ->
             pr "    else return ()\n"
         | RInt _ ->
             pr "    else return (fromIntegral r)\n"
         | RInt64 _ ->
             pr "    else return (fromIntegral r)\n"
         | RBool _ ->
             pr "    else return (toBool r)\n"
         | RConstString _
         | RConstOptString _
         | RString _
         | RStringList _
         | RStruct _
         | RStructList _
         | RHashtable _
         | RBufferOut _ ->
             pr "    else return ()\n" (* XXXXXXXXXXXXXXXXXXXX *)
        );
        pr "\n";
      )
  ) all_functions

and generate_haskell_prototype ~handle ?(hs = false) style =
  pr "%s -> " handle;
  let string = if hs then "String" else "CString" in
  let int = if hs then "Int" else "CInt" in
  let bool = if hs then "Bool" else "CInt" in
  let int64 = if hs then "Integer" else "Int64" in
  List.iter (
    fun arg ->
      (match arg with
       | Pathname _ | Device _ | Dev_or_Path _ | String _ -> pr "%s" string
       | OptString _ -> if hs then pr "Maybe String" else pr "CString"
       | StringList _ | DeviceList _ -> if hs then pr "[String]" else pr "Ptr CString"
       | Bool _ -> pr "%s" bool
       | Int _ -> pr "%s" int
       | Int64 _ -> pr "%s" int
       | FileIn _ -> pr "%s" string
       | FileOut _ -> pr "%s" string
      );
      pr " -> ";
  ) (snd style);
  pr "IO (";
  (match fst style with
   | RErr -> if not hs then pr "CInt"
   | RInt _ -> pr "%s" int
   | RInt64 _ -> pr "%s" int64
   | RBool _ -> pr "%s" bool
   | RConstString _ -> pr "%s" string
   | RConstOptString _ -> pr "Maybe %s" string
   | RString _ -> pr "%s" string
   | RStringList _ -> pr "[%s]" string
   | RStruct (_, typ) ->
       let name = java_name_of_struct typ in
       pr "%s" name
   | RStructList (_, typ) ->
       let name = java_name_of_struct typ in
       pr "[%s]" name
   | RHashtable _ -> pr "Hashtable"
   | RBufferOut _ -> pr "%s" string
  );
  pr ")"

and generate_csharp () =
  generate_header CPlusPlusStyle LGPLv2plus;

  (* XXX Make this configurable by the C# assembly users. *)
  let library = "libguestfs.so.0" in

  pr "\
// These C# bindings are highly experimental at present.
//
// Firstly they only work on Linux (ie. Mono).  In order to get them
// to work on Windows (ie. .Net) you would need to port the library
// itself to Windows first.
//
// The second issue is that some calls are known to be incorrect and
// can cause Mono to segfault.  Particularly: calls which pass or
// return string[], or return any structure value.  This is because
// we haven't worked out the correct way to do this from C#.
//
// The third issue is that when compiling you get a lot of warnings.
// We are not sure whether the warnings are important or not.
//
// Fourthly we do not routinely build or test these bindings as part
// of the make && make check cycle, which means that regressions might
// go unnoticed.
//
// Suggestions and patches are welcome.

// To compile:
//
// gmcs Libguestfs.cs
// mono Libguestfs.exe
//
// (You'll probably want to add a Test class / static main function
// otherwise this won't do anything useful).

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Collections;

namespace Guestfs
{
  class Error : System.ApplicationException
  {
    public Error (string message) : base (message) {}
    protected Error (SerializationInfo info, StreamingContext context) {}
  }

  class Guestfs
  {
    IntPtr _handle;

    [DllImport (\"%s\")]
    static extern IntPtr guestfs_create ();

    public Guestfs ()
    {
      _handle = guestfs_create ();
      if (_handle == IntPtr.Zero)
        throw new Error (\"could not create guestfs handle\");
    }

    [DllImport (\"%s\")]
    static extern void guestfs_close (IntPtr h);

    ~Guestfs ()
    {
      guestfs_close (_handle);
    }

    [DllImport (\"%s\")]
    static extern string guestfs_last_error (IntPtr h);

" library library library;

  (* Generate C# structure bindings.  We prefix struct names with
   * underscore because C# cannot have conflicting struct names and
   * method names (eg. "class stat" and "stat").
   *)
  List.iter (
    fun (typ, cols) ->
      pr "    [StructLayout (LayoutKind.Sequential)]\n";
      pr "    public class _%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "      char %s;\n" name
        | name, FString -> pr "      string %s;\n" name
        | name, FBuffer ->
            pr "      uint %s_len;\n" name;
            pr "      string %s;\n" name
        | name, FUUID ->
            pr "      [MarshalAs (UnmanagedType.ByValTStr, SizeConst=16)]\n";
            pr "      string %s;\n" name
        | name, FUInt32 -> pr "      uint %s;\n" name
        | name, FInt32 -> pr "      int %s;\n" name
        | name, (FUInt64|FBytes) -> pr "      ulong %s;\n" name
        | name, FInt64 -> pr "      long %s;\n" name
        | name, FOptPercent -> pr "      float %s; /* [0..100] or -1 */\n" name
      ) cols;
      pr "    }\n";
      pr "\n"
  ) structs;

  (* Generate C# function bindings. *)
  List.iter (
    fun (name, style, _, _, _, shortdesc, _) ->
      let rec csharp_return_type () =
	match fst style with
	| RErr -> "void"
	| RBool n -> "bool"
	| RInt n -> "int"
	| RInt64 n -> "long"
	| RConstString n
	| RConstOptString n
	| RString n
	| RBufferOut n -> "string"
	| RStruct (_,n) -> "_" ^ n
	| RHashtable n -> "Hashtable"
	| RStringList n -> "string[]"
	| RStructList (_,n) -> sprintf "_%s[]" n

      and c_return_type () =
	match fst style with
	| RErr
	| RBool _
	| RInt _ -> "int"
	| RInt64 _ -> "long"
	| RConstString _
	| RConstOptString _
	| RString _
	| RBufferOut _ -> "string"
	| RStruct (_,n) -> "_" ^ n
	| RHashtable _
	| RStringList _ -> "string[]"
	| RStructList (_,n) -> sprintf "_%s[]" n
    
      and c_error_comparison () =
	match fst style with
	| RErr
	| RBool _
	| RInt _
	| RInt64 _ -> "== -1"
	| RConstString _
	| RConstOptString _
	| RString _
	| RBufferOut _
	| RStruct (_,_)
	| RHashtable _
	| RStringList _
	| RStructList (_,_) -> "== null"
    
      and generate_extern_prototype () =
	pr "    static extern %s guestfs_%s (IntPtr h"
	  (c_return_type ()) name;
	List.iter (
	  function
	  | Pathname n | Device n | Dev_or_Path n | String n | OptString n
	  | FileIn n | FileOut n ->
              pr ", [In] string %s" n
	  | StringList n | DeviceList n ->
              pr ", [In] string[] %s" n
	  | Bool n ->
	      pr ", bool %s" n
	  | Int n ->
	      pr ", int %s" n
	  | Int64 n ->
	      pr ", long %s" n
	) (snd style);
	pr ");\n"

      and generate_public_prototype () =
	pr "    public %s %s (" (csharp_return_type ()) name;
	let comma = ref false in
	let next () =
	  if !comma then pr ", ";
	  comma := true
	in
	List.iter (
	  function
	  | Pathname n | Device n | Dev_or_Path n | String n | OptString n
	  | FileIn n | FileOut n ->
              next (); pr "string %s" n
	  | StringList n | DeviceList n ->
              next (); pr "string[] %s" n
	  | Bool n ->
	      next (); pr "bool %s" n
	  | Int n ->
	      next (); pr "int %s" n
	  | Int64 n ->
	      next (); pr "long %s" n
	) (snd style);
	pr ")\n"

      and generate_call () =
	pr "guestfs_%s (_handle" name;
	List.iter (fun arg -> pr ", %s" (name_of_argt arg)) (snd style);
	pr ");\n";
      in

      pr "    [DllImport (\"%s\")]\n" library;
      generate_extern_prototype ();
      pr "\n";
      pr "    /// <summary>\n";
      pr "    /// %s\n" shortdesc;
      pr "    /// </summary>\n";
      generate_public_prototype ();
      pr "    {\n";
      pr "      %s r;\n" (c_return_type ());
      pr "      r = ";
      generate_call ();
      pr "      if (r %s)\n" (c_error_comparison ());
      pr "        throw new Error (\"%s: \" + guestfs_last_error (_handle));\n"
        name;
      (match fst style with
       | RErr -> ()
       | RBool _ ->
           pr "      return r != 0 ? true : false;\n"
       | RHashtable _ ->
           pr "      Hashtable rr = new Hashtable ();\n";
           pr "      for (int i = 0; i < r.Length; i += 2)\n";
           pr "        rr.Add (r[i], r[i+1]);\n";
           pr "      return rr;\n"
       | RInt _ | RInt64 _ | RConstString _ | RConstOptString _
       | RString _ | RBufferOut _ | RStruct _ | RStringList _
       | RStructList _ ->
           pr "      return r;\n"
      );
      pr "    }\n";
      pr "\n";
  ) all_functions_sorted;

  pr "  }
}
"

and generate_bindtests () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>

#include \"guestfs.h\"
#include \"guestfs-internal.h\"
#include \"guestfs-internal-actions.h\"
#include \"guestfs_protocol.h\"

#define error guestfs_error
#define safe_calloc guestfs_safe_calloc
#define safe_malloc guestfs_safe_malloc

static void
print_strings (char *const *argv)
{
  int argc;

  printf (\"[\");
  for (argc = 0; argv[argc] != NULL; ++argc) {
    if (argc > 0) printf (\", \");
    printf (\"\\\"%%s\\\"\", argv[argc]);
  }
  printf (\"]\\n\");
}

/* The test0 function prints its parameters to stdout. */
";

  let test0, tests =
    match test_functions with
    | [] -> assert false
    | test0 :: tests -> test0, tests in

  let () =
    let (name, style, _, _, _, _, _) = test0 in
    generate_prototype ~extern:false ~semicolon:false ~newline:true
      ~handle:"g" ~prefix:"guestfs__" name style;
    pr "{\n";
    List.iter (
      function
      | Pathname n
      | Device n | Dev_or_Path n
      | String n
      | FileIn n
      | FileOut n -> pr "  printf (\"%%s\\n\", %s);\n" n
      | OptString n -> pr "  printf (\"%%s\\n\", %s ? %s : \"null\");\n" n n
      | StringList n | DeviceList n -> pr "  print_strings (%s);\n" n
      | Bool n -> pr "  printf (\"%%s\\n\", %s ? \"true\" : \"false\");\n" n
      | Int n -> pr "  printf (\"%%d\\n\", %s);\n" n
      | Int64 n -> pr "  printf (\"%%\" PRIi64 \"\\n\", %s);\n" n
    ) (snd style);
    pr "  /* Java changes stdout line buffering so we need this: */\n";
    pr "  fflush (stdout);\n";
    pr "  return 0;\n";
    pr "}\n";
    pr "\n" in

  List.iter (
    fun (name, style, _, _, _, _, _) ->
      if String.sub name (String.length name - 3) 3 <> "err" then (
        pr "/* Test normal return. */\n";
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs__" name style;
        pr "{\n";
        (match fst style with
         | RErr ->
             pr "  return 0;\n"
         | RInt _ ->
             pr "  int r;\n";
             pr "  sscanf (val, \"%%d\", &r);\n";
             pr "  return r;\n"
         | RInt64 _ ->
             pr "  int64_t r;\n";
             pr "  sscanf (val, \"%%\" SCNi64, &r);\n";
             pr "  return r;\n"
         | RBool _ ->
             pr "  return STREQ (val, \"true\");\n"
         | RConstString _
         | RConstOptString _ ->
             (* Can't return the input string here.  Return a static
              * string so we ensure we get a segfault if the caller
              * tries to free it.
              *)
             pr "  return \"static string\";\n"
         | RString _ ->
             pr "  return strdup (val);\n"
         | RStringList _ ->
             pr "  char **strs;\n";
             pr "  int n, i;\n";
             pr "  sscanf (val, \"%%d\", &n);\n";
             pr "  strs = safe_malloc (g, (n+1) * sizeof (char *));\n";
             pr "  for (i = 0; i < n; ++i) {\n";
             pr "    strs[i] = safe_malloc (g, 16);\n";
             pr "    snprintf (strs[i], 16, \"%%d\", i);\n";
             pr "  }\n";
             pr "  strs[n] = NULL;\n";
             pr "  return strs;\n"
         | RStruct (_, typ) ->
             pr "  struct guestfs_%s *r;\n" typ;
             pr "  r = safe_calloc (g, sizeof *r, 1);\n";
             pr "  return r;\n"
         | RStructList (_, typ) ->
             pr "  struct guestfs_%s_list *r;\n" typ;
             pr "  r = safe_calloc (g, sizeof *r, 1);\n";
             pr "  sscanf (val, \"%%d\", &r->len);\n";
             pr "  r->val = safe_calloc (g, r->len, sizeof *r->val);\n";
             pr "  return r;\n"
         | RHashtable _ ->
             pr "  char **strs;\n";
             pr "  int n, i;\n";
             pr "  sscanf (val, \"%%d\", &n);\n";
             pr "  strs = safe_malloc (g, (n*2+1) * sizeof (*strs));\n";
             pr "  for (i = 0; i < n; ++i) {\n";
             pr "    strs[i*2] = safe_malloc (g, 16);\n";
             pr "    strs[i*2+1] = safe_malloc (g, 16);\n";
             pr "    snprintf (strs[i*2], 16, \"%%d\", i);\n";
             pr "    snprintf (strs[i*2+1], 16, \"%%d\", i);\n";
             pr "  }\n";
             pr "  strs[n*2] = NULL;\n";
             pr "  return strs;\n"
         | RBufferOut _ ->
             pr "  return strdup (val);\n"
        );
        pr "}\n";
        pr "\n"
      ) else (
        pr "/* Test error return. */\n";
        generate_prototype ~extern:false ~semicolon:false ~newline:true
          ~handle:"g" ~prefix:"guestfs__" name style;
        pr "{\n";
        pr "  error (g, \"error\");\n";
        (match fst style with
         | RErr | RInt _ | RInt64 _ | RBool _ ->
             pr "  return -1;\n"
         | RConstString _ | RConstOptString _
         | RString _ | RStringList _ | RStruct _
         | RStructList _
         | RHashtable _
         | RBufferOut _ ->
             pr "  return NULL;\n"
        );
        pr "}\n";
        pr "\n"
      )
  ) tests

and generate_ocaml_bindtests () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
let () =
  let g = Guestfs.create () in
";

  let mkargs args =
    String.concat " " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "None"
        | CallOptString (Some s) -> sprintf "(Some \"%s\")" s
        | CallStringList xs ->
            "[|" ^ String.concat ";" (List.map (sprintf "\"%s\"") xs) ^ "|]"
        | CallInt i when i >= 0 -> string_of_int i
        | CallInt i (* when i < 0 *) -> "(" ^ string_of_int i ^ ")"
        | CallInt64 i when i >= 0L -> Int64.to_string i ^ "L"
        | CallInt64 i (* when i < 0L *) -> "(" ^ Int64.to_string i ^ "L)"
        | CallBool b -> string_of_bool b
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "  Guestfs.%s g %s;\n" f (mkargs args)
  );

  pr "print_endline \"EOF\"\n"

and generate_perl_bindtests () =
  pr "#!/usr/bin/perl -w\n";
  generate_header HashStyle GPLv2plus;

  pr "\
use strict;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
";

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "undef"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> if b then "1" else "0"
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "$g->%s (%s);\n" f (mkargs args)
  );

  pr "print \"EOF\\n\"\n"

and generate_python_bindtests () =
  generate_header HashStyle GPLv2plus;

  pr "\
import guestfs

g = guestfs.GuestFS ()
";

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "None"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> if b then "1" else "0"
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "g.%s (%s)\n" f (mkargs args)
  );

  pr "print \"EOF\"\n"

and generate_ruby_bindtests () =
  generate_header HashStyle GPLv2plus;

  pr "\
require 'guestfs'

g = Guestfs::create()
";

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "nil"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> string_of_bool b
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "g.%s(%s)\n" f (mkargs args)
  );

  pr "print \"EOF\\n\"\n"

and generate_java_bindtests () =
  generate_header CStyle GPLv2plus;

  pr "\
import com.redhat.et.libguestfs.*;

public class Bindtests {
    public static void main (String[] argv)
    {
        try {
            GuestFS g = new GuestFS ();
";

  let mkargs args =
    String.concat ", " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "null"
        | CallOptString (Some s) -> sprintf "\"%s\"" s
        | CallStringList xs ->
            "new String[]{" ^
              String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "}"
        | CallInt i -> string_of_int i
        | CallInt64 i -> Int64.to_string i
        | CallBool b -> string_of_bool b
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "            g.%s (%s);\n" f (mkargs args)
  );

  pr "
            System.out.println (\"EOF\");
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
"

and generate_haskell_bindtests () =
  generate_header HaskellStyle GPLv2plus;

  pr "\
module Bindtests where
import qualified Guestfs

main = do
  g <- Guestfs.create
";

  let mkargs args =
    String.concat " " (
      List.map (
        function
        | CallString s -> "\"" ^ s ^ "\""
        | CallOptString None -> "Nothing"
        | CallOptString (Some s) -> sprintf "(Just \"%s\")" s
        | CallStringList xs ->
            "[" ^ String.concat "," (List.map (sprintf "\"%s\"") xs) ^ "]"
        | CallInt i when i < 0 -> "(" ^ string_of_int i ^ ")"
        | CallInt i -> string_of_int i
        | CallInt64 i when i < 0L -> "(" ^ Int64.to_string i ^ ")"
        | CallInt64 i -> Int64.to_string i
        | CallBool true -> "True"
        | CallBool false -> "False"
      ) args
    )
  in

  generate_lang_bindtests (
    fun f args -> pr "  Guestfs.%s g %s\n" f (mkargs args)
  );

  pr "  putStrLn \"EOF\"\n"

(* Language-independent bindings tests - we do it this way to
 * ensure there is parity in testing bindings across all languages.
 *)
and generate_lang_bindtests call =
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString None;
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString ""; CallOptString (Some "def");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString ""; CallOptString (Some "");
                CallStringList []; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"; "2"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool true;
                CallInt 0; CallInt64 0L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt (-1); CallInt64 (-1L); CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt (-2); CallInt64 (-2L); CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 1; CallInt64 1L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 2; CallInt64 2L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 4095; CallInt64 4095L; CallString "123"; CallString "456"];
  call "test0" [CallString "abc"; CallOptString (Some "def");
                CallStringList ["1"]; CallBool false;
                CallInt 0; CallInt64 0L; CallString ""; CallString ""]

(* XXX Add here tests of the return and error functions. *)

(* Code to generator bindings for virt-inspector.  Currently only
 * implemented for OCaml code (for virt-p2v 2.0).
 *)
let rng_input = "inspector/virt-inspector.rng"

(* Read the input file and parse it into internal structures.  This is
 * by no means a complete RELAX NG parser, but is just enough to be
 * able to parse the specific input file.
 *)
type rng =
  | Element of string * rng list        (* <element name=name/> *)
  | Attribute of string * rng list        (* <attribute name=name/> *)
  | Interleave of rng list                (* <interleave/> *)
  | ZeroOrMore of rng                        (* <zeroOrMore/> *)
  | OneOrMore of rng                        (* <oneOrMore/> *)
  | Optional of rng                        (* <optional/> *)
  | Choice of string list                (* <choice><value/>*</choice> *)
  | Value of string                        (* <value>str</value> *)
  | Text                                (* <text/> *)

let rec string_of_rng = function
  | Element (name, xs) ->
      "Element (\"" ^ name ^ "\", (" ^ string_of_rng_list xs ^ "))"
  | Attribute (name, xs) ->
      "Attribute (\"" ^ name ^ "\", (" ^ string_of_rng_list xs ^ "))"
  | Interleave xs -> "Interleave (" ^ string_of_rng_list xs ^ ")"
  | ZeroOrMore rng -> "ZeroOrMore (" ^ string_of_rng rng ^ ")"
  | OneOrMore rng -> "OneOrMore (" ^ string_of_rng rng ^ ")"
  | Optional rng -> "Optional (" ^ string_of_rng rng ^ ")"
  | Choice values -> "Choice [" ^ String.concat ", " values ^ "]"
  | Value value -> "Value \"" ^ value ^ "\""
  | Text -> "Text"

and string_of_rng_list xs =
  String.concat ", " (List.map string_of_rng xs)

let rec parse_rng ?defines context = function
  | [] -> []
  | Xml.Element ("element", ["name", name], children) :: rest ->
      Element (name, parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("attribute", ["name", name], children) :: rest ->
      Attribute (name, parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("interleave", [], children) :: rest ->
      Interleave (parse_rng ?defines context children)
      :: parse_rng ?defines context rest
  | Xml.Element ("zeroOrMore", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> ZeroOrMore child :: parse_rng ?defines context rest
       | _ ->
           failwithf "%s: <zeroOrMore> contains more than one child element"
             context
      )
  | Xml.Element ("oneOrMore", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> OneOrMore child :: parse_rng ?defines context rest
       | _ ->
           failwithf "%s: <oneOrMore> contains more than one child element"
             context
      )
  | Xml.Element ("optional", [], [child]) :: rest ->
      let rng = parse_rng ?defines context [child] in
      (match rng with
       | [child] -> Optional child :: parse_rng ?defines context rest
       | _ ->
           failwithf "%s: <optional> contains more than one child element"
             context
      )
  | Xml.Element ("choice", [], children) :: rest ->
      let values = List.map (
        function Xml.Element ("value", [], [Xml.PCData value]) -> value
        | _ ->
            failwithf "%s: can't handle anything except <value> in <choice>"
              context
      ) children in
      Choice values
      :: parse_rng ?defines context rest
  | Xml.Element ("value", [], [Xml.PCData value]) :: rest ->
      Value value :: parse_rng ?defines context rest
  | Xml.Element ("text", [], []) :: rest ->
      Text :: parse_rng ?defines context rest
  | Xml.Element ("ref", ["name", name], []) :: rest ->
      (* Look up the reference.  Because of limitations in this parser,
       * we can't handle arbitrarily nested <ref> yet.  You can only
       * use <ref> from inside <start>.
       *)
      (match defines with
       | None ->
           failwithf "%s: contains <ref>, but no refs are defined yet" context
       | Some map ->
           let rng = StringMap.find name map in
           rng @ parse_rng ?defines context rest
      )
  | x :: _ ->
      failwithf "%s: can't handle '%s' in schema" context (Xml.to_string x)

let grammar =
  let xml = Xml.parse_file rng_input in
  match xml with
  | Xml.Element ("grammar", _,
                 Xml.Element ("start", _, gram) :: defines) ->
      (* The <define/> elements are referenced in the <start> section,
       * so build a map of those first.
       *)
      let defines = List.fold_left (
        fun map ->
          function Xml.Element ("define", ["name", name], defn) ->
            StringMap.add name defn map
          | _ ->
              failwithf "%s: expected <define name=name/>" rng_input
      ) StringMap.empty defines in
      let defines = StringMap.mapi parse_rng defines in

      (* Parse the <start> clause, passing the defines. *)
      parse_rng ~defines "<start>" gram
  | _ ->
      failwithf "%s: input is not <grammar><start/><define>*</grammar>"
        rng_input

let name_of_field = function
  | Element (name, _) | Attribute (name, _)
  | ZeroOrMore (Element (name, _))
  | OneOrMore (Element (name, _))
  | Optional (Element (name, _)) -> name
  | Optional (Attribute (name, _)) -> name
  | Text -> (* an unnamed field in an element *)
      "data"
  | rng ->
      failwithf "name_of_field failed at: %s" (string_of_rng rng)

(* At the moment this function only generates OCaml types.  However we
 * should parameterize it later so it can generate types/structs in a
 * variety of languages.
 *)
let generate_types xs =
  (* A simple type is one that can be printed out directly, eg.
   * "string option".  A complex type is one which has a name and has
   * to be defined via another toplevel definition, eg. a struct.
   *
   * generate_type generates code for either simple or complex types.
   * In the simple case, it returns the string ("string option").  In
   * the complex case, it returns the name ("mountpoint").  In the
   * complex case it has to print out the definition before returning,
   * so it should only be called when we are at the beginning of a
   * new line (BOL context).
   *)
  let rec generate_type = function
    | Text ->                                (* string *)
        "string", true
    | Choice values ->                        (* [`val1|`val2|...] *)
        "[" ^ String.concat "|" (List.map ((^)"`") values) ^ "]", true
    | ZeroOrMore rng ->                        (* <rng> list *)
        let t, is_simple = generate_type rng in
        t ^ " list (* 0 or more *)", is_simple
    | OneOrMore rng ->                        (* <rng> list *)
        let t, is_simple = generate_type rng in
        t ^ " list (* 1 or more *)", is_simple
                                        (* virt-inspector hack: bool *)
    | Optional (Attribute (name, [Value "1"])) ->
        "bool", true
    | Optional rng ->                        (* <rng> list *)
        let t, is_simple = generate_type rng in
        t ^ " option", is_simple
                                        (* type name = { fields ... } *)
    | Element (name, fields) when is_attrs_interleave fields ->
        generate_type_struct name (get_attrs_interleave fields)
    | Element (name, [field])                (* type name = field *)
    | Attribute (name, [field]) ->
        let t, is_simple = generate_type field in
        if is_simple then (t, true)
        else (
          pr "type %s = %s\n" name t;
          name, false
        )
    | Element (name, fields) ->              (* type name = { fields ... } *)
        generate_type_struct name fields
    | rng ->
        failwithf "generate_type failed at: %s" (string_of_rng rng)

  and is_attrs_interleave = function
    | [Interleave _] -> true
    | Attribute _ :: fields -> is_attrs_interleave fields
    | Optional (Attribute _) :: fields -> is_attrs_interleave fields
    | _ -> false

  and get_attrs_interleave = function
    | [Interleave fields] -> fields
    | ((Attribute _) as field) :: fields
    | ((Optional (Attribute _)) as field) :: fields ->
        field :: get_attrs_interleave fields
    | _ -> assert false

  and generate_types xs =
    List.iter (fun x -> ignore (generate_type x)) xs

  and generate_type_struct name fields =
    (* Calculate the types of the fields first.  We have to do this
     * before printing anything so we are still in BOL context.
     *)
    let types = List.map fst (List.map generate_type fields) in

    (* Special case of a struct containing just a string and another
     * field.  Turn it into an assoc list.
     *)
    match types with
    | ["string"; other] ->
        let fname1, fname2 =
          match fields with
          | [f1; f2] -> name_of_field f1, name_of_field f2
          | _ -> assert false in
        pr "type %s = string * %s (* %s -> %s *)\n" name other fname1 fname2;
        name, false

    | types ->
        pr "type %s = {\n" name;
        List.iter (
          fun (field, ftype) ->
            let fname = name_of_field field in
            pr "  %s_%s : %s;\n" name fname ftype
        ) (List.combine fields types);
        pr "}\n";
        (* Return the name of this type, and
         * false because it's not a simple type.
         *)
        name, false
  in

  generate_types xs

let generate_parsers xs =
  (* As for generate_type above, generate_parser makes a parser for
   * some type, and returns the name of the parser it has generated.
   * Because it (may) need to print something, it should always be
   * called in BOL context.
   *)
  let rec generate_parser = function
    | Text ->                                (* string *)
        "string_child_or_empty"
    | Choice values ->                        (* [`val1|`val2|...] *)
        sprintf "(fun x -> match Xml.pcdata (first_child x) with %s | str -> failwith (\"unexpected field value: \" ^ str))"
          (String.concat "|"
             (List.map (fun v -> sprintf "%S -> `%s" v v) values))
    | ZeroOrMore rng ->                        (* <rng> list *)
        let pa = generate_parser rng in
        sprintf "(fun x -> List.map %s (Xml.children x))" pa
    | OneOrMore rng ->                        (* <rng> list *)
        let pa = generate_parser rng in
        sprintf "(fun x -> List.map %s (Xml.children x))" pa
                                        (* virt-inspector hack: bool *)
    | Optional (Attribute (name, [Value "1"])) ->
        sprintf "(fun x -> try ignore (Xml.attrib x %S); true with Xml.No_attribute _ -> false)" name
    | Optional rng ->                        (* <rng> list *)
        let pa = generate_parser rng in
        sprintf "(function None -> None | Some x -> Some (%s x))" pa
                                        (* type name = { fields ... } *)
    | Element (name, fields) when is_attrs_interleave fields ->
        generate_parser_struct name (get_attrs_interleave fields)
    | Element (name, [field]) ->        (* type name = field *)
        let pa = generate_parser field in
        let parser_name = sprintf "parse_%s_%d" name (unique ()) in
        pr "let %s =\n" parser_name;
        pr "  %s\n" pa;
        pr "let parse_%s = %s\n" name parser_name;
        parser_name
    | Attribute (name, [field]) ->
        let pa = generate_parser field in
        let parser_name = sprintf "parse_%s_%d" name (unique ()) in
        pr "let %s =\n" parser_name;
        pr "  %s\n" pa;
        pr "let parse_%s = %s\n" name parser_name;
        parser_name
    | Element (name, fields) ->              (* type name = { fields ... } *)
        generate_parser_struct name ([], fields)
    | rng ->
        failwithf "generate_parser failed at: %s" (string_of_rng rng)

  and is_attrs_interleave = function
    | [Interleave _] -> true
    | Attribute _ :: fields -> is_attrs_interleave fields
    | Optional (Attribute _) :: fields -> is_attrs_interleave fields
    | _ -> false

  and get_attrs_interleave = function
    | [Interleave fields] -> [], fields
    | ((Attribute _) as field) :: fields
    | ((Optional (Attribute _)) as field) :: fields ->
        let attrs, interleaves = get_attrs_interleave fields in
        (field :: attrs), interleaves
    | _ -> assert false

  and generate_parsers xs =
    List.iter (fun x -> ignore (generate_parser x)) xs

  and generate_parser_struct name (attrs, interleaves) =
    (* Generate parsers for the fields first.  We have to do this
     * before printing anything so we are still in BOL context.
     *)
    let fields = attrs @ interleaves in
    let pas = List.map generate_parser fields in

    (* Generate an intermediate tuple from all the fields first.
     * If the type is just a string + another field, then we will
     * return this directly, otherwise it is turned into a record.
     *
     * RELAX NG note: This code treats <interleave> and plain lists of
     * fields the same.  In other words, it doesn't bother enforcing
     * any ordering of fields in the XML.
     *)
    pr "let parse_%s x =\n" name;
    pr "  let t = (\n    ";
    let comma = ref false in
    List.iter (
      fun x ->
        if !comma then pr ",\n    ";
        comma := true;
        match x with
        | Optional (Attribute (fname, [field])), pa ->
            pr "%s x" pa
        | Optional (Element (fname, [field])), pa ->
            pr "%s (optional_child %S x)" pa fname
        | Attribute (fname, [Text]), _ ->
            pr "attribute %S x" fname
        | (ZeroOrMore _ | OneOrMore _), pa ->
            pr "%s x" pa
        | Text, pa ->
            pr "%s x" pa
        | (field, pa) ->
            let fname = name_of_field field in
            pr "%s (child %S x)" pa fname
    ) (List.combine fields pas);
    pr "\n  ) in\n";

    (match fields with
     | [Element (_, [Text]) | Attribute (_, [Text]); _] ->
         pr "  t\n"

     | _ ->
         pr "  (Obj.magic t : %s)\n" name
(*
         List.iter (
           function
           | (Optional (Attribute (fname, [field])), pa) ->
               pr "  %s_%s =\n" name fname;
               pr "    %s x;\n" pa
           | (Optional (Element (fname, [field])), pa) ->
               pr "  %s_%s =\n" name fname;
               pr "    (let x = optional_child %S x in\n" fname;
               pr "     %s x);\n" pa
           | (field, pa) ->
               let fname = name_of_field field in
               pr "  %s_%s =\n" name fname;
               pr "    (let x = child %S x in\n" fname;
               pr "     %s x);\n" pa
         ) (List.combine fields pas);
         pr "}\n"
*)
    );
    sprintf "parse_%s" name
  in

  generate_parsers xs

(* Generate ocaml/guestfs_inspector.mli. *)
let generate_ocaml_inspector_mli () =
  generate_header ~extra_inputs:[rng_input] OCamlStyle LGPLv2plus;

  pr "\
(** This is an OCaml language binding to the external [virt-inspector]
    program.

    For more information, please read the man page [virt-inspector(1)].
*)

";

  generate_types grammar;
  pr "(** The nested information returned from the {!inspect} function. *)\n";
  pr "\n";

  pr "\
val inspect : ?connect:string -> ?xml:string -> string list -> operatingsystems
(** To inspect a libvirt domain called [name], pass a singleton
    list: [inspect [name]].  When using libvirt only, you may
    optionally pass a libvirt URI using [inspect ~connect:uri ...].

    To inspect a disk image or images, pass a list of the filenames
    of the disk images: [inspect filenames]

    This function inspects the given guest or disk images and
    returns a list of operating system(s) found and a large amount
    of information about them.  In the vast majority of cases,
    a virtual machine only contains a single operating system.

    If the optional [~xml] parameter is given, then this function
    skips running the external virt-inspector program and just
    parses the given XML directly (which is expected to be XML
    produced from a previous run of virt-inspector).  The list of
    names and connect URI are ignored in this case.

    This function can throw a wide variety of exceptions, for example
    if the external virt-inspector program cannot be found, or if
    it doesn't generate valid XML.
*)
"

(* Generate ocaml/guestfs_inspector.ml. *)
let generate_ocaml_inspector_ml () =
  generate_header ~extra_inputs:[rng_input] OCamlStyle LGPLv2plus;

  pr "open Unix\n";
  pr "\n";

  generate_types grammar;
  pr "\n";

  pr "\
(* Misc functions which are used by the parser code below. *)
let first_child = function
  | Xml.Element (_, _, c::_) -> c
  | Xml.Element (name, _, []) ->
      failwith (\"expected <\" ^ name ^ \"/> to have a child node\")
  | Xml.PCData str ->
      failwith (\"expected XML tag, but read PCDATA '\" ^ str ^ \"' instead\")

let string_child_or_empty = function
  | Xml.Element (_, _, [Xml.PCData s]) -> s
  | Xml.Element (_, _, []) -> \"\"
  | Xml.Element (x, _, _) ->
      failwith (\"expected XML tag with a single PCDATA child, but got \" ^
                x ^ \" instead\")
  | Xml.PCData str ->
      failwith (\"expected XML tag, but read PCDATA '\" ^ str ^ \"' instead\")

let optional_child name xml =
  let children = Xml.children xml in
  try
    Some (List.find (function
                     | Xml.Element (n, _, _) when n = name -> true
                     | _ -> false) children)
  with
    Not_found -> None

let child name xml =
  match optional_child name xml with
  | Some c -> c
  | None ->
      failwith (\"mandatory field <\" ^ name ^ \"/> missing in XML output\")

let attribute name xml =
  try Xml.attrib xml name
  with Xml.No_attribute _ ->
    failwith (\"mandatory attribute \" ^ name ^ \" missing in XML output\")

";

  generate_parsers grammar;
  pr "\n";

  pr "\
(* Run external virt-inspector, then use parser to parse the XML. *)
let inspect ?connect ?xml names =
  let xml =
    match xml with
    | None ->
        if names = [] then invalid_arg \"inspect: no names given\";
        let cmd = [ \"virt-inspector\"; \"--xml\" ] @
          (match connect with None -> [] | Some uri -> [ \"--connect\"; uri ]) @
          names in
        let cmd = List.map Filename.quote cmd in
        let cmd = String.concat \" \" cmd in
        let chan = open_process_in cmd in
        let xml = Xml.parse_in chan in
        (match close_process_in chan with
         | WEXITED 0 -> ()
         | WEXITED _ -> failwith \"external virt-inspector command failed\"
         | WSIGNALED i | WSTOPPED i ->
             failwith (\"external virt-inspector command died or stopped on sig \" ^
                       string_of_int i)
        );
        xml
    | Some doc ->
        Xml.parse_string doc in
  parse_operatingsystems xml
"

(* This is used to generate the src/MAX_PROC_NR file which
 * contains the maximum procedure number, a surrogate for the
 * ABI version number.  See src/Makefile.am for the details.
 *)
and generate_max_proc_nr () =
  let proc_nrs = List.map (
    fun (_, _, proc_nr, _, _, _, _) -> proc_nr
  ) daemon_functions in

  let max_proc_nr = List.fold_left max 0 proc_nrs in

  pr "%d\n" max_proc_nr

let output_to filename k =
  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  k ();
  close_out !chan;
  chan := Pervasives.stdout;

  (* Is the new file different from the current file? *)
  if Sys.file_exists filename && files_equal filename filename_new then
    unlink filename_new                 (* same, so skip it *)
  else (
    (* different, overwrite old one *)
    (try chmod filename 0o644 with Unix_error _ -> ());
    rename filename_new filename;
    chmod filename 0o444;
    printf "written %s\n%!" filename;
  )

let perror msg = function
  | Unix_error (err, _, _) ->
      eprintf "%s: %s\n" msg (error_message err)
  | exn ->
      eprintf "%s: %s\n" msg (Printexc.to_string exn)

(* Main program. *)
let () =
  let lock_fd =
    try openfile "HACKING" [O_RDWR] 0
    with
    | Unix_error (ENOENT, _, _) ->
        eprintf "\
You are probably running this from the wrong directory.
Run it from the top source directory using the command
  src/generator.ml
";
        exit 1
    | exn ->
        perror "open: HACKING" exn;
        exit 1 in

  (* Acquire a lock so parallel builds won't try to run the generator
   * twice at the same time.  Subsequent builds will wait for the first
   * one to finish.  Note the lock is released implicitly when the
   * program exits.
   *)
  (try lockf lock_fd F_LOCK 1
   with exn ->
     perror "lock: HACKING" exn;
     exit 1);

  check_functions ();

  output_to "src/guestfs_protocol.x" generate_xdr;
  output_to "src/guestfs-structs.h" generate_structs_h;
  output_to "src/guestfs-actions.h" generate_actions_h;
  output_to "src/guestfs-internal-actions.h" generate_internal_actions_h;
  output_to "src/guestfs-actions.c" generate_client_actions;
  output_to "src/guestfs-bindtests.c" generate_bindtests;
  output_to "src/guestfs-structs.pod" generate_structs_pod;
  output_to "src/guestfs-actions.pod" generate_actions_pod;
  output_to "src/guestfs-availability.pod" generate_availability_pod;
  output_to "src/MAX_PROC_NR" generate_max_proc_nr;
  output_to "daemon/actions.h" generate_daemon_actions_h;
  output_to "daemon/stubs.c" generate_daemon_actions;
  output_to "daemon/names.c" generate_daemon_names;
  output_to "daemon/optgroups.c" generate_daemon_optgroups_c;
  output_to "daemon/optgroups.h" generate_daemon_optgroups_h;
  output_to "capitests/tests.c" generate_tests;
  output_to "fish/cmds.c" generate_fish_cmds;
  output_to "fish/completion.c" generate_fish_completion;
  output_to "fish/guestfish-actions.pod" generate_fish_actions_pod;
  output_to "ocaml/guestfs.mli" generate_ocaml_mli;
  output_to "ocaml/guestfs.ml" generate_ocaml_ml;
  output_to "ocaml/guestfs_c_actions.c" generate_ocaml_c;
  output_to "ocaml/bindtests.ml" generate_ocaml_bindtests;
  output_to "ocaml/guestfs_inspector.mli" generate_ocaml_inspector_mli;
  output_to "ocaml/guestfs_inspector.ml" generate_ocaml_inspector_ml;
  output_to "perl/Guestfs.xs" generate_perl_xs;
  output_to "perl/lib/Sys/Guestfs.pm" generate_perl_pm;
  output_to "perl/bindtests.pl" generate_perl_bindtests;
  output_to "python/guestfs-py.c" generate_python_c;
  output_to "python/guestfs.py" generate_python_py;
  output_to "python/bindtests.py" generate_python_bindtests;
  output_to "ruby/ext/guestfs/_guestfs.c" generate_ruby_c;
  output_to "ruby/bindtests.rb" generate_ruby_bindtests;
  output_to "java/com/redhat/et/libguestfs/GuestFS.java" generate_java_java;

  List.iter (
    fun (typ, jtyp) ->
      let cols = cols_of_struct typ in
      let filename = sprintf "java/com/redhat/et/libguestfs/%s.java" jtyp in
      output_to filename (generate_java_struct jtyp cols);
  ) java_structs;

  output_to "java/Makefile.inc" generate_java_makefile_inc;
  output_to "java/com_redhat_et_libguestfs_GuestFS.c" generate_java_c;
  output_to "java/Bindtests.java" generate_java_bindtests;
  output_to "haskell/Guestfs.hs" generate_haskell_hs;
  output_to "haskell/Bindtests.hs" generate_haskell_bindtests;
  output_to "csharp/Libguestfs.cs" generate_csharp;

  (* Always generate this file last, and unconditionally.  It's used
   * by the Makefile to know when we must re-run the generator.
   *)
  let chan = open_out "src/stamp-generator" in
  fprintf chan "1\n";
  close_out chan;

  printf "generated %d lines of code\n" !lines
