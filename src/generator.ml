#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
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
 * this one to describe the interface (see the big table below), and
 * daemon/<somefile>.c to write the implementation.
 *
 * After editing this file, run it (./src/generator.ml) to regenerate
 * all the output files.
 *
 * IMPORTANT: This script should NOT print any warnings.  If it prints
 * warnings, you should treat them as errors.
 * [Need to add -warn-error to ocaml command line]
 *)

#load "unix.cma";;

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
     * Try to avoid using this.  In particular you cannot use this
     * for values returned from the daemon, because there is no
     * thread-safe way to return them in the C API.
     *)
  | RConstString of string
    (* "RString" and "RStringList" are caller-frees. *)
  | RString of string
  | RStringList of string
    (* Some limited tuples are possible: *)
  | RIntBool of string * string
    (* LVM PVs, VGs and LVs. *)
  | RPVList of string
  | RVGList of string
  | RLVList of string
    (* Stat buffers. *)
  | RStat of string
  | RStatVFS of string
    (* Key-value pairs of untyped strings.  Turns into a hashtable or
     * dictionary in languages which support it.  DON'T use this as a
     * general "bucket" for results.  Prefer a stronger typed return
     * value if one is available, or write a custom struct.  Don't use
     * this if the list could potentially be very long, since it is
     * inefficient.  Keys should be unique.  NULLs are not permitted.
     *)
  | RHashtable of string

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
  | OptString of string	(* const char *name, may be NULL *)
  | StringList of string(* list of strings (each string cannot be NULL) *)
  | Bool of string	(* boolean *)
  | Int of string	(* int (smallish ints, signed, <= 31 bits) *)
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

type flags =
  | ProtocolLimitWarning  (* display warning about protocol size limits *)
  | DangerWillRobinson	  (* flags particularly dangerous commands *)
  | FishAlias of string	  (* provide an alias for this cmd in guestfish *)
  | FishAction of string  (* call this function in guestfish *)
  | NotInFish		  (* do not export via guestfish *)

let protocol_limit_warning =
  "Because of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP."

let danger_will_robinson =
  "B<This command is dangerous.  Without careful use you
can easily destroy all your data>."

(* You can supply zero or as many tests as you want per API call.
 *
 * Note that the test environment has 3 block devices, of size 500MB,
 * 50MB and 10MB (respectively /dev/sda, /dev/sdb, /dev/sdc).
 * Note for partitioning purposes, the 500MB device has 63 cylinders.
 *
 * To be able to run the tests in a reasonable amount of time,
 * the virtual machine and block devices are reused between tests.
 * So don't try testing kill_subprocess :-x
 *
 * Between each test we umount-all and lvm-remove-all (except InitNone).
 *
 * Don't assume anything about the previous contents of the block
 * devices.  Use 'Init*' to create some initial scenarios.
 *)
type tests = (test_init * test) list
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
     * command to be the integer.
     *)
  | TestOutputInt of seq * int
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
     * command to be a structure.
     *)
  | TestOutputStruct of seq * test_field_compare list
    (* Run the command sequence and expect the final command (only)
     * to fail.
     *)
  | TestLastFail of seq

and test_field_compare =
  | CompareWithInt of string * int
  | CompareWithString of string * string
  | CompareFieldsIntEq of string * string
  | CompareFieldsStrEq of string * string

(* Some initial scenarios for testing. *)
and test_init =
    (* Do nothing, block devices could contain random stuff including
     * LVM PVs, and some filesystems might be mounted.  This is usually
     * a bad idea.
     *)
  | InitNone
    (* Block devices are empty and no filesystems are mounted. *)
  | InitEmpty
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

let non_daemon_functions = [
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
   "wait until the qemu subprocess launches",
   "\
Internally libguestfs is implemented by running a virtual machine
using L<qemu(1)>.

You should call this after C<guestfs_launch> to wait for the launch
to complete.");

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

This is equivalent to the qemu parameter C<-drive file=filename>.");

  ("add_cdrom", (RErr, [String "filename"]), -1, [FishAlias "cdrom"],
   [],
   "add a CD-ROM disk image to examine",
   "\
This function adds a virtual CD-ROM disk image to the guest.

This is equivalent to the qemu parameter C<-cdrom filename>.");

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

  ("set_path", (RErr, [String "path"]), -1, [FishAlias "path"],
   [],
   "set the search path",
   "\
Set the path that libguestfs searches for kernel and initrd.img.

The default is C<$libdir/guestfs> unless overridden by setting
C<LIBGUESTFS_PATH> environment variable.

The string C<path> is stashed in the libguestfs handle, so the caller
must make sure it remains valid for the lifetime of the handle.

Setting C<path> to C<NULL> restores the default path.");

  ("get_path", (RConstString "path", []), -1, [],
   [],
   "get the search path",
   "\
Return the current search path.

This is always non-NULL.  If it wasn't set already, then this will
return the default path.");

  ("set_autosync", (RErr, [Bool "autosync"]), -1, [FishAlias "autosync"],
   [],
   "set autosync mode",
   "\
If C<autosync> is true, this enables autosync.  Libguestfs will make a
best effort attempt to run C<guestfs_sync> when the handle is closed
(also if the program exits without closing handles).");

  ("get_autosync", (RBool "autosync", []), -1, [],
   [],
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
   [],
   "is ready to accept commands",
   "\
This returns true iff this handle is ready to accept commands
(in the C<READY> state).

For more information on states, see L<guestfs(3)>.");

  ("is_config", (RBool "config", []), -1, [],
   [],
   "is in configuration state",
   "\
This returns true iff this handle is being configured
(in the C<CONFIG> state).

For more information on states, see L<guestfs(3)>.");

  ("is_launching", (RBool "launching", []), -1, [],
   [],
   "is launching subprocess",
   "\
This returns true iff this handle is launching the subprocess
(in the C<LAUNCHING> state).

For more information on states, see L<guestfs(3)>.");

  ("is_busy", (RBool "busy", []), -1, [],
   [],
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

  ("set_busy", (RErr, []), -1, [NotInFish],
   [],
   "set state to busy",
   "\
This sets the state to C<BUSY>.  This is only used when implementing
actions using the low-level API.

For more information on states, see L<guestfs(3)>.");

  ("set_ready", (RErr, []), -1, [NotInFish],
   [],
   "set state to ready",
   "\
This sets the state to C<READY>.  This is only used when implementing
actions using the low-level API.

For more information on states, see L<guestfs(3)>.");

]

let daemon_functions = [
  ("mount", (RErr, [String "device"; String "mountpoint"]), 1, [],
   [InitEmpty, TestOutput (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
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
   [ InitEmpty, TestRun [["sync"]]],
   "sync disks, writes are flushed through to the disk image",
   "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
closing the handle.");

  ("touch", (RErr, [String "path"]), 3, [],
   [InitBasicFS, TestOutputTrue (
      [["touch"; "/new"];
       ["exists"; "/new"]])],
   "update file timestamps or create a new file",
   "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.");

  ("cat", (RString "content", [String "path"]), 4, [ProtocolLimitWarning],
   [InitBasicFS, TestOutput (
      [["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "list the contents of a file",
   "\
Return the contents of the file named C<path>.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_download>
function which has a more complex interface.");

  ("ll", (RString "listing", [String "directory"]), 5, [],
   [], (* XXX Tricky to test because it depends on the exact format
	* of the 'ls -l' command, which changes between F10 and F11.
	*)
   "list the files in a directory (long format)",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.");

  ("ls", (RStringList "listing", [String "directory"]), 6, [],
   [InitBasicFS, TestOutputList (
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
   [InitEmpty, TestOutputList (
      [["list_devices"]], ["/dev/sda"; "/dev/sdb"; "/dev/sdc"])],
   "list the block devices",
   "\
List all the block devices.

The full block device names are returned, eg. C</dev/sda>");

  ("list_partitions", (RStringList "partitions", []), 8, [],
   [InitBasicFS, TestOutputList (
      [["list_partitions"]], ["/dev/sda1"]);
    InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
       ["list_partitions"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "list the partitions",
   "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. C</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.");

  ("pvs", (RStringList "physvols", []), 9, [],
   [InitBasicFSonLVM, TestOutputList (
      [["pvs"]], ["/dev/sda1"]);
    InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
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

  ("vgs", (RStringList "volgroups", []), 10, [],
   [InitBasicFSonLVM, TestOutputList (
      [["vgs"]], ["VG"]);
    InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
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

  ("lvs", (RStringList "logvols", []), 11, [],
   [InitBasicFSonLVM, TestOutputList (
      [["lvs"]], ["/dev/VG/LV"]);
    InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
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

  ("pvs_full", (RPVList "physvols", []), 12, [],
   [], (* XXX how to test? *)
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields.");

  ("vgs_full", (RVGList "volgroups", []), 13, [],
   [], (* XXX how to test? *)
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields.");

  ("lvs_full", (RLVList "logvols", []), 14, [],
   [], (* XXX how to test? *)
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields.");

  ("read_lines", (RStringList "lines", [String "path"]), 15, [],
   [InitBasicFS, TestOutputList (
      [["write_file"; "/new"; "line1\r\nline2\nline3"; "0"];
       ["read_lines"; "/new"]], ["line1"; "line2"; "line3"]);
    InitBasicFS, TestOutputList (
      [["write_file"; "/new"; ""; "0"];
       ["read_lines"; "/new"]], [])],
   "read file as lines",
   "\
Return the contents of the file named C<path>.

The file contents are returned as a list of lines.  Trailing
C<LF> and C<CRLF> character sequences are I<not> returned.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of line).  For those you need to use the C<guestfs_read_file>
function which has a more complex interface.");

  ("aug_init", (RErr, [String "root"; Int "flags"]), 16, [],
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

  ("aug_close", (RErr, []), 26, [],
   [], (* XXX Augeas code needs tests. *)
   "close the current Augeas handle",
   "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions.");

  ("aug_defvar", (RInt "nrnodes", [String "name"; OptString "expr"]), 17, [],
   [], (* XXX Augeas code needs tests. *)
   "define an Augeas variable",
   "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset.");

  ("aug_defnode", (RIntBool ("nrnodes", "created"), [String "name"; String "expr"; String "val"]), 18, [],
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

  ("aug_get", (RString "val", [String "path"]), 19, [],
   [], (* XXX Augeas code needs tests. *)
   "look up the value of an Augeas path",
   "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned.");

  ("aug_set", (RErr, [String "path"; String "val"]), 20, [],
   [], (* XXX Augeas code needs tests. *)
   "set Augeas path to value",
   "\
Set the value associated with C<path> to C<value>.");

  ("aug_insert", (RErr, [String "path"; String "label"; Bool "before"]), 21, [],
   [], (* XXX Augeas code needs tests. *)
   "insert a sibling Augeas node",
   "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain C</>, C<*> or end
with a bracketed index C<[N]>.");

  ("aug_rm", (RInt "nrnodes", [String "path"]), 22, [],
   [], (* XXX Augeas code needs tests. *)
   "remove an Augeas path",
   "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed.");

  ("aug_mv", (RErr, [String "src"; String "dest"]), 23, [],
   [], (* XXX Augeas code needs tests. *)
   "move Augeas node",
   "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists.");

  ("aug_match", (RStringList "matches", [String "path"]), 24, [],
   [], (* XXX Augeas code needs tests. *)
   "return Augeas nodes which match path",
   "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree.");

  ("aug_save", (RErr, []), 25, [],
   [], (* XXX Augeas code needs tests. *)
   "write all pending Augeas changes to disk",
   "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved.");

  ("aug_load", (RErr, []), 27, [],
   [], (* XXX Augeas code needs tests. *)
   "load files into the tree",
   "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details.");

  ("aug_ls", (RStringList "matches", [String "path"]), 28, [],
   [], (* XXX Augeas code needs tests. *)
   "list Augeas nodes under a path",
   "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the resulting nodes into alphabetical order.");

  ("rm", (RErr, [String "path"]), 29, [],
   [InitBasicFS, TestRun
      [["touch"; "/new"];
       ["rm"; "/new"]];
    InitBasicFS, TestLastFail
      [["rm"; "/new"]];
    InitBasicFS, TestLastFail
      [["mkdir"; "/new"];
       ["rm"; "/new"]]],
   "remove a file",
   "\
Remove the single file C<path>.");

  ("rmdir", (RErr, [String "path"]), 30, [],
   [InitBasicFS, TestRun
      [["mkdir"; "/new"];
       ["rmdir"; "/new"]];
    InitBasicFS, TestLastFail
      [["rmdir"; "/new"]];
    InitBasicFS, TestLastFail
      [["touch"; "/new"];
       ["rmdir"; "/new"]]],
   "remove a directory",
   "\
Remove the single directory C<path>.");

  ("rm_rf", (RErr, [String "path"]), 31, [],
   [InitBasicFS, TestOutputFalse
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

  ("mkdir", (RErr, [String "path"]), 32, [],
   [InitBasicFS, TestOutputTrue
      [["mkdir"; "/new"];
       ["is_dir"; "/new"]];
    InitBasicFS, TestLastFail
      [["mkdir"; "/new/foo/bar"]]],
   "create a directory",
   "\
Create a directory named C<path>.");

  ("mkdir_p", (RErr, [String "path"]), 33, [],
   [InitBasicFS, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new/foo/bar"]];
    InitBasicFS, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new/foo"]];
    InitBasicFS, TestOutputTrue
      [["mkdir_p"; "/new/foo/bar"];
       ["is_dir"; "/new"]]],
   "create a directory and parents",
   "\
Create a directory named C<path>, creating any parent directories
as necessary.  This is like the C<mkdir -p> shell command.");

  ("chmod", (RErr, [Int "mode"; String "path"]), 34, [],
   [], (* XXX Need stat command to test *)
   "change file mode",
   "\
Change the mode (permissions) of C<path> to C<mode>.  Only
numeric modes are supported.");

  ("chown", (RErr, [Int "owner"; Int "group"; String "path"]), 35, [],
   [], (* XXX Need stat command to test *)
   "change file owner and group",
   "\
Change the file owner to C<owner> and group to C<group>.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy).");

  ("exists", (RBool "existsflag", [String "path"]), 36, [],
   [InitBasicFS, TestOutputTrue (
      [["touch"; "/new"];
       ["exists"; "/new"]]);
    InitBasicFS, TestOutputTrue (
      [["mkdir"; "/new"];
       ["exists"; "/new"]])],
   "test if file or directory exists",
   "\
This returns C<true> if and only if there is a file, directory
(or anything) with the given C<path> name.

See also C<guestfs_is_file>, C<guestfs_is_dir>, C<guestfs_stat>.");

  ("is_file", (RBool "fileflag", [String "path"]), 37, [],
   [InitBasicFS, TestOutputTrue (
      [["touch"; "/new"];
       ["is_file"; "/new"]]);
    InitBasicFS, TestOutputFalse (
      [["mkdir"; "/new"];
       ["is_file"; "/new"]])],
   "test if file exists",
   "\
This returns C<true> if and only if there is a file
with the given C<path> name.  Note that it returns false for
other objects like directories.

See also C<guestfs_stat>.");

  ("is_dir", (RBool "dirflag", [String "path"]), 38, [],
   [InitBasicFS, TestOutputFalse (
      [["touch"; "/new"];
       ["is_dir"; "/new"]]);
    InitBasicFS, TestOutputTrue (
      [["mkdir"; "/new"];
       ["is_dir"; "/new"]])],
   "test if file exists",
   "\
This returns C<true> if and only if there is a directory
with the given C<path> name.  Note that it returns false for
other objects like files.

See also C<guestfs_stat>.");

  ("pvcreate", (RErr, [String "device"]), 39, [],
   [InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["pvs"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "create an LVM physical volume",
   "\
This creates an LVM physical volume on the named C<device>,
where C<device> should usually be a partition name such
as C</dev/sda1>.");

  ("vgcreate", (RErr, [String "volgroup"; StringList "physvols"]), 40, [],
   [InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
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

  ("lvcreate", (RErr, [String "logvol"; String "volgroup"; Int "mbytes"]), 41, [],
   [InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ",10 ,20 ,"];
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

  ("mkfs", (RErr, [String "fstype"; String "device"]), 42, [],
   [InitEmpty, TestOutput (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents")],
   "make a filesystem",
   "\
This creates a filesystem on C<device> (usually a partition
of LVM logical volume).  The filesystem type is C<fstype>, for
example C<ext3>.");

  ("sfdisk", (RErr, [String "device";
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
the string C<,> (comma).");

  ("write_file", (RErr, [String "path"; String "content"; Int "size"]), 44, [ProtocolLimitWarning],
   [InitBasicFS, TestOutput (
      [["write_file"; "/new"; "new file contents"; "0"];
       ["cat"; "/new"]], "new file contents");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "\nnew file contents\n"; "0"];
       ["cat"; "/new"]], "\nnew file contents\n");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "\n\n"; "0"];
       ["cat"; "/new"]], "\n\n");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; ""; "0"];
       ["cat"; "/new"]], "");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "\n\n\n"; "0"];
       ["cat"; "/new"]], "\n\n\n");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "\n"; "0"];
       ["cat"; "/new"]], "\n")],
   "create a file",
   "\
This call creates a file called C<path>.  The contents of the
file is the string C<content> (which can contain any 8 bit data),
with length C<size>.

As a special case, if C<size> is C<0>
then the length is calculated using C<strlen> (so in this case
the content cannot contain embedded ASCII NULs).");

  ("umount", (RErr, [String "pathordevice"]), 45, [FishAlias "unmount"],
   [InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["mounts"]], ["/dev/sda1"]);
    InitEmpty, TestOutputList (
      [["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
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
   [InitBasicFS, TestOutputList (
      [["mounts"]], ["/dev/sda1"])],
   "show mounted filesystems",
   "\
This returns the list of currently mounted filesystems.  It returns
the list of devices (eg. C</dev/sda1>, C</dev/VG/LV>).

Some internal mounts are not shown.");

  ("umount_all", (RErr, []), 47, [FishAlias "unmount-all"],
   [InitBasicFS, TestOutputList (
      [["umount_all"];
       ["mounts"]], [])],
   "unmount all filesystems",
   "\
This unmounts all mounted filesystems.

Some internal mounts are not unmounted by this call.");

  ("lvm_remove_all", (RErr, []), 48, [DangerWillRobinson],
   [],
   "remove all LVM LVs, VGs and PVs",
   "\
This command removes all LVM logical volumes, volume groups
and physical volumes.");

  ("file", (RString "description", [String "path"]), 49, [],
   [InitBasicFS, TestOutput (
      [["touch"; "/new"];
       ["file"; "/new"]], "empty");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "some content\n"; "0"];
       ["file"; "/new"]], "ASCII text");
    InitBasicFS, TestLastFail (
      [["file"; "/nofile"]])],
   "determine file type",
   "\
This call uses the standard L<file(1)> command to determine
the type or contents of the file.  This also works on devices,
for example to find out whether a partition contains a filesystem.

The exact command which runs is C<file -bsL path>.  Note in
particular that the filename is not prepended to the output
(the C<-b> option).");

  ("command", (RString "output", [StringList "arguments"]), 50, [],
   [], (* XXX how to test? *)
   "run a command from the guest filesystem",
   "\
This call runs a command from the guest filesystem.  The
filesystem must be mounted, and must contain a compatible
operating system (ie. something Linux, with the same
or compatible processor architecture).

The single parameter is an argv-style list of arguments.
The first element is the name of the program to run.
Subsequent elements are parameters.  The list must be
non-empty (ie. must contain a program name).

The C<$PATH> environment variable will contain at least
C</usr/bin> and C</bin>.  If you require a program from
another location, you should provide the full path in the
first parameter.

Shared libraries and data files required by the program
must be available on filesystems which are mounted in the
correct places.  It is the caller's responsibility to ensure
all filesystems that are needed are mounted at the right
locations.");

  ("command_lines", (RStringList "lines", [StringList "arguments"]), 51, [],
   [], (* XXX how to test? *)
   "run a command, returning lines",
   "\
This is the same as C<guestfs_command>, but splits the
result into a list of lines.");

  ("stat", (RStat "statbuf", [String "path"]), 52, [],
   [InitBasicFS, TestOutputStruct (
      [["touch"; "/new"];
       ["stat"; "/new"]], [CompareWithInt ("size", 0)])],
   "get file information",
   "\
Returns file information for the given C<path>.

This is the same as the C<stat(2)> system call.");

  ("lstat", (RStat "statbuf", [String "path"]), 53, [],
   [InitBasicFS, TestOutputStruct (
      [["touch"; "/new"];
       ["lstat"; "/new"]], [CompareWithInt ("size", 0)])],
   "get file information for a symbolic link",
   "\
Returns file information for the given C<path>.

This is the same as C<guestfs_stat> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the C<lstat(2)> system call.");

  ("statvfs", (RStatVFS "statbuf", [String "path"]), 54, [],
   [InitBasicFS, TestOutputStruct (
      [["statvfs"; "/"]], [CompareWithInt ("bfree", 487702);
			   CompareWithInt ("blocks", 490020);
			   CompareWithInt ("bsize", 1024)])],
   "get file system statistics",
   "\
Returns file system statistics for any mounted file system.
C<path> should be a file or directory in the mounted file system
(typically it is the mount point itself, but it doesn't need to be).

This is the same as the C<statvfs(2)> system call.");

  ("tune2fs_l", (RHashtable "superblock", [String "device"]), 55, [],
   [], (* XXX test *)
   "get ext2/ext3 superblock details",
   "\
This returns the contents of the ext2 or ext3 filesystem superblock
on C<device>.

It is the same as running C<tune2fs -l device>.  See L<tune2fs(8)>
manpage for more details.  The list of fields returned isn't
clearly defined, and depends on both the version of C<tune2fs>
that libguestfs was built against, and the filesystem itself.");

  ("blockdev_setro", (RErr, [String "device"]), 56, [],
   [InitEmpty, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-only",
   "\
Sets the block device named C<device> to read-only.

This uses the L<blockdev(8)> command.");

  ("blockdev_setrw", (RErr, [String "device"]), 57, [],
   [InitEmpty, TestOutputFalse (
      [["blockdev_setrw"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-write",
   "\
Sets the block device named C<device> to read-write.

This uses the L<blockdev(8)> command.");

  ("blockdev_getro", (RBool "ro", [String "device"]), 58, [],
   [InitEmpty, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "is block device set to read-only",
   "\
Returns a boolean indicating if the block device is read-only
(true if read-only, false if not).

This uses the L<blockdev(8)> command.");

  ("blockdev_getss", (RInt "sectorsize", [String "device"]), 59, [],
   [InitEmpty, TestOutputInt (
      [["blockdev_getss"; "/dev/sda"]], 512)],
   "get sectorsize of block device",
   "\
This returns the size of sectors on a block device.
Usually 512, but can be larger for modern devices.

(Note, this is not the size in sectors, use C<guestfs_blockdev_getsz>
for that).

This uses the L<blockdev(8)> command.");

  ("blockdev_getbsz", (RInt "blocksize", [String "device"]), 60, [],
   [InitEmpty, TestOutputInt (
      [["blockdev_getbsz"; "/dev/sda"]], 4096)],
   "get blocksize of block device",
   "\
This returns the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_setbsz", (RErr, [String "device"; Int "blocksize"]), 61, [],
   [], (* XXX test *)
   "set blocksize of block device",
   "\
This sets the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_getsz", (RInt64 "sizeinsectors", [String "device"]), 62, [],
   [InitEmpty, TestOutputInt (
      [["blockdev_getsz"; "/dev/sda"]], 1024000)],
   "get total size of device in 512-byte sectors",
   "\
This returns the size of the device in units of 512-byte sectors
(even if the sectorsize isn't 512 bytes ... weird).

See also C<guestfs_blockdev_getss> for the real sector size of
the device, and C<guestfs_blockdev_getsize64> for the more
useful I<size in bytes>.

This uses the L<blockdev(8)> command.");

  ("blockdev_getsize64", (RInt64 "sizeinbytes", [String "device"]), 63, [],
   [InitEmpty, TestOutputInt (
      [["blockdev_getsize64"; "/dev/sda"]], 524288000)],
   "get total size of device in bytes",
   "\
This returns the size of the device in bytes.

See also C<guestfs_blockdev_getsz>.

This uses the L<blockdev(8)> command.");

  ("blockdev_flushbufs", (RErr, [String "device"]), 64, [],
   [InitEmpty, TestRun
      [["blockdev_flushbufs"; "/dev/sda"]]],
   "flush device buffers",
   "\
This tells the kernel to flush internal buffers associated
with C<device>.

This uses the L<blockdev(8)> command.");

  ("blockdev_rereadpt", (RErr, [String "device"]), 65, [],
   [InitEmpty, TestRun
      [["blockdev_rereadpt"; "/dev/sda"]]],
   "reread partition table",
   "\
Reread the partition table on C<device>.

This uses the L<blockdev(8)> command.");

  ("upload", (RErr, [FileIn "filename"; String "remotefilename"]), 66, [],
   [InitBasicFS, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
    [["upload"; "COPYING.LIB"; "/COPYING.LIB"];
     ["checksum"; "md5"; "/COPYING.LIB"]], "e3eda01d9815f8d24aae2dbd89b68b06")],
   "upload a file from the local machine",
   "\
Upload local file C<filename> to C<remotefilename> on the
filesystem.

C<filename> can also be a named pipe.

See also C<guestfs_download>.");

  ("download", (RErr, [String "remotefilename"; FileOut "filename"]), 67, [],
   [InitBasicFS, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
    [["upload"; "COPYING.LIB"; "/COPYING.LIB"];
     ["download"; "/COPYING.LIB"; "testdownload.tmp"];
     ["upload"; "testdownload.tmp"; "/upload"];
     ["checksum"; "md5"; "/upload"]], "e3eda01d9815f8d24aae2dbd89b68b06")],
   "download a file to the local machine",
   "\
Download file C<remotefilename> and save it as C<filename>
on the local machine.

C<filename> can also be a named pipe.

See also C<guestfs_upload>, C<guestfs_cat>.");

  ("checksum", (RString "checksum", [String "csumtype"; String "path"]), 68, [],
   [InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "crc"; "/new"]], "935282863");
    InitBasicFS, TestLastFail (
      [["checksum"; "crc"; "/new"]]);
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "md5"; "/new"]], "d8e8fca2dc0f896fd7cb4cb0031ba249");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "sha1"; "/new"]], "4e1243bd22c66e76c2ba9eddc1f91394e57f9f83");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "sha224"; "/new"]], "52f1bf093f4b7588726035c176c0cdb4376cfea53819f1395ac9e6ec");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "sha256"; "/new"]], "f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "sha384"; "/new"]], "109bb6b5b6d5547c1ce03c7a8bd7d8f80c1cb0957f50c4f7fda04692079917e4f9cad52b878f3d8234e1a170b154b72d");
    InitBasicFS, TestOutput (
      [["write_file"; "/new"; "test\n"; "0"];
       ["checksum"; "sha512"; "/new"]], "0e3e75234abc68f4378a86b3f4b32a198ba301845b0cd6e50106e874345700cc6663a86c1ea125dc5e92be17c98f9a0f85ca9d5f595db2012f7cc3571945c123")],
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
   [InitBasicFS, TestOutput (
      [["tar_in"; "images/helloworld.tar"; "/"];
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
   [InitBasicFS, TestOutput (
      [["tgz_in"; "images/helloworld.tar.gz"; "/"];
       ["cat"; "/hello"]], "hello\n")],
   "unpack compressed tarball to directory",
   "\
This command uploads and unpacks local file C<tarball> (a
I<gzip compressed> tar file) into C<directory>.

To upload an uncompressed tarball, use C<guestfs_tar_in>.");

  ("tgz_out", (RErr, [String "directory"; FileOut "tarball"]), 72, [],
   [],
   "pack directory into compressed tarball",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarball>.

To download an uncompressed tarball, use C<guestfs_tar_out>.");

]

let all_functions = non_daemon_functions @ daemon_functions

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let all_functions_sorted =
  List.sort (fun (n1,_,_,_,_,_,_) (n2,_,_,_,_,_,_) ->
	       compare n1 n2) all_functions

(* Column names and types from LVM PVs/VGs/LVs. *)
let pv_cols = [
  "pv_name", `String;
  "pv_uuid", `UUID;
  "pv_fmt", `String;
  "pv_size", `Bytes;
  "dev_size", `Bytes;
  "pv_free", `Bytes;
  "pv_used", `Bytes;
  "pv_attr", `String (* XXX *);
  "pv_pe_count", `Int;
  "pv_pe_alloc_count", `Int;
  "pv_tags", `String;
  "pe_start", `Bytes;
  "pv_mda_count", `Int;
  "pv_mda_free", `Bytes;
(* Not in Fedora 10:
  "pv_mda_size", `Bytes;
*)
]
let vg_cols = [
  "vg_name", `String;
  "vg_uuid", `UUID;
  "vg_fmt", `String;
  "vg_attr", `String (* XXX *);
  "vg_size", `Bytes;
  "vg_free", `Bytes;
  "vg_sysid", `String;
  "vg_extent_size", `Bytes;
  "vg_extent_count", `Int;
  "vg_free_count", `Int;
  "max_lv", `Int;
  "max_pv", `Int;
  "pv_count", `Int;
  "lv_count", `Int;
  "snap_count", `Int;
  "vg_seqno", `Int;
  "vg_tags", `String;
  "vg_mda_count", `Int;
  "vg_mda_free", `Bytes;
(* Not in Fedora 10:
  "vg_mda_size", `Bytes;
*)
]
let lv_cols = [
  "lv_name", `String;
  "lv_uuid", `UUID;
  "lv_attr", `String (* XXX *);
  "lv_major", `Int;
  "lv_minor", `Int;
  "lv_kernel_major", `Int;
  "lv_kernel_minor", `Int;
  "lv_size", `Bytes;
  "seg_count", `Int;
  "origin", `String;
  "snap_percent", `OptPercent;
  "copy_percent", `OptPercent;
  "move_pv", `String;
  "lv_tags", `String;
  "mirror_log", `String;
  "modules", `String;
]

(* Column names and types from stat structures.
 * NB. Can't use things like 'st_atime' because glibc header files
 * define some of these as macros.  Ugh.
 *)
let stat_cols = [
  "dev", `Int;
  "ino", `Int;
  "mode", `Int;
  "nlink", `Int;
  "uid", `Int;
  "gid", `Int;
  "rdev", `Int;
  "size", `Int;
  "blksize", `Int;
  "blocks", `Int;
  "atime", `Int;
  "mtime", `Int;
  "ctime", `Int;
]
let statvfs_cols = [
  "bsize", `Int;
  "frsize", `Int;
  "blocks", `Int;
  "bfree", `Int;
  "bavail", `Int;
  "files", `Int;
  "ffree", `Int;
  "favail", `Int;
  "fsid", `Int;
  "flag", `Int;
  "namemax", `Int;
]

(* Useful functions.
 * Note we don't want to use any external OCaml libraries which
 * makes this a bit harder than it should be.
 *)
let failwithf fs = ksprintf failwith fs

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

let name_of_argt = function
  | String n | OptString n | StringList n | Bool n | Int n
  | FileIn n | FileOut n -> n

let seq_of_test = function
  | TestRun s | TestOutput (s, _) | TestOutputList (s, _)
  | TestOutputInt (s, _) | TestOutputTrue s | TestOutputFalse s
  | TestOutputLength (s, _) | TestOutputStruct (s, _)
  | TestLastFail s -> s

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
      if contains_uppercase name then
	failwithf "function name %s should not contain uppercase chars" name;
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
	  failwithf "%s has a param/ret called 'value', which causes conflicts in the OCaml bindings, use something like 'val' or a more descriptive name" n;
	if n = "argv" || n = "args" then
	  failwithf "%s has a param/ret called 'argv' or 'args', which will cause some conflicts in the generated code" n
      in

      (match fst style with
       | RErr -> ()
       | RInt n | RInt64 n | RBool n | RConstString n | RString n
       | RStringList n | RPVList n | RVGList n | RLVList n
       | RStat n | RStatVFS n
       | RHashtable n ->
	   check_arg_ret_name n
       | RIntBool (n,m) ->
	   check_arg_ret_name n;
	   check_arg_ret_name m
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
	    fun (_, test) ->
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
let chan = ref stdout
let pr fs = ksprintf (output_string !chan) fs

(* Generate a header block in a number of standard styles. *)
type comment_style = CStyle | HashStyle | OCamlStyle
type license = GPLv2 | LGPLv2

let generate_header comment license =
  let c = match comment with
    | CStyle ->     pr "/* "; " *"
    | HashStyle ->  pr "# ";  "#"
    | OCamlStyle -> pr "(* "; " *" in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED BY 'src/generator.ml'.\n" c;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) 2009 Red Hat Inc.\n" c;
  pr "%s\n" c;
  (match license with
   | GPLv2 ->
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

   | LGPLv2 ->
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
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
  );
  pr "\n"

(* Start of main code generation functions below this line. *)

(* Generate the pod documentation for the C API. *)
let rec generate_actions_pod () =
  List.iter (
    fun (shortname, style, _, flags, _, _, longdesc) ->
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
       | RString _ ->
	   pr "This function returns a string, or NULL on error.
I<The caller must free the returned string after use>.\n\n"
       | RStringList _ ->
	   pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
       | RIntBool _ ->
	   pr "This function returns a C<struct guestfs_int_bool *>,
or NULL if there was an error.
I<The caller must call C<guestfs_free_int_bool> after use>.\n\n"
       | RPVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_pv_list *>
(see E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<guestfs_free_lvm_pv_list> after use>.\n\n"
       | RVGList _ ->
	   pr "This function returns a C<struct guestfs_lvm_vg_list *>
(see E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<guestfs_free_lvm_vg_list> after use>.\n\n"
       | RLVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_lv_list *>
(see E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<guestfs_free_lvm_lv_list> after use>.\n\n"
       | RStat _ ->
	   pr "This function returns a C<struct guestfs_stat *>
(see L<stat(2)> and E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<free> after use>.\n\n"
       | RStatVFS _ ->
	   pr "This function returns a C<struct guestfs_statvfs *>
(see L<statvfs(2)> and E<lt>guestfs-structs.hE<gt>),
or NULL if there was an error.
I<The caller must call C<free> after use>.\n\n"
       | RHashtable _ ->
	   pr "This function returns a NULL-terminated array of
strings, or NULL if there was an error.
The array of strings will always have length C<2n+1>, where
C<n> keys and values alternate, followed by the trailing NULL entry.
I<The caller must free the strings and the array after use>.\n\n"
      );
      if List.mem ProtocolLimitWarning flags then
	pr "%s\n\n" protocol_limit_warning;
      if List.mem DangerWillRobinson flags then
	pr "%s\n\n" danger_will_robinson;
  ) all_functions_sorted

and generate_structs_pod () =
  (* LVM structs documentation. *)
  List.iter (
    fun (typ, cols) ->
      pr "=head2 guestfs_lvm_%s\n" typ;
      pr "\n";
      pr " struct guestfs_lvm_%s {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  char *%s;\n" name
	| name, `UUID ->
	    pr "  /* The next field is NOT nul-terminated, be careful when printing it: */\n";
	    pr "  char %s[32];\n" name
	| name, `Bytes -> pr "  uint64_t %s;\n" name
	| name, `Int -> pr "  int64_t %s;\n" name
	| name, `OptPercent ->
	    pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
	    pr "  float %s;\n" name
      ) cols;
      pr " \n";
      pr " struct guestfs_lvm_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_lvm_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr " \n";
      pr " void guestfs_free_lvm_%s_list (struct guestfs_free_lvm_%s_list *);\n"
	typ typ;
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.
 *
 * We have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
and generate_xdr () =
  generate_header CStyle LGPLv2;

  (* This has to be defined to get around a limitation in Sun's rpcgen. *)
  pr "typedef string str<>;\n";
  pr "\n";

  (* LVM internal structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_int_%s {\n" typ;
	List.iter (function
		   | name, `String -> pr "  string %s<>;\n" name
		   | name, `UUID -> pr "  opaque %s[32];\n" name
		   | name, `Bytes -> pr "  hyper %s;\n" name
		   | name, `Int -> pr "  hyper %s;\n" name
		   | name, `OptPercent -> pr "  float %s;\n" name
		  ) cols;
	pr "};\n";
	pr "\n";
	pr "typedef struct guestfs_lvm_int_%s guestfs_lvm_int_%s_list<>;\n" typ typ;
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* Stat internal structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_int_%s {\n" typ;
	List.iter (function
		   | name, `Int -> pr "  hyper %s;\n" name
		  ) cols;
	pr "};\n";
	pr "\n";
  ) ["stat", stat_cols; "statvfs", statvfs_cols];

  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (match snd style with
       | [] -> ()
       | args ->
	   pr "struct %s_args {\n" name;
	   List.iter (
	     function
	     | String n -> pr "  string %s<>;\n" n
	     | OptString n -> pr "  str *%s;\n" n
	     | StringList n -> pr "  str %s<>;\n" n
	     | Bool n -> pr "  bool %s;\n" n
	     | Int n -> pr "  int %s;\n" n
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
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RString n ->
	   pr "struct %s_ret {\n" name;
	   pr "  string %s<>;\n" n;
	   pr "};\n\n"
       | RStringList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  str %s<>;\n" n;
	   pr "};\n\n"
       | RIntBool (n,m) ->
	   pr "struct %s_ret {\n" name;
	   pr "  int %s;\n" n;
	   pr "  bool %s;\n" m;
	   pr "};\n\n"
       | RPVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_pv_list %s;\n" n;
	   pr "};\n\n"
       | RVGList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_vg_list %s;\n" n;
	   pr "};\n\n"
       | RLVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_lv_list %s;\n" n;
	   pr "};\n\n"
       | RStat n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_int_stat %s;\n" n;
	   pr "};\n\n"
       | RStatVFS n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_int_statvfs %s;\n" n;
	   pr "};\n\n"
       | RHashtable n ->
	   pr "struct %s_ret {\n" name;
	   pr "  str %s<>;\n" n;
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
  generate_header CStyle LGPLv2;

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

  (* guestfs_int_bool structure. *)
  pr "struct guestfs_int_bool {\n";
  pr "  int32_t i;\n";
  pr "  int32_t b;\n";
  pr "};\n";
  pr "\n";

  (* LVM public structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_%s {\n" typ;
	List.iter (
	  function
	  | name, `String -> pr "  char *%s;\n" name
	  | name, `UUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
	  | name, `Bytes -> pr "  uint64_t %s;\n" name
	  | name, `Int -> pr "  int64_t %s;\n" name
	  | name, `OptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
	) cols;
	pr "};\n";
	pr "\n";
	pr "struct guestfs_lvm_%s_list {\n" typ;
	pr "  uint32_t len;\n";
	pr "  struct guestfs_lvm_%s *val;\n" typ;
	pr "};\n";
	pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* Stat structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_%s {\n" typ;
	List.iter (
	  function
	  | name, `Int -> pr "  int64_t %s;\n" name
	) cols;
	pr "};\n";
	pr "\n"
  ) ["stat", stat_cols; "statvfs", statvfs_cols]

(* Generate the guestfs-actions.h file. *)
and generate_actions_h () =
  generate_header CStyle LGPLv2;
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"handle"
	name style
  ) all_functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2;

  pr "\
#include <stdio.h>
#include <stdlib.h>

#include \"guestfs.h\"
#include \"guestfs_protocol.h\"

#define error guestfs_error
#define perrorf guestfs_perrorf
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
#define safe_strdup guestfs_safe_strdup
#define safe_memdup guestfs_safe_memdup

/* Check the return message from a call for validity. */
static int
check_reply_header (guestfs_h *g,
                    const struct guestfs_message_header *hdr,
                    int proc_nr, int serial)
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
  if (!guestfs_is_ready (g)) {
    if (guestfs_is_config (g))
      error (g, \"%%s: call launch() before using this function\",
        caller);
    else if (guestfs_is_launching (g))
      error (g, \"%%s: call wait_ready() before using this function\",
        caller);
    else
      error (g, \"%%s called from the wrong state, %%d != READY\",
        caller, guestfs_get_state (g));
    return -1;
  }
  return 0;
}

";

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (* Generate the context struct which stores the high-level
       * state between callback functions.
       *)
      pr "struct %s_ctx {\n" shortname;
      pr "  /* This flag is set by the callbacks, so we know we've done\n";
      pr "   * the callbacks as expected, and in the right sequence.\n";
      pr "   * 0 = not called, 1 = send called,\n";
      pr "   * 1001 = reply called.\n";
      pr "   */\n";
      pr "  int cb_sequence;\n";
      pr "  struct guestfs_message_header hdr;\n";
      pr "  struct guestfs_message_error err;\n";
      (match fst style with
       | RErr -> ()
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RInt _ | RInt64 _
       | RBool _ | RString _ | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _
       | RStat _ | RStatVFS _
       | RHashtable _ ->
	   pr "  struct %s_ret ret;\n" name
      );
      pr "};\n";
      pr "\n";

      (* Generate the reply callback function. *)
      pr "static void %s_reply_cb (guestfs_h *g, void *data, XDR *xdr)\n" shortname;
      pr "{\n";
      pr "  guestfs_main_loop *ml = guestfs_get_main_loop (g);\n";
      pr "  struct %s_ctx *ctx = (struct %s_ctx *) data;\n" shortname shortname;
      pr "\n";
      pr "  ml->main_loop_quit (ml, g);\n";
      pr "\n";
      pr "  if (!xdr_guestfs_message_header (xdr, &ctx->hdr)) {\n";
      pr "    error (g, \"%%s: failed to parse reply header\", \"%s\");\n" name;
      pr "    return;\n";
      pr "  }\n";
      pr "  if (ctx->hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    if (!xdr_guestfs_message_error (xdr, &ctx->err)) {\n";
      pr "      error (g, \"%%s: failed to parse reply error\", \"%s\");\n"
	name;
      pr "      return;\n";
      pr "    }\n";
      pr "    goto done;\n";
      pr "  }\n";

      (match fst style with
       | RErr -> ()
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RInt _ | RInt64 _
       | RBool _ | RString _ | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _
       | RStat _ | RStatVFS _
       | RHashtable _ ->
	    pr "  if (!xdr_%s_ret (xdr, &ctx->ret)) {\n" name;
	    pr "    error (g, \"%%s: failed to parse reply\", \"%s\");\n" name;
	    pr "    return;\n";
	    pr "  }\n";
      );

      pr " done:\n";
      pr "  ctx->cb_sequence = 1001;\n";
      pr "}\n\n";

      (* Generate the action stub. *)
      generate_prototype ~extern:false ~semicolon:false ~newline:true
	~handle:"g" name style;

      let error_code =
	match fst style with
	| RErr | RInt _ | RInt64 _ | RBool _ -> "-1"
	| RConstString _ ->
	    failwithf "RConstString cannot be returned from a daemon function"
	| RString _ | RStringList _ | RIntBool _
	| RPVList _ | RVGList _ | RLVList _
	| RStat _ | RStatVFS _
	| RHashtable _ ->
	    "NULL" in

      pr "{\n";

      (match snd style with
       | [] -> ()
       | _ -> pr "  struct %s_args args;\n" name
      );

      pr "  struct %s_ctx ctx;\n" shortname;
      pr "  guestfs_main_loop *ml = guestfs_get_main_loop (g);\n";
      pr "  int serial;\n";
      pr "\n";
      pr "  if (check_state (g, \"%s\") == -1) return %s;\n" name error_code;
      pr "  guestfs_set_busy (g);\n";
      pr "\n";
      pr "  memset (&ctx, 0, sizeof ctx);\n";
      pr "\n";

      (* Send the main header and arguments. *)
      (match snd style with
       | [] ->
	   pr "  serial = guestfs__send_sync (g, GUESTFS_PROC_%s, NULL, NULL);\n"
	     (String.uppercase shortname)
       | args ->
	   List.iter (
	     function
	     | String n ->
		 pr "  args.%s = (char *) %s;\n" n n
	     | OptString n ->
		 pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
	     | StringList n ->
		 pr "  args.%s.%s_val = (char **) %s;\n" n n n;
		 pr "  for (args.%s.%s_len = 0; %s[args.%s.%s_len]; args.%s.%s_len++) ;\n" n n n n n n n;
	     | Bool n ->
		 pr "  args.%s = %s;\n" n n
	     | Int n ->
		 pr "  args.%s = %s;\n" n n
	     | FileIn _ | FileOut _ -> ()
	   ) args;
	   pr "  serial = guestfs__send_sync (g, GUESTFS_PROC_%s,\n"
	     (String.uppercase shortname);
	   pr "        (xdrproc_t) xdr_%s_args, (char *) &args);\n"
	     name;
      );
      pr "  if (serial == -1) {\n";
      pr "    guestfs_set_ready (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Send any additional files (FileIn) requested. *)
      let need_read_reply_label = ref false in
      List.iter (
	function
	| FileIn n ->
	    pr "  {\n";
	    pr "    int r;\n";
	    pr "\n";
	    pr "    r = guestfs__send_file_sync (g, %s);\n" n;
	    pr "    if (r == -1) {\n";
	    pr "      guestfs_set_ready (g);\n";
	    pr "      return %s;\n" error_code;
	    pr "    }\n";
	    pr "    if (r == -2) /* daemon cancelled */\n";
	    pr "      goto read_reply;\n";
	    need_read_reply_label := true;
	    pr "  }\n";
	    pr "\n";
	| _ -> ()
      ) (snd style);

      (* Wait for the reply from the remote end. *)
      if !need_read_reply_label then pr " read_reply:\n";
      pr "  guestfs__switch_to_receiving (g);\n";
      pr "  ctx.cb_sequence = 0;\n";
      pr "  guestfs_set_reply_callback (g, %s_reply_cb, &ctx);\n" shortname;
      pr "  (void) ml->main_loop_run (ml, g);\n";
      pr "  guestfs_set_reply_callback (g, NULL, NULL);\n";
      pr "  if (ctx.cb_sequence != 1001) {\n";
      pr "    error (g, \"%%s reply failed, see earlier error messages\", \"%s\");\n" name;
      pr "    guestfs_set_ready (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &ctx.hdr, GUESTFS_PROC_%s, serial) == -1) {\n"
	(String.uppercase shortname);
      pr "    guestfs_set_ready (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (ctx.hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    error (g, \"%%s\", ctx.err.error_message);\n";
      pr "    guestfs_set_ready (g);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (* Expecting to receive further files (FileOut)? *)
      List.iter (
	function
	| FileOut n ->
	    pr "  if (guestfs__receive_file_sync (g, %s) == -1) {\n" n;
	    pr "    guestfs_set_ready (g);\n";
	    pr "    return %s;\n" error_code;
	    pr "  }\n";
	    pr "\n";
	| _ -> ()
      ) (snd style);

      pr "  guestfs_set_ready (g);\n";

      (match fst style with
       | RErr -> pr "  return 0;\n"
       | RInt n | RInt64 n | RBool n ->
	   pr "  return ctx.ret.%s;\n" n
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RString n ->
	   pr "  return ctx.ret.%s; /* caller will free */\n" n
       | RStringList n | RHashtable n ->
	   pr "  /* caller will free this, but we need to add a NULL entry */\n";
	   pr "  ctx.ret.%s.%s_val =\n" n n;
	   pr "    safe_realloc (g, ctx.ret.%s.%s_val,\n" n n;
	   pr "                  sizeof (char *) * (ctx.ret.%s.%s_len + 1));\n"
	     n n;
	   pr "  ctx.ret.%s.%s_val[ctx.ret.%s.%s_len] = NULL;\n" n n n n;
	   pr "  return ctx.ret.%s.%s_val;\n" n n
       | RIntBool _ ->
	   pr "  /* caller with free this */\n";
	   pr "  return safe_memdup (g, &ctx.ret, sizeof (ctx.ret));\n"
       | RPVList n | RVGList n | RLVList n
       | RStat n | RStatVFS n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &ctx.ret.%s, sizeof (ctx.ret.%s));\n" n n
      );

      pr "}\n\n"
  ) daemon_functions

(* Generate daemon/actions.h. *)
and generate_daemon_actions_h () =
  generate_header CStyle GPLv2;

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
  generate_header CStyle GPLv2;

  pr "#define _GNU_SOURCE // for strchrnul\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <ctype.h>\n";
  pr "#include <rpc/types.h>\n";
  pr "#include <rpc/xdr.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
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
	| RConstString _ ->
	    failwithf "RConstString cannot be returned from a daemon function"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
	| RIntBool _ -> pr "  guestfs_%s_ret *r;\n" name; "NULL"
	| RPVList _ -> pr "  guestfs_lvm_int_pv_list *r;\n"; "NULL"
	| RVGList _ -> pr "  guestfs_lvm_int_vg_list *r;\n"; "NULL"
	| RLVList _ -> pr "  guestfs_lvm_int_lv_list *r;\n"; "NULL"
	| RStat _ -> pr "  guestfs_int_stat *r;\n"; "NULL"
	| RStatVFS _ -> pr "  guestfs_int_statvfs *r;\n"; "NULL" in

      (match snd style with
       | [] -> ()
       | args ->
	   pr "  struct guestfs_%s_args args;\n" name;
	   List.iter (
	     function
	     | String n
	     | OptString n -> pr "  const char *%s;\n" n
	     | StringList n -> pr "  char **%s;\n" n
	     | Bool n -> pr "  int %s;\n" n
	     | Int n -> pr "  int %s;\n" n
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
	   List.iter (
	     function
	     | String n -> pr "  %s = args.%s;\n" n n
	     | OptString n -> pr "  %s = args.%s ? *args.%s : NULL;\n" n n n
	     | StringList n ->
		 pr "  args.%s.%s_val = realloc (args.%s.%s_val, sizeof (char *) * (args.%s.%s_len+1));\n" n n n n n n;
		 pr "  args.%s.%s_val[args.%s.%s_len] = NULL;\n" n n n n;
		 pr "  %s = args.%s.%s_val;\n" n n n
	     | Bool n -> pr "  %s = args.%s;\n" n n
	     | Int n -> pr "  %s = args.%s;\n" n n
	     | FileIn _ | FileOut _ -> ()
	   ) args;
	   pr "\n"
      );

      (* Don't want to call the impl with any FileIn or FileOut
       * parameters, since these go "outside" the RPC protocol.
       *)
      let argsnofile =
	List.filter (function FileIn _ | FileOut _ -> false | _ -> true)
	  (snd style) in
      pr "  r = do_%s " name;
      generate_call_args argsnofile;
      pr ";\n";

      pr "  if (r == %s)\n" error_code;
      pr "    /* do_%s has already called reply_with_error */\n" name;
      pr "    goto done;\n";
      pr "\n";

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
	| RConstString _ ->
	    failwithf "RConstString cannot be returned from a daemon function"
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
	| RIntBool _ ->
	    pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) r);\n"
	      name;
	    pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) r);\n" name
	| RPVList n | RVGList n | RLVList n
	| RStat n | RStatVFS n ->
	    pr "  struct guestfs_%s_ret ret;\n" name;
	    pr "  ret.%s = *r;\n" n;
	    pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
	      name;
	    pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n"
	      name
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
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d\", proc_nr);\n";
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

	pr "static int lvm_tokenize_%s (char *str, struct guestfs_lvm_int_%s *r)\n" typ typ;
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
	pr "  if (!*str || isspace (*str)) {\n";
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
	     | `String ->
		 pr "  r->%s = strdup (tok);\n" name;
		 pr "  if (r->%s == NULL) {\n" name;
		 pr "    perror (\"strdup\");\n";
		 pr "    return -1;\n";
		 pr "  }\n"
	     | `UUID ->
		 pr "  for (i = j = 0; i < 32; ++j) {\n";
		 pr "    if (tok[j] == '\\0') {\n";
		 pr "      fprintf (stderr, \"%%s: failed to parse UUID from '%%s'\\n\", __func__, tok);\n";
		 pr "      return -1;\n";
		 pr "    } else if (tok[j] != '-')\n";
		 pr "      r->%s[i++] = tok[j];\n" name;
		 pr "  }\n";
	     | `Bytes ->
		 pr "  if (sscanf (tok, \"%%\"SCNu64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `Int ->
		 pr "  if (sscanf (tok, \"%%\"SCNi64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse int '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `OptPercent ->
		 pr "  if (tok[0] == '\\0')\n";
		 pr "    r->%s = -1;\n" name;
		 pr "  else if (sscanf (tok, \"%%f\", &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse float '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
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

	pr "guestfs_lvm_int_%s_list *\n" typ;
	pr "parse_command_line_%ss (void)\n" typ;
	pr "{\n";
	pr "  char *out, *err;\n";
	pr "  char *p, *pend;\n";
	pr "  int r, i;\n";
	pr "  guestfs_lvm_int_%s_list *ret;\n" typ;
	pr "  void *newp;\n";
	pr "\n";
	pr "  ret = malloc (sizeof *ret);\n";
	pr "  if (!ret) {\n";
	pr "    reply_with_perror (\"malloc\");\n";
	pr "    return NULL;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = 0;\n" typ;
	pr "  ret->guestfs_lvm_int_%s_list_val = NULL;\n" typ;
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
	pr "    while (*p && isspace (*p))	/* Skip any leading whitespace. */\n";
	pr "      p++;\n";
	pr "\n";
	pr "    if (!*p) {			/* Empty line?  Skip it. */\n";
	pr "      p = pend;\n";
	pr "      continue;\n";
	pr "    }\n";
	pr "\n";
	pr "    /* Allocate some space to store this next entry. */\n";
	pr "    newp = realloc (ret->guestfs_lvm_int_%s_list_val,\n" typ;
	pr "		    sizeof (guestfs_lvm_int_%s) * (i+1));\n" typ;
	pr "    if (newp == NULL) {\n";
	pr "      reply_with_perror (\"realloc\");\n";
	pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
	pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "    ret->guestfs_lvm_int_%s_list_val = newp;\n" typ;
	pr "\n";
	pr "    /* Tokenize the next entry. */\n";
	pr "    r = lvm_tokenize_%s (p, &ret->guestfs_lvm_int_%s_list_val[i]);\n" typ typ;
	pr "    if (r == -1) {\n";
	pr "      reply_with_error (\"failed to parse output of '%ss' command\");\n" typ;
        pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
        pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "\n";
	pr "    ++i;\n";
	pr "    p = pend;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = i;\n" typ;
	pr "\n";
	pr "  free (out);\n";
	pr "  return ret;\n";
	pr "}\n"

  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the tests. *)
and generate_tests () =
  generate_header CStyle GPLv2;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <fcntl.h>

#include \"guestfs.h\"

static guestfs_h *g;
static int suppress_error = 0;

static void print_error (guestfs_h *g, void *data, const char *msg)
{
  if (!suppress_error)
    fprintf (stderr, \"%%s\\n\", msg);
}

static void print_strings (char * const * const argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf (\"\\t%%s\\n\", argv[argc]);
}

/*
static void print_table (char * const * const argv)
{
  int i;

  for (i = 0; argv[i] != NULL; i += 2)
    printf (\"%%s: %%s\\n\", argv[i], argv[i+1]);
}
*/

static void no_test_warnings (void)
{
";

  List.iter (
    function
    | name, _, _, _, [], _, _ ->
	pr "  fprintf (stderr, \"warning: \\\"guestfs_%s\\\" has no tests\\n\");\n" name
    | name, _, _, _, tests, _, _ -> ()
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
      fun (name, _, _, _, tests, _, _) ->
	mapi (generate_one_test name) tests
    ) (List.rev all_functions) in
  let test_names = List.concat test_names in
  let nr_tests = List.length test_names in

  pr "\
int main (int argc, char *argv[])
{
  char c = 0;
  int failed = 0;
  const char *srcdir;
  const char *filename;
  int fd;
  int nr_tests, test_num = 0;

  no_test_warnings ();

  g = guestfs_create ();
  if (g == NULL) {
    printf (\"guestfs_create FAILED\\n\");
    exit (1);
  }

  guestfs_set_error_handler (g, print_error, NULL);

  srcdir = getenv (\"srcdir\");
  if (!srcdir) srcdir = \".\";
  chdir (srcdir);
  guestfs_set_path (g, \".\");

  filename = \"test1.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (1);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (1);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (1);
  }

  filename = \"test2.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (1);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (1);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (1);
  }

  filename = \"test3.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_NONBLOCK|O_TRUNC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (1);
  }
  if (lseek (fd, %d, SEEK_SET) == -1) {
    perror (\"lseek\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (write (fd, &c, 1) == -1) {
    perror (\"write\");
    close (fd);
    unlink (filename);
    exit (1);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (1);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"guestfs_add_drive %%s FAILED\\n\", filename);
    exit (1);
  }

  if (guestfs_launch (g) == -1) {
    printf (\"guestfs_launch FAILED\\n\");
    exit (1);
  }
  if (guestfs_wait_ready (g) == -1) {
    printf (\"guestfs_wait_ready FAILED\\n\");
    exit (1);
  }

  nr_tests = %d;

" (500 * 1024 * 1024) (50 * 1024 * 1024) (10 * 1024 * 1024) nr_tests;

  iteri (
    fun i test_name ->
      pr "  test_num++;\n";
      pr "  printf (\"%%3d/%%3d %s\\n\", test_num, nr_tests);\n" test_name;
      pr "  if (%s () == -1) {\n" test_name;
      pr "    printf (\"%s FAILED\\n\");\n" test_name;
      pr "    failed++;\n";
      pr "  }\n";
  ) test_names;
  pr "\n";

  pr "  guestfs_close (g);\n";
  pr "  unlink (\"test1.img\");\n";
  pr "  unlink (\"test2.img\");\n";
  pr "  unlink (\"test3.img\");\n";
  pr "\n";

  pr "  if (failed > 0) {\n";
  pr "    printf (\"***** %%d / %%d tests FAILED *****\\n\", failed, nr_tests);\n";
  pr "    exit (1);\n";
  pr "  }\n";
  pr "\n";

  pr "  exit (0);\n";
  pr "}\n"

and generate_one_test name i (init, test) =
  let test_name = sprintf "test_%s_%d" name i in

  pr "static int %s (void)\n" test_name;
  pr "{\n";

  (match init with
   | InitNone -> ()
   | InitEmpty ->
       pr "  /* InitEmpty for %s (%d) */\n" name i;
       List.iter (generate_test_command_call test_name)
	 [["umount_all"];
	  ["lvm_remove_all"]]
   | InitBasicFS ->
       pr "  /* InitBasicFS for %s (%d): create ext2 on /dev/sda1 */\n" name i;
       List.iter (generate_test_command_call test_name)
	 [["umount_all"];
	  ["lvm_remove_all"];
	  ["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
	  ["mkfs"; "ext2"; "/dev/sda1"];
	  ["mount"; "/dev/sda1"; "/"]]
   | InitBasicFSonLVM ->
       pr "  /* InitBasicFSonLVM for %s (%d): create ext2 on /dev/VG/LV */\n"
	 name i;
       List.iter (generate_test_command_call test_name)
	 [["umount_all"];
	  ["lvm_remove_all"];
	  ["sfdisk"; "/dev/sda"; "0"; "0"; "0"; ","];
	  ["pvcreate"; "/dev/sda1"];
	  ["vgcreate"; "VG"; "/dev/sda1"];
	  ["lvcreate"; "LV"; "VG"; "8"];
	  ["mkfs"; "ext2"; "/dev/VG/LV"];
	  ["mount"; "/dev/VG/LV"; "/"]]
  );

  let get_seq_last = function
    | [] ->
	failwithf "%s: you cannot use [] (empty list) when expecting a command"
	  test_name
    | seq ->
	let seq = List.rev seq in
	List.rev (List.tl seq), List.hd seq
  in

  (match test with
   | TestRun seq ->
       pr "  /* TestRun for %s (%d) */\n" name i;
       List.iter (generate_test_command_call test_name) seq
   | TestOutput (seq, expected) ->
       pr "  /* TestOutput for %s (%d) */\n" name i;
       let seq, last = get_seq_last seq in
       let test () =
	 pr "    if (strcmp (r, \"%s\") != 0) {\n" (c_quote expected);
	 pr "      fprintf (stderr, \"%s: expected \\\"%s\\\" but got \\\"%%s\\\"\\n\", r);\n" test_name (c_quote expected);
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
	     pr "    if (strcmp (r[%d], \"%s\") != 0) {\n" i (c_quote str);
	     pr "      fprintf (stderr, \"%s: expected \\\"%s\\\" but got \\\"%%s\\\"\\n\", r[%d]);\n" test_name (c_quote str) i;
	     pr "      return -1;\n";
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
	   | CompareWithString (field, expected) ->
	       pr "    if (strcmp (r->%s, \"%s\") != 0) {\n" field expected;
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
	       pr "    if (strcmp (r->%s, r->%s) != 0) {\n" field1 field2;
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
  );

  pr "  return 0;\n";
  pr "}\n";
  pr "\n";
  test_name

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
	| String _, _
	| OptString _, _
	| Int _, _
	| Bool _, _ -> ()
	| FileIn _, _ | FileOut _, _ -> ()
	| StringList n, arg ->
	    pr "    char *%s[] = {\n" n;
	    let strs = string_split " " arg in
	    List.iter (
	      fun str -> pr "      \"%s\",\n" (c_quote str)
	    ) strs;
	    pr "      NULL\n";
	    pr "    };\n";
      ) (List.combine (snd style) args);

      let error_code =
	match fst style with
	| RErr | RInt _ | RBool _ -> pr "    int r;\n"; "-1"
	| RInt64 _ -> pr "    int64_t r;\n"; "-1"
	| RConstString _ -> pr "    const char *r;\n"; "NULL"
	| RString _ -> pr "    char *r;\n"; "NULL"
	| RStringList _ | RHashtable _ ->
	    pr "    char **r;\n";
	    pr "    int i;\n";
	    "NULL"
	| RIntBool _ ->
	    pr "    struct guestfs_int_bool *r;\n"; "NULL"
	| RPVList _ ->
	    pr "    struct guestfs_lvm_pv_list *r;\n"; "NULL"
	| RVGList _ ->
	    pr "    struct guestfs_lvm_vg_list *r;\n"; "NULL"
	| RLVList _ ->
	    pr "    struct guestfs_lvm_lv_list *r;\n"; "NULL"
	| RStat _ ->
	    pr "    struct guestfs_stat *r;\n"; "NULL"
	| RStatVFS _ ->
	    pr "    struct guestfs_statvfs *r;\n"; "NULL" in

      pr "    suppress_error = %d;\n" (if expect_error then 1 else 0);
      pr "    r = guestfs_%s (g" name;

      (* Generate the parameters. *)
      List.iter (
	function
	| String _, arg
	| FileIn _, arg | FileOut _, arg ->
	    pr ", \"%s\"" (c_quote arg)
	| OptString _, arg ->
	    if arg = "NULL" then pr ", NULL" else pr ", \"%s\"" (c_quote arg)
	| StringList n, _ ->
	    pr ", %s" n
	| Int _, arg ->
	    let i =
	      try int_of_string arg
	      with Failure "int_of_string" ->
		failwithf "%s: expecting an int, but got '%s'" test_name arg in
	    pr ", %d" i
	| Bool _, arg ->
	    let b = bool_of_string arg in pr ", %d" (if b then 1 else 0)
      ) (List.combine (snd style) args);

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
       | RErr | RInt _ | RInt64 _ | RBool _ | RConstString _ -> ()
       | RString _ -> pr "    free (r);\n"
       | RStringList _ | RHashtable _ ->
	   pr "    for (i = 0; r[i] != NULL; ++i)\n";
	   pr "      free (r[i]);\n";
	   pr "    free (r);\n"
       | RIntBool _ ->
	   pr "    guestfs_free_int_bool (r);\n"
       | RPVList _ ->
	   pr "    guestfs_free_lvm_pv_list (r);\n"
       | RVGList _ ->
	   pr "    guestfs_free_lvm_vg_list (r);\n"
       | RLVList _ ->
	   pr "    guestfs_free_lvm_lv_list (r);\n"
       | RStat _ | RStatVFS _ ->
	   pr "    free (r);\n"
      );

      pr "  }\n"

and c_quote str =
  let str = replace_str str "\r" "\\r" in
  let str = replace_str str "\n" "\\n" in
  let str = replace_str str "\t" "\\t" in
  str

(* Generate a lot of different functions for guestfish. *)
and generate_fish_cmds () =
  generate_header CStyle GPLv2;

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
  pr "#include \"fish.h\"\n";
  pr "\n";

  (* list_commands function, which implements guestfish -h *)
  pr "void list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", \"Command\", \"Description\");\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, flags, _, shortdesc, _) ->
      let name = replace_char name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", \"%s\");\n"
	name shortdesc
  ) all_functions_sorted;
  pr "  printf (\"    Use -h <cmd> / help <cmd> to show detailed help for a command.\\n\");\n";
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
	    sprintf "%s <%s>"
	      name2 (String.concat "> <" (List.map name_of_argt args)) in

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

      let describe_alias =
	if name <> alias then
	  sprintf "\n\nYou can use '%s' as an alias for this command." alias
	else "" in

      pr "  if (";
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      if name <> alias then
	pr " || strcasecmp (cmd, \"%s\") == 0" alias;
      pr ")\n";
      pr "    pod2text (\"%s - %s\", %S);\n"
	name2 shortdesc
	(" " ^ synopsis ^ "\n\n" ^ longdesc ^ warnings ^ describe_alias);
      pr "  else\n"
  ) all_functions;
  pr "    display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  (* print_{pv,vg,lv}_list functions *)
  List.iter (
    function
    | typ, cols ->
	pr "static void print_%s (struct guestfs_lvm_%s *%s)\n" typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	List.iter (
	  function
	  | name, `String ->
	      pr "  printf (\"%s: %%s\\n\", %s->%s);\n" name typ name
	  | name, `UUID ->
	      pr "  printf (\"%s: \");\n" name;
	      pr "  for (i = 0; i < 32; ++i)\n";
	      pr "    printf (\"%%c\", %s->%s[i]);\n" typ name;
	      pr "  printf (\"\\n\");\n"
	  | name, `Bytes ->
	      pr "  printf (\"%s: %%\" PRIu64 \"\\n\", %s->%s);\n" name typ name
	  | name, `Int ->
	      pr "  printf (\"%s: %%\" PRIi64 \"\\n\", %s->%s);\n" name typ name
	  | name, `OptPercent ->
	      pr "  if (%s->%s >= 0) printf (\"%s: %%g %%%%\\n\", %s->%s);\n"
		typ name name typ name;
	      pr "  else printf (\"%s: \\n\");\n" name
	) cols;
	pr "}\n";
	pr "\n";
	pr "static void print_%s_list (struct guestfs_lvm_%s_list *%ss)\n"
	  typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
	pr "    print_%s (&%ss->val[i]);\n" typ typ;
	pr "}\n";
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* print_{stat,statvfs} functions *)
  List.iter (
    function
    | typ, cols ->
	pr "static void print_%s (struct guestfs_%s *%s)\n" typ typ typ;
	pr "{\n";
	List.iter (
	  function
	  | name, `Int ->
	      pr "  printf (\"%s: %%\" PRIi64 \"\\n\", %s->%s);\n" name typ name
	) cols;
	pr "}\n";
	pr "\n";
  ) ["stat", stat_cols; "statvfs", statvfs_cols];

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
       | RConstString _ -> pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ | RHashtable _ -> pr "  char **r;\n"
       | RIntBool _ -> pr "  struct guestfs_int_bool *r;\n"
       | RPVList _ -> pr "  struct guestfs_lvm_pv_list *r;\n"
       | RVGList _ -> pr "  struct guestfs_lvm_vg_list *r;\n"
       | RLVList _ -> pr "  struct guestfs_lvm_lv_list *r;\n"
       | RStat _ -> pr "  struct guestfs_stat *r;\n"
       | RStatVFS _ -> pr "  struct guestfs_statvfs *r;\n"
      );
      List.iter (
	function
	| String n
	| OptString n
	| FileIn n
	| FileOut n -> pr "  const char *%s;\n" n
	| StringList n -> pr "  char **%s;\n" n
	| Bool n -> pr "  int %s;\n" n
	| Int n -> pr "  int %s;\n" n
      ) (snd style);

      (* Check and convert parameters. *)
      let argc_expected = List.length (snd style) in
      pr "  if (argc != %d) {\n" argc_expected;
      pr "    fprintf (stderr, \"%%s should have %d parameter(s)\\n\", cmd);\n"
	argc_expected;
      pr "    fprintf (stderr, \"type 'help %%s' for help on %%s\\n\", cmd, cmd);\n";
      pr "    return -1;\n";
      pr "  }\n";
      iteri (
	fun i ->
	  function
	  | String name -> pr "  %s = argv[%d];\n" name i
	  | OptString name ->
	      pr "  %s = strcmp (argv[%d], \"\") != 0 ? argv[%d] : NULL;\n"
		name i i
	  | FileIn name ->
	      pr "  %s = strcmp (argv[%d], \"-\") != 0 ? argv[%d] : \"/dev/stdin\";\n"
		name i i
	  | FileOut name ->
	      pr "  %s = strcmp (argv[%d], \"-\") != 0 ? argv[%d] : \"/dev/stdout\";\n"
		name i i
	  | StringList name ->
	      pr "  %s = parse_string_list (argv[%d]);\n" name i
	  | Bool name ->
	      pr "  %s = is_true (argv[%d]) ? 1 : 0;\n" name i
	  | Int name ->
	      pr "  %s = atoi (argv[%d]);\n" name i
      ) (snd style);

      (* Call C API function. *)
      let fn =
	try find_map (function FishAction n -> Some n | _ -> None) flags
	with Not_found -> sprintf "guestfs_%s" name in
      pr "  r = %s " fn;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";

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
       | RIntBool _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  printf (\"%%d, %%s\\n\", r->i,\n";
	   pr "    r->b ? \"true\" : \"false\");\n";
	   pr "  guestfs_free_int_bool (r);\n";
	   pr "  return 0;\n"
       | RPVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n";
	   pr "  return 0;\n"
       | RVGList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n";
	   pr "  return 0;\n"
       | RLVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n";
	   pr "  return 0;\n"
       | RStat _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_stat (r);\n";
	   pr "  free (r);\n";
	   pr "  return 0;\n"
       | RStatVFS _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_statvfs (r);\n";
	   pr "  free (r);\n";
	   pr "  return 0;\n"
       | RHashtable _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_table (r);\n";
	   pr "  free_strings (r);\n";
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
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      if name <> alias then
	pr " || strcasecmp (cmd, \"%s\") == 0" alias;
      pr ")\n";
      pr "    return run_%s (cmd, argc, argv);\n" name;
      pr "  else\n";
  ) all_functions;
  pr "    {\n";
  pr "      fprintf (stderr, \"%%s: unknown command\\n\", cmd);\n";
  pr "      return -1;\n";
  pr "    }\n";
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

(* Readline completion for guestfish. *)
and generate_fish_completion () =
  generate_header CStyle GPLv2;

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

static const char *commands[] = {
";

  (* Get the commands and sort them, including the aliases. *)
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
  let commands = List.sort compare commands in

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

  while ((name = commands[index]) != NULL) {
    index++;
    if (strncasecmp (name, text, len) == 0)
      return strdup (name);
  }

  return NULL;
}

#endif /* HAVE_LIBREADLINE */

char **do_completion (const char *text, int start, int end)
{
  char **matches = NULL;

#ifdef HAVE_LIBREADLINE
  if (start == 0)
    matches = rl_completion_matches (text, generator);
#endif

  return matches;
}
";

(* Generate the POD documentation for guestfish. *)
and generate_fish_actions_pod () =
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  List.iter (
    fun (name, style, _, flags, _, _, longdesc) ->
      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
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
	| String n -> pr " %s" n
	| OptString n -> pr " %s" n
	| StringList n -> pr " %s,..." n
	| Bool _ -> pr " true|false"
	| Int n -> pr " %s" n
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
	pr "%s\n\n" danger_will_robinson
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
   | RConstString _ -> pr "const char *"
   | RString _ -> pr "char *"
   | RStringList _ | RHashtable _ -> pr "char **"
   | RIntBool _ ->
       if not in_daemon then pr "struct guestfs_int_bool *"
       else pr "guestfs_%s_ret *" name
   | RPVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_pv_list *"
       else pr "guestfs_lvm_int_pv_list *"
   | RVGList _ ->
       if not in_daemon then pr "struct guestfs_lvm_vg_list *"
       else pr "guestfs_lvm_int_vg_list *"
   | RLVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_lv_list *"
       else pr "guestfs_lvm_int_lv_list *"
   | RStat _ ->
       if not in_daemon then pr "struct guestfs_stat *"
       else pr "guestfs_int_stat *"
   | RStatVFS _ ->
       if not in_daemon then pr "struct guestfs_statvfs *"
       else pr "guestfs_int_statvfs *"
  );
  pr "%s%s (" prefix name;
  if handle = None && List.length (snd style) = 0 then
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
      | String n
      | OptString n -> next (); pr "const char *%s" n
      | StringList n -> next (); pr "char * const* const %s" n
      | Bool n -> next (); pr "int %s" n
      | Int n -> next (); pr "int %s" n
      | FileIn n
      | FileOut n ->
	  if not in_daemon then (next (); pr "const char *%s" n)
    ) (snd style);
  );
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_call_args ?handle args =
  pr "(";
  let comma = ref false in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  List.iter (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      pr "%s" (name_of_argt arg)
  ) args;
  pr ")"

(* Generate the OCaml bindings interface. *)
and generate_ocaml_mli () =
  generate_header OCamlStyle LGPLv2;

  pr "\
(** For API documentation you should refer to the C API
    in the guestfs(3) manual page.  The OCaml API uses almost
    exactly the same calls. *)

type t
(** A [guestfs_h] handle. *)

exception Error of string
(** This exception is raised when there is an error. *)

val create : unit -> t

val close : t -> unit
(** Handles are closed by the garbage collector when they become
    unreferenced, but callers can also call this in order to
    provide predictable cleanup. *)

";
  generate_ocaml_lvm_structure_decls ();

  generate_ocaml_stat_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, _, shortdesc, _) ->
      generate_ocaml_prototype name style;
      pr "(** %s *)\n" shortdesc;
      pr "\n"
  ) all_functions

(* Generate the OCaml bindings implementation. *)
and generate_ocaml_ml () =
  generate_header OCamlStyle LGPLv2;

  pr "\
type t
exception Error of string
external create : unit -> t = \"ocaml_guestfs_create\"
external close : t -> unit = \"ocaml_guestfs_close\"

let () =
  Callback.register_exception \"ocaml_guestfs_error\" (Error \"\")

";

  generate_ocaml_lvm_structure_decls ();

  generate_ocaml_stat_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, _, shortdesc, _) ->
      generate_ocaml_prototype ~is_external:true name style;
  ) all_functions

(* Generate the OCaml bindings C implementation. *)
and generate_ocaml_c () =
  generate_header CStyle LGPLv2;

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

  (* LVM struct copy functions. *)
  List.iter (
    fun (typ, cols) ->
      let has_optpercent_col =
	List.exists (function (_, `OptPercent) -> true | _ -> false) cols in

      pr "static CAMLprim value\n";
      pr "copy_lvm_%s (const struct guestfs_lvm_%s *%s)\n" typ typ typ;
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
	   | name, `String ->
	       pr "  v = caml_copy_string (%s->%s);\n" typ name
	   | name, `UUID ->
	       pr "  v = caml_alloc_string (32);\n";
	       pr "  memcpy (String_val (v), %s->%s, 32);\n" typ name
	   | name, `Bytes
	   | name, `Int ->
	       pr "  v = caml_copy_int64 (%s->%s);\n" typ name
	   | name, `OptPercent ->
	       pr "  if (%s->%s >= 0) { /* Some %s */\n" typ name name;
	       pr "    v2 = caml_copy_double (%s->%s);\n" typ name;
	       pr "    v = caml_alloc (1, 0);\n";
	       pr "    Store_field (v, 0, v2);\n";
	       pr "  } else /* None */\n";
	       pr "    v = Val_int (0);\n";
	  );
	  pr "  Store_field (rv, %d, v);\n" i
      ) cols;
      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";

      pr "static CAMLprim value\n";
      pr "copy_lvm_%s_list (const struct guestfs_lvm_%s_list *%ss)\n"
	typ typ typ;
      pr "{\n";
      pr "  CAMLparam0 ();\n";
      pr "  CAMLlocal2 (rv, v);\n";
      pr "  int i;\n";
      pr "\n";
      pr "  if (%ss->len == 0)\n" typ;
      pr "    CAMLreturn (Atom (0));\n";
      pr "  else {\n";
      pr "    rv = caml_alloc (%ss->len, 0);\n" typ;
      pr "    for (i = 0; i < %ss->len; ++i) {\n" typ;
      pr "      v = copy_lvm_%s (&%ss->val[i]);\n" typ typ;
      pr "      caml_modify (&Field (rv, i), v);\n";
      pr "    }\n";
      pr "    CAMLreturn (rv);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* Stat copy functions. *)
  List.iter (
    fun (typ, cols) ->
      pr "static CAMLprim value\n";
      pr "copy_%s (const struct guestfs_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  CAMLparam0 ();\n";
      pr "  CAMLlocal2 (rv, v);\n";
      pr "\n";
      pr "  rv = caml_alloc (%d, 0);\n" (List.length cols);
      iteri (
	fun i col ->
	  (match col with
	   | name, `Int ->
	       pr "  v = caml_copy_int64 (%s->%s);\n" typ name
	  );
	  pr "  Store_field (rv, %d, v);\n" i
      ) cols;
      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";
  ) ["stat", stat_cols; "statvfs", statvfs_cols];

  (* The wrappers. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      let params =
	"gv" :: List.map (fun arg -> name_of_argt arg ^ "v") (snd style) in

      pr "CAMLprim value\n";
      pr "ocaml_guestfs_%s (value %s" name (List.hd params);
      List.iter (pr ", value %s") (List.tl params);
      pr ")\n";
      pr "{\n";

      (match params with
       | p1 :: p2 :: p3 :: p4 :: p5 :: rest ->
	   pr "  CAMLparam5 (%s);\n" (String.concat ", " [p1; p2; p3; p4; p5]);
	   pr "  CAMLxparam%d (%s);\n"
	     (List.length rest) (String.concat ", " rest)
       | ps ->
	   pr "  CAMLparam%d (%s);\n" (List.length ps) (String.concat ", " ps)
      );
      pr "  CAMLlocal1 (rv);\n";
      pr "\n";

      pr "  guestfs_h *g = Guestfs_val (gv);\n";
      pr "  if (g == NULL)\n";
      pr "    caml_failwith (\"%s: used handle after closing it\");\n" name;
      pr "\n";

      List.iter (
	function
	| String n
	| FileIn n
	| FileOut n ->
	    pr "  const char *%s = String_val (%sv);\n" n n
	| OptString n ->
	    pr "  const char *%s =\n" n;
	    pr "    %sv != Val_int (0) ? String_val (Field (%sv, 0)) : NULL;\n"
	      n n
	| StringList n ->
	    pr "  char **%s = ocaml_guestfs_strings_val (%sv);\n" n n
	| Bool n ->
	    pr "  int %s = Bool_val (%sv);\n" n n
	| Int n ->
	    pr "  int %s = Int_val (%sv);\n" n n
      ) (snd style);
      let error_code =
	match fst style with
	| RErr -> pr "  int r;\n"; "-1"
	| RInt _ -> pr "  int r;\n"; "-1"
	| RInt64 _ -> pr "  int64_t r;\n"; "-1"
	| RBool _ -> pr "  int r;\n"; "-1"
	| RConstString _ -> pr "  const char *r;\n"; "NULL"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ ->
	    pr "  int i;\n";
	    pr "  char **r;\n";
	    "NULL"
	| RIntBool _ ->
	    pr "  struct guestfs_int_bool *r;\n"; "NULL"
	| RPVList _ ->
	    pr "  struct guestfs_lvm_pv_list *r;\n"; "NULL"
	| RVGList _ ->
	    pr "  struct guestfs_lvm_vg_list *r;\n"; "NULL"
	| RLVList _ ->
	    pr "  struct guestfs_lvm_lv_list *r;\n"; "NULL"
	| RStat _ ->
	    pr "  struct guestfs_stat *r;\n"; "NULL"
	| RStatVFS _ ->
	    pr "  struct guestfs_statvfs *r;\n"; "NULL"
	| RHashtable _ ->
	    pr "  int i;\n";
	    pr "  char **r;\n";
	    "NULL" in
      pr "\n";

      pr "  caml_enter_blocking_section ();\n";
      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";
      pr "  caml_leave_blocking_section ();\n";

      List.iter (
	function
	| StringList n ->
	    pr "  ocaml_guestfs_free_strings (%s);\n" n;
	| String _ | OptString _ | Bool _ | Int _ | FileIn _ | FileOut _ -> ()
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
       | RConstString _ -> pr "  rv = caml_copy_string (r);\n"
       | RString _ ->
	   pr "  rv = caml_copy_string (r);\n";
	   pr "  free (r);\n"
       | RStringList _ ->
	   pr "  rv = caml_copy_string_array ((const char **) r);\n";
	   pr "  for (i = 0; r[i] != NULL; ++i) free (r[i]);\n";
	   pr "  free (r);\n"
       | RIntBool _ ->
	   pr "  rv = caml_alloc (2, 0);\n";
	   pr "  Store_field (rv, 0, Val_int (r->i));\n";
	   pr "  Store_field (rv, 1, Val_bool (r->b));\n";
	   pr "  guestfs_free_int_bool (r);\n";
       | RPVList _ ->
	   pr "  rv = copy_lvm_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n";
       | RVGList _ ->
	   pr "  rv = copy_lvm_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n";
       | RLVList _ ->
	   pr "  rv = copy_lvm_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n";
       | RStat _ ->
	   pr "  rv = copy_stat (r);\n";
	   pr "  free (r);\n";
       | RStatVFS _ ->
	   pr "  rv = copy_statvfs (r);\n";
	   pr "  free (r);\n";
       | RHashtable _ ->
	   pr "  rv = copy_table (r);\n";
	   pr "  for (i = 0; r[i] != NULL; ++i) free (r[i]);\n";
	   pr "  free (r);\n";
      );

      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";

      if List.length params > 5 then (
	pr "CAMLprim value\n";
	pr "ocaml_guestfs_%s_byte (value *argv, int argn)\n" name;
	pr "{\n";
	pr "  return ocaml_guestfs_%s (argv[0]" name;
	iteri (fun i _ -> pr ", argv[%d]" i) (List.tl params);
	pr ");\n";
	pr "}\n";
	pr "\n"
      )
  ) all_functions

and generate_ocaml_lvm_structure_decls () =
  List.iter (
    fun (typ, cols) ->
      pr "type lvm_%s = {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  %s : string;\n" name
	| name, `UUID -> pr "  %s : string;\n" name
	| name, `Bytes -> pr "  %s : int64;\n" name
	| name, `Int -> pr "  %s : int64;\n" name
	| name, `OptPercent -> pr "  %s : float option;\n" name
      ) cols;
      pr "}\n";
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

and generate_ocaml_stat_structure_decls () =
  List.iter (
    fun (typ, cols) ->
      pr "type %s = {\n" typ;
      List.iter (
	function
	| name, `Int -> pr "  %s : int64;\n" name
      ) cols;
      pr "}\n";
      pr "\n"
  ) ["stat", stat_cols; "statvfs", statvfs_cols]

and generate_ocaml_prototype ?(is_external = false) name style =
  if is_external then pr "external " else pr "val ";
  pr "%s : t -> " name;
  List.iter (
    function
    | String _ | FileIn _ | FileOut _ -> pr "string -> "
    | OptString _ -> pr "string option -> "
    | StringList _ -> pr "string array -> "
    | Bool _ -> pr "bool -> "
    | Int _ -> pr "int -> "
  ) (snd style);
  (match fst style with
   | RErr -> pr "unit" (* all errors are turned into exceptions *)
   | RInt _ -> pr "int"
   | RInt64 _ -> pr "int64"
   | RBool _ -> pr "bool"
   | RConstString _ -> pr "string"
   | RString _ -> pr "string"
   | RStringList _ -> pr "string array"
   | RIntBool _ -> pr "int * bool"
   | RPVList _ -> pr "lvm_pv array"
   | RVGList _ -> pr "lvm_vg array"
   | RLVList _ -> pr "lvm_lv array"
   | RStat _ -> pr "stat"
   | RStatVFS _ -> pr "statvfs"
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
  generate_header CStyle LGPLv2;

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

  if (!arg || !SvOK (arg) || !SvROK (arg) || SvTYPE (SvRV (arg)) != SVt_PVAV) {
    croak (\"array reference expected\");
  }

  av = (AV *)SvRV (arg);
  ret = (char **)malloc (av_len (av) + 1 + 1);

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
       | RString _ -> pr "SV *\n"
       | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _
       | RStat _ | RStatVFS _
       | RHashtable _ ->
	   pr "void\n" (* all lists returned implictly on the stack *)
      );
      (* Call and arguments. *)
      pr "%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr "\n";
      pr "      guestfs_h *g;\n";
      List.iter (
	function
	| String n | FileIn n | FileOut n -> pr "      char *%s;\n" n
	| OptString n -> pr "      char *%s;\n" n
	| StringList n -> pr "      char **%s;\n" n
	| Bool n -> pr "      int %s;\n" n
	| Int n -> pr "      int %s;\n" n
      ) (snd style);

      let do_cleanups () =
	List.iter (
	  function
	  | String _ | OptString _ | Bool _ | Int _
	  | FileIn _ | FileOut _ -> ()
	  | StringList n -> pr "      free (%s);\n" n
	) (snd style)
      in

      (* Code. *)
      (match fst style with
       | RErr ->
	   pr "PREINIT:\n";
	   pr "      int r;\n";
	   pr " PPCODE:\n";
	   pr "      r = guestfs_%s " name;
	   generate_call_args ~handle:"g" (snd style);
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
	   generate_call_args ~handle:"g" (snd style);
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
	   generate_call_args ~handle:"g" (snd style);
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
	   generate_call_args ~handle:"g" (snd style);
	   pr ";\n";
	   do_cleanups ();
	   pr "      if (%s == NULL)\n" n;
	   pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
	   pr "      RETVAL = newSVpv (%s, 0);\n" n;
	   pr " OUTPUT:\n";
	   pr "      RETVAL\n"
       | RString n ->
	   pr "PREINIT:\n";
	   pr "      char *%s;\n" n;
	   pr "   CODE:\n";
	   pr "      %s = guestfs_%s " n name;
	   generate_call_args ~handle:"g" (snd style);
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
	   generate_call_args ~handle:"g" (snd style);
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
       | RIntBool _ ->
	   pr "PREINIT:\n";
	   pr "      struct guestfs_int_bool *r;\n";
	   pr " PPCODE:\n";
	   pr "      r = guestfs_%s " name;
	   generate_call_args ~handle:"g" (snd style);
	   pr ";\n";
	   do_cleanups ();
	   pr "      if (r == NULL)\n";
	   pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
	   pr "      EXTEND (SP, 2);\n";
	   pr "      PUSHs (sv_2mortal (newSViv (r->i)));\n";
	   pr "      PUSHs (sv_2mortal (newSViv (r->b)));\n";
	   pr "      guestfs_free_int_bool (r);\n";
       | RPVList n ->
	   generate_perl_lvm_code "pv" pv_cols name style n do_cleanups
       | RVGList n ->
	   generate_perl_lvm_code "vg" vg_cols name style n do_cleanups
       | RLVList n ->
	   generate_perl_lvm_code "lv" lv_cols name style n do_cleanups
       | RStat n ->
	   generate_perl_stat_code "stat" stat_cols name style n do_cleanups
       | RStatVFS n ->
	   generate_perl_stat_code
	     "statvfs" statvfs_cols name style n do_cleanups
      );

      pr "\n"
  ) all_functions

and generate_perl_lvm_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_lvm_%s_list *%s;\n" typ n;
  pr "      int i;\n";
  pr "      HV *hv;\n";
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_call_args ~handle:"g" (snd style);
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
  pr "      EXTEND (SP, %s->len);\n" n;
  pr "      for (i = 0; i < %s->len; ++i) {\n" n;
  pr "        hv = newHV ();\n";
  List.iter (
    function
    | name, `String ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 0), 0);\n"
	  name (String.length name) n name
    | name, `UUID ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 32), 0);\n"
	  name (String.length name) n name
    | name, `Bytes ->
	pr "        (void) hv_store (hv, \"%s\", %d, my_newSVull (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
    | name, `Int ->
	pr "        (void) hv_store (hv, \"%s\", %d, my_newSVll (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
    | name, `OptPercent ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
  ) cols;
  pr "        PUSHs (sv_2mortal ((SV *) hv));\n";
  pr "      }\n";
  pr "      guestfs_free_lvm_%s_list (%s);\n" typ n

and generate_perl_stat_code typ cols name style n do_cleanups =
  pr "PREINIT:\n";
  pr "      struct guestfs_%s *%s;\n" typ n;
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_call_args ~handle:"g" (snd style);
  pr ";\n";
  do_cleanups ();
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%s: %%s\", guestfs_last_error (g));\n" name;
  pr "      EXTEND (SP, %d);\n" (List.length cols);
  List.iter (
    function
    | name, `Int ->
	pr "      PUSHs (sv_2mortal (my_newSVll (%s->%s)));\n" n name
  ) cols;
  pr "      free (%s);\n" n

(* Generate Sys/Guestfs.pm. *)
and generate_perl_pm () =
  generate_header HashStyle LGPLv2;

  pr "\
=pod

=head1 NAME

Sys::Guestfs - Perl bindings for libguestfs

=head1 SYNOPSIS

 use Sys::Guestfs;
 
 my $h = Sys::Guestfs->new ();
 $h->add_drive ('guest.img');
 $h->launch ();
 $h->wait_ready ();
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
      let longdesc = replace_str longdesc "C<guestfs_" "C<$h-E<gt>" in
      pr "=item ";
      generate_perl_prototype name style;
      pr "\n\n";
      pr "%s\n\n" longdesc;
      if List.mem ProtocolLimitWarning flags then
	pr "%s\n\n" protocol_limit_warning;
      if List.mem DangerWillRobinson flags then
	pr "%s\n\n" danger_will_robinson
  ) all_functions_sorted;

  (* End of file. *)
  pr "\
=cut

1;

=back

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<guestfs(3)>, L<guestfish(1)>.

=cut
"

and generate_perl_prototype name style =
  (match fst style with
   | RErr -> ()
   | RBool n
   | RInt n
   | RInt64 n
   | RConstString n
   | RString n -> pr "$%s = " n
   | RIntBool (n, m) -> pr "($%s, $%s) = " n m
   | RStringList n
   | RPVList n
   | RVGList n
   | RLVList n -> pr "@%s = " n
   | RStat n
   | RStatVFS n
   | RHashtable n -> pr "%%%s = " n
  );
  pr "$h->%s (" name;
  let comma = ref false in
  List.iter (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | String n | OptString n | Bool n | Int n | FileIn n | FileOut n ->
	  pr "$%s" n
      | StringList n ->
	  pr "\\@%s" n
  ) (snd style);
  pr ");"

(* Generate Python C module. *)
and generate_python_c () =
  generate_header CStyle LGPLv2;

  pr "\
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include <Python.h>

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
static const char **
get_string_list (PyObject *obj)
{
  int i, len;
  const char **r;

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

  (* LVM structures, turned into Python dictionaries. *)
  List.iter (
    fun (typ, cols) ->
      pr "static PyObject *\n";
      pr "put_lvm_%s (struct guestfs_lvm_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  PyObject *dict;\n";
      pr "\n";
      pr "  dict = PyDict_New ();\n";
      List.iter (
	function
	| name, `String ->
	    pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                        PyString_FromString (%s->%s));\n"
	      typ name
	| name, `UUID ->
	    pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                        PyString_FromStringAndSize (%s->%s, 32));\n"
	      typ name
	| name, `Bytes ->
	    pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                        PyLong_FromUnsignedLongLong (%s->%s));\n"
	      typ name
	| name, `Int ->
	    pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                        PyLong_FromLongLong (%s->%s));\n"
	      typ name
	| name, `OptPercent ->
	    pr "  if (%s->%s >= 0)\n" typ name;
	    pr "    PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                          PyFloat_FromDouble ((double) %s->%s));\n"
	      typ name;
	    pr "  else {\n";
	    pr "    Py_INCREF (Py_None);\n";
	    pr "    PyDict_SetItemString (dict, \"%s\", Py_None);" name;
	    pr "  }\n"
      ) cols;
      pr "  return dict;\n";
      pr "};\n";
      pr "\n";

      pr "static PyObject *\n";
      pr "put_lvm_%s_list (struct guestfs_lvm_%s_list *%ss)\n" typ typ typ;
      pr "{\n";
      pr "  PyObject *list;\n";
      pr "  int i;\n";
      pr "\n";
      pr "  list = PyList_New (%ss->len);\n" typ;
      pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
      pr "    PyList_SetItem (list, i, put_lvm_%s (&%ss->val[i]));\n" typ typ;
      pr "  return list;\n";
      pr "};\n";
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* Stat structures, turned into Python dictionaries. *)
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
	| name, `Int ->
	    pr "  PyDict_SetItemString (dict, \"%s\",\n" name;
	    pr "                        PyLong_FromLongLong (%s->%s));\n"
	      typ name
      ) cols;
      pr "  return dict;\n";
      pr "};\n";
      pr "\n";
  ) ["stat", stat_cols; "statvfs", statvfs_cols];

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
	| RConstString _ -> pr "  const char *r;\n"; "NULL"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
	| RIntBool _ -> pr "  struct guestfs_int_bool *r;\n"; "NULL"
	| RPVList n -> pr "  struct guestfs_lvm_pv_list *r;\n"; "NULL"
	| RVGList n -> pr "  struct guestfs_lvm_vg_list *r;\n"; "NULL"
	| RLVList n -> pr "  struct guestfs_lvm_lv_list *r;\n"; "NULL"
	| RStat n -> pr "  struct guestfs_stat *r;\n"; "NULL"
	| RStatVFS n -> pr "  struct guestfs_statvfs *r;\n"; "NULL" in

      List.iter (
	function
	| String n | FileIn n | FileOut n -> pr "  const char *%s;\n" n
	| OptString n -> pr "  const char *%s;\n" n
	| StringList n ->
	    pr "  PyObject *py_%s;\n" n;
	    pr "  const char **%s;\n" n
	| Bool n -> pr "  int %s;\n" n
	| Int n -> pr "  int %s;\n" n
      ) (snd style);

      pr "\n";

      (* Convert the parameters. *)
      pr "  if (!PyArg_ParseTuple (args, (char *) \"O";
      List.iter (
	function
	| String _ | FileIn _ | FileOut _ -> pr "s"
	| OptString _ -> pr "z"
	| StringList _ -> pr "O"
	| Bool _ -> pr "i" (* XXX Python has booleans? *)
	| Int _ -> pr "i"
      ) (snd style);
      pr ":guestfs_%s\",\n" name;
      pr "                         &py_g";
      List.iter (
	function
	| String n | FileIn n | FileOut n -> pr ", &%s" n
	| OptString n -> pr ", &%s" n
	| StringList n -> pr ", &py_%s" n
	| Bool n -> pr ", &%s" n
	| Int n -> pr ", &%s" n
      ) (snd style);

      pr "))\n";
      pr "    return NULL;\n";

      pr "  g = get_handle (py_g);\n";
      List.iter (
	function
	| String _ | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ -> ()
	| StringList n ->
	    pr "  %s = get_string_list (py_%s);\n" n n;
	    pr "  if (!%s) return NULL;\n" n
      ) (snd style);

      pr "\n";

      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";

      List.iter (
	function
	| String _ | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ -> ()
	| StringList n ->
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
       | RString _ ->
	   pr "  py_r = PyString_FromString (r);\n";
	   pr "  free (r);\n"
       | RStringList _ ->
	   pr "  py_r = put_string_list (r);\n";
	   pr "  free_strings (r);\n"
       | RIntBool _ ->
	   pr "  py_r = PyTuple_New (2);\n";
	   pr "  PyTuple_SetItem (py_r, 0, PyInt_FromLong ((long) r->i));\n";
	   pr "  PyTuple_SetItem (py_r, 1, PyInt_FromLong ((long) r->b));\n";
	   pr "  guestfs_free_int_bool (r);\n"
       | RPVList n ->
	   pr "  py_r = put_lvm_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n"
       | RVGList n ->
	   pr "  py_r = put_lvm_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n"
       | RLVList n ->
	   pr "  py_r = put_lvm_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n"
       | RStat n ->
	   pr "  py_r = put_stat (r);\n";
	   pr "  free (r);\n"
       | RStatVFS n ->
	   pr "  py_r = put_statvfs (r);\n";
	   pr "  free (r);\n"
       | RHashtable n ->
	   pr "  py_r = put_table (r);\n";
	   pr "  free_strings (r);\n"
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
  generate_header HashStyle LGPLv2;

  pr "\
u\"\"\"Python bindings for libguestfs

import guestfs
g = guestfs.GuestFS ()
g.add_drive (\"guest.img\")
g.launch ()
g.wait_ready ()
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
g.wait_ready ()

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
      let doc = replace_str longdesc "C<guestfs_" "C<g." in
      let doc =
        match fst style with
	| RErr | RInt _ | RInt64 _ | RBool _ | RConstString _
	| RString _ -> doc
	| RStringList _ ->
	    doc ^ "\n\nThis function returns a list of strings."
	| RIntBool _ ->
	    doc ^ "\n\nThis function returns a tuple (int, bool).\n"
	| RPVList _ ->
	    doc ^ "\n\nThis function returns a list of PVs.  Each PV is represented as a dictionary."
	| RVGList _ ->
	    doc ^ "\n\nThis function returns a list of VGs.  Each VG is represented as a dictionary."
	| RLVList _ ->
	    doc ^ "\n\nThis function returns a list of LVs.  Each LV is represented as a dictionary."
	| RStat _ ->
	    doc ^ "\n\nThis function returns a dictionary, with keys matching the various fields in the stat structure."
       | RStatVFS _ ->
	    doc ^ "\n\nThis function returns a dictionary, with keys matching the various fields in the statvfs structure."
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
      let doc = pod2text ~width:60 name doc in
      let doc = List.map (fun line -> replace_str line "\\" "\\\\") doc in
      let doc = String.concat "\n        " doc in

      pr "    def %s " name;
      generate_call_args ~handle:"self" (snd style);
      pr ":\n";
      pr "        u\"\"\"%s\"\"\"\n" doc;
      pr "        return libguestfsmod.%s " name;
      generate_call_args ~handle:"self._o" (snd style);
      pr "\n";
      pr "\n";
  ) all_functions

(* Useful if you need the longdesc POD text as plain text.  Returns a
 * list of lines.
 *
 * This is the slowest thing about autogeneration.
 *)
and pod2text ~width name longdesc =
  let filename, chan = Filename.open_temp_file "gen" ".tmp" in
  fprintf chan "=head1 %s\n\n%s\n" name longdesc;
  close_out chan;
  let cmd = sprintf "pod2text -w %d %s" width (Filename.quote filename) in
  let chan = Unix.open_process_in cmd in
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
  Unix.unlink filename;
  match Unix.close_process_in chan with
  | Unix.WEXITED 0 -> lines
  | Unix.WEXITED i ->
      failwithf "pod2text: process exited with non-zero status (%d)" i
  | Unix.WSIGNALED i | Unix.WSTOPPED i ->
      failwithf "pod2text: process signalled or stopped by signal %d" i

(* Generate ruby bindings. *)
and generate_ruby_c () =
  generate_header CStyle LGPLv2;

  pr "\
#include <stdio.h>
#include <stdlib.h>

#include <ruby.h>

#include \"guestfs.h\"

#include \"extconf.h\"

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
	| String n | FileIn n | FileOut n ->
	    pr "  const char *%s = StringValueCStr (%sv);\n" n n;
	    pr "  if (!%s)\n" n;
	    pr "    rb_raise (rb_eTypeError, \"expected string for parameter %%s of %%s\",\n";
	    pr "              \"%s\", \"%s\");\n" n name
	| OptString n ->
	    pr "  const char *%s = StringValueCStr (%sv);\n" n n
	| StringList n ->
	    pr "  char **%s;" n;
	    pr "  {\n";
	    pr "    int i, len;\n";
	    pr "    len = RARRAY_LEN (%sv);\n" n;
	    pr "    %s = malloc (sizeof (char *) * (len+1));\n" n;
	    pr "    for (i = 0; i < len; ++i) {\n";
	    pr "      VALUE v = rb_ary_entry (%sv, i);\n" n;
	    pr "      %s[i] = StringValueCStr (v);\n" n;
	    pr "    }\n";
	    pr "  }\n";
	| Bool n
	| Int n ->
	    pr "  int %s = NUM2INT (%sv);\n" n n
      ) (snd style);
      pr "\n";

      let error_code =
	match fst style with
	| RErr | RInt _ | RBool _ -> pr "  int r;\n"; "-1"
	| RInt64 _ -> pr "  int64_t r;\n"; "-1"
	| RConstString _ -> pr "  const char *r;\n"; "NULL"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ | RHashtable _ -> pr "  char **r;\n"; "NULL"
	| RIntBool _ -> pr "  struct guestfs_int_bool *r;\n"; "NULL"
	| RPVList n -> pr "  struct guestfs_lvm_pv_list *r;\n"; "NULL"
	| RVGList n -> pr "  struct guestfs_lvm_vg_list *r;\n"; "NULL"
	| RLVList n -> pr "  struct guestfs_lvm_lv_list *r;\n"; "NULL"
	| RStat n -> pr "  struct guestfs_stat *r;\n"; "NULL"
	| RStatVFS n -> pr "  struct guestfs_statvfs *r;\n"; "NULL" in
      pr "\n";

      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";

      List.iter (
	function
	| String _ | FileIn _ | FileOut _ | OptString _ | Bool _ | Int _ -> ()
	| StringList n ->
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
       | RIntBool _ ->
	   pr "  VALUE rv = rb_ary_new2 (2);\n";
	   pr "  rb_ary_push (rv, INT2NUM (r->i));\n";
	   pr "  rb_ary_push (rv, INT2NUM (r->b));\n";
	   pr "  guestfs_free_int_bool (r);\n";
	   pr "  return rv;\n"
       | RPVList n ->
	   generate_ruby_lvm_code "pv" pv_cols
       | RVGList n ->
	   generate_ruby_lvm_code "vg" vg_cols
       | RLVList n ->
	   generate_ruby_lvm_code "lv" lv_cols
       | RStat n ->
	   pr "  VALUE rv = rb_hash_new ();\n";
	   List.iter (
	     function
	     | name, `Int ->
		 pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
	   ) stat_cols;
	   pr "  free (r);\n";
	   pr "  return rv;\n"
       | RStatVFS n ->
	   pr "  VALUE rv = rb_hash_new ();\n";
	   List.iter (
	     function
	     | name, `Int ->
		 pr "  rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->%s));\n" name name
	   ) statvfs_cols;
	   pr "  free (r);\n";
	   pr "  return rv;\n"
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

(* Ruby code to return an LVM struct list. *)
and generate_ruby_lvm_code typ cols =
  pr "  VALUE rv = rb_ary_new2 (r->len);\n";
  pr "  int i;\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    VALUE hv = rb_hash_new ();\n";
  List.iter (
    function
    | name, `String ->
	pr "    rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new2 (r->val[i].%s));\n" name name
    | name, `UUID ->
	pr "    rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_str_new (r->val[i].%s, 32));\n" name name
    | name, `Bytes
    | name, `Int ->
	pr "    rb_hash_aset (rv, rb_str_new2 (\"%s\"), ULL2NUM (r->val[i].%s));\n" name name
    | name, `OptPercent ->
	pr "    rb_hash_aset (rv, rb_str_new2 (\"%s\"), rb_dbl2big (r->val[i].%s));\n" name name
  ) cols;
  pr "    rb_ary_push (rv, hv);\n";
  pr "  }\n";
  pr "  guestfs_free_lvm_%s_list (r);\n" typ;
  pr "  return rv;\n"

(* Generate Java bindings GuestFS.java file. *)
and generate_java_java () =
  generate_header CStyle LGPLv2;

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
      let doc = replace_str longdesc "C<guestfs_" "C<g." in
      let doc =
	if List.mem ProtocolLimitWarning flags then
	  doc ^ "\n\n" ^ protocol_limit_warning
	else doc in
      let doc =
	if List.mem DangerWillRobinson flags then
	  doc ^ "\n\n" ^ danger_will_robinson
	else doc in
      let doc = pod2text ~width:60 name doc in
      let doc = String.concat "\n   * " doc in

      pr "  /**\n";
      pr "   * %s\n" shortdesc;
      pr "   *\n";
      pr "   * %s\n" doc;
      pr "   * @throws LibGuestFSException\n";
      pr "   */\n";
      pr "  ";
      generate_java_prototype ~public:true ~semicolon:false name style;
      pr "\n";
      pr "  {\n";
      pr "    if (g == 0)\n";
      pr "      throw new LibGuestFSException (\"%s: handle is closed\");\n"
	name;
      pr "    ";
      if fst style <> RErr then pr "return ";
      pr "_%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";
      pr "  }\n";
      pr "  ";
      generate_java_prototype ~privat:true ~native:true name style;
      pr "\n";
      pr "\n";
  ) all_functions;

  pr "}\n"

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
   | RConstString _ | RString _ -> pr "String ";
   | RStringList _ -> pr "String[] ";
   | RIntBool _ -> pr "IntBool ";
   | RPVList _ -> pr "PV[] ";
   | RVGList _ -> pr "VG[] ";
   | RLVList _ -> pr "LV[] ";
   | RStat _ -> pr "Stat ";
   | RStatVFS _ -> pr "StatVFS ";
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
      | String n
      | OptString n
      | FileIn n
      | FileOut n ->
	  pr "String %s" n
      | StringList n ->
	  pr "String[] %s" n
      | Bool n ->
	  pr "boolean %s" n
      | Int n ->
	  pr "int %s" n
  ) (snd style);

  pr ")\n";
  pr "    throws LibGuestFSException";
  if semicolon then pr ";"

and generate_java_struct typ cols =
  generate_header CStyle LGPLv2;

  pr "\
package com.redhat.et.libguestfs;

/**
 * Libguestfs %s structure.
 *
 * @author rjones
 * @see GuestFS
 */
public class %s {
" typ typ;

  List.iter (
    function
    | name, `String
    | name, `UUID -> pr "  public String %s;\n" name
    | name, `Bytes
    | name, `Int -> pr "  public long %s;\n" name
    | name, `OptPercent ->
	pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
	pr "  public float %s;\n" name
  ) cols;

  pr "}\n"

and generate_java_c () =
  generate_header CStyle LGPLv2;

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
  return (jlong) g;
}

JNIEXPORT void JNICALL
Java_com_redhat_et_libguestfs_GuestFS__1close
  (JNIEnv *env, jobject obj, jlong jg)
{
  guestfs_h *g = (guestfs_h *) jg;
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
       | RConstString _ | RString _ -> pr "jstring ";
       | RIntBool _ | RStat _ | RStatVFS _ | RHashtable _ ->
	   pr "jobject ";
       | RStringList _ | RPVList _ | RVGList _ | RLVList _ ->
	   pr "jobjectArray ";
      );
      pr "JNICALL\n";
      pr "Java_com_redhat_et_libguestfs_";
      pr "%s" (replace_str ("_" ^ name) "_" "_1");
      pr "\n";
      pr "  (JNIEnv *env, jobject obj, jlong jg";
      List.iter (
	function
	| String n
	| OptString n
	| FileIn n
	| FileOut n ->
	    pr ", jstring j%s" n
	| StringList n ->
	    pr ", jobjectArray j%s" n
	| Bool n ->
	    pr ", jboolean j%s" n
	| Int n ->
	    pr ", jint j%s" n
      ) (snd style);
      pr ")\n";
      pr "{\n";
      pr "  guestfs_h *g = (guestfs_h *) jg;\n";
      let error_code, no_ret =
	match fst style with
	| RErr -> pr "  int r;\n"; "-1", ""
	| RBool _
	| RInt _ -> pr "  int r;\n"; "-1", "0"
	| RInt64 _ -> pr "  int64_t r;\n"; "-1", "0"
	| RConstString _ -> pr "  const char *r;\n"; "NULL", "NULL"
	| RString _ ->
	    pr "  jstring jr;\n";
	    pr "  char *r;\n"; "NULL", "NULL"
	| RStringList _ ->
	    pr "  jobjectArray jr;\n";
	    pr "  int r_len;\n";
	    pr "  jclass cl;\n";
	    pr "  jstring jstr;\n";
	    pr "  char **r;\n"; "NULL", "NULL"
	| RIntBool _ ->
	    pr "  jobject jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  struct guestfs_int_bool *r;\n"; "NULL", "NULL"
	| RStat _ ->
	    pr "  jobject jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  struct guestfs_stat *r;\n"; "NULL", "NULL"
	| RStatVFS _ ->
	    pr "  jobject jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  struct guestfs_statvfs *r;\n"; "NULL", "NULL"
	| RPVList _ ->
	    pr "  jobjectArray jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  jobject jfl;\n";
	    pr "  struct guestfs_lvm_pv_list *r;\n"; "NULL", "NULL"
	| RVGList _ ->
	    pr "  jobjectArray jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  jobject jfl;\n";
	    pr "  struct guestfs_lvm_vg_list *r;\n"; "NULL", "NULL"
	| RLVList _ ->
	    pr "  jobjectArray jr;\n";
	    pr "  jclass cl;\n";
	    pr "  jfieldID fl;\n";
	    pr "  jobject jfl;\n";
	    pr "  struct guestfs_lvm_lv_list *r;\n"; "NULL", "NULL"
	| RHashtable _ -> pr "  char **r;\n"; "NULL", "NULL" in
      List.iter (
	function
	| String n
	| OptString n
	| FileIn n
	| FileOut n ->
	    pr "  const char *%s;\n" n
	| StringList n ->
	    pr "  int %s_len;\n" n;
	    pr "  const char **%s;\n" n
	| Bool n
	| Int n ->
	    pr "  int %s;\n" n
      ) (snd style);

      let needs_i =
	(match fst style with
	 | RStringList _ | RPVList _ | RVGList _ | RLVList _ -> true
	 | RErr _ | RBool _ | RInt _ | RInt64 _ | RConstString _
	 | RString _ | RIntBool _ | RStat _ | RStatVFS _
	 | RHashtable _ -> false) ||
	List.exists (function StringList _ -> true | _ -> false) (snd style) in
      if needs_i then
	pr "  int i;\n";

      pr "\n";

      (* Get the parameters. *)
      List.iter (
	function
	| String n
	| OptString n
	| FileIn n
	| FileOut n ->
	    pr "  %s = (*env)->GetStringUTFChars (env, j%s, NULL);\n" n n
	| StringList n ->
	    pr "  %s_len = (*env)->GetArrayLength (env, j%s);\n" n n;
	    pr "  %s = malloc (sizeof (char *) * (%s_len+1));\n" n n;
	    pr "  for (i = 0; i < %s_len; ++i) {\n" n;
	    pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
	      n;
	    pr "    %s[i] = (*env)->GetStringUTFChars (env, o, NULL);\n" n;
	    pr "  }\n";
	    pr "  %s[%s_len] = NULL;\n" n n;
	| Bool n
	| Int n ->
	    pr "  %s = j%s;\n" n n
      ) (snd style);

      (* Make the call. *)
      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" (snd style);
      pr ";\n";

      (* Release the parameters. *)
      List.iter (
	function
	| String n
	| OptString n
	| FileIn n
	| FileOut n ->
	    pr "  (*env)->ReleaseStringUTFChars (env, j%s, %s);\n" n n
	| StringList n ->
	    pr "  for (i = 0; i < %s_len; ++i) {\n" n;
	    pr "    jobject o = (*env)->GetObjectArrayElement (env, j%s, i);\n"
	      n;
	    pr "    (*env)->ReleaseStringUTFChars (env, o, %s[i]);\n" n;
	    pr "  }\n";
	    pr "  free (%s);\n" n
	| Bool n
	| Int n -> ()
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
       | RIntBool _ ->
	   pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/IntBool\");\n";
	   pr "  jr = (*env)->AllocObject (env, cl);\n";
	   pr "  fl = (*env)->GetFieldID (env, cl, \"i\", \"I\");\n";
	   pr "  (*env)->SetIntField (env, jr, fl, r->i);\n";
	   pr "  fl = (*env)->GetFieldID (env, cl, \"i\", \"Z\");\n";
	   pr "  (*env)->SetBooleanField (env, jr, fl, r->b);\n";
	   pr "  guestfs_free_int_bool (r);\n";
	   pr "  return jr;\n"
       | RStat _ ->
	   pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/Stat\");\n";
	   pr "  jr = (*env)->AllocObject (env, cl);\n";
	   List.iter (
	     function
	     | name, `Int ->
		 pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n"
		   name;
		 pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
	   ) stat_cols;
	   pr "  free (r);\n";
	   pr "  return jr;\n"
       | RStatVFS _ ->
	   pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/StatVFS\");\n";
	   pr "  jr = (*env)->AllocObject (env, cl);\n";
	   List.iter (
	     function
	     | name, `Int ->
		 pr "  fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n"
		   name;
		 pr "  (*env)->SetLongField (env, jr, fl, r->%s);\n" name;
	   ) statvfs_cols;
	   pr "  free (r);\n";
	   pr "  return jr;\n"
       | RPVList _ ->
	   generate_java_lvm_return "pv" "PV" pv_cols
       | RVGList _ ->
	   generate_java_lvm_return "vg" "VG" vg_cols
       | RLVList _ ->
	   generate_java_lvm_return "lv" "LV" lv_cols
       | RHashtable _ ->
	   (* XXX *)
	   pr "  throw_exception (env, \"%s: internal error: please let us know how to make a Java HashMap from JNI bindings!\");\n" name;
	   pr "  return NULL;\n"
      );

      pr "}\n";
      pr "\n"
  ) all_functions

and generate_java_lvm_return typ jtyp cols =
  pr "  cl = (*env)->FindClass (env, \"com/redhat/et/libguestfs/%s\");\n" jtyp;
  pr "  jr = (*env)->NewObjectArray (env, r->len, cl, NULL);\n";
  pr "  for (i = 0; i < r->len; ++i) {\n";
  pr "    jfl = (*env)->AllocObject (env, cl);\n";
  List.iter (
    function
    | name, `String ->
	pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
	pr "    (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, r->val[i].%s));\n" name;
    | name, `UUID ->
	pr "    {\n";
	pr "      char s[33];\n";
	pr "      memcpy (s, r->val[i].%s, 32);\n" name;
	pr "      s[32] = 0;\n";
	pr "      fl = (*env)->GetFieldID (env, cl, \"%s\", \"Ljava/lang/String;\");\n" name;
	pr "      (*env)->SetObjectField (env, jfl, fl, (*env)->NewStringUTF (env, s));\n";
	pr "    }\n";
    | name, (`Bytes|`Int) ->
	pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"J\");\n" name;
	pr "    (*env)->SetLongField (env, jfl, fl, r->val[i].%s);\n" name;
    | name, `OptPercent ->
	pr "    fl = (*env)->GetFieldID (env, cl, \"%s\", \"F\");\n" name;
	pr "    (*env)->SetFloatField (env, jfl, fl, r->val[i].%s);\n" name;
  ) cols;
  pr "    (*env)->SetObjectArrayElement (env, jfl, i, jfl);\n";
  pr "  }\n";
  pr "  guestfs_free_lvm_%s_list (r);\n" typ;
  pr "  return jr;\n"

let output_to filename =
  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  let close () =
    close_out !chan;
    chan := stdout;
    Unix.rename filename_new filename;
    printf "written %s\n%!" filename;
  in
  close

(* Main program. *)
let () =
  check_functions ();

  if not (Sys.file_exists "configure.ac") then (
    eprintf "\
You are probably running this from the wrong directory.
Run it from the top source directory using the command
  src/generator.ml
";
    exit 1
  );

  let close = output_to "src/guestfs_protocol.x" in
  generate_xdr ();
  close ();

  let close = output_to "src/guestfs-structs.h" in
  generate_structs_h ();
  close ();

  let close = output_to "src/guestfs-actions.h" in
  generate_actions_h ();
  close ();

  let close = output_to "src/guestfs-actions.c" in
  generate_client_actions ();
  close ();

  let close = output_to "daemon/actions.h" in
  generate_daemon_actions_h ();
  close ();

  let close = output_to "daemon/stubs.c" in
  generate_daemon_actions ();
  close ();

  let close = output_to "tests.c" in
  generate_tests ();
  close ();

  let close = output_to "fish/cmds.c" in
  generate_fish_cmds ();
  close ();

  let close = output_to "fish/completion.c" in
  generate_fish_completion ();
  close ();

  let close = output_to "guestfs-structs.pod" in
  generate_structs_pod ();
  close ();

  let close = output_to "guestfs-actions.pod" in
  generate_actions_pod ();
  close ();

  let close = output_to "guestfish-actions.pod" in
  generate_fish_actions_pod ();
  close ();

  let close = output_to "ocaml/guestfs.mli" in
  generate_ocaml_mli ();
  close ();

  let close = output_to "ocaml/guestfs.ml" in
  generate_ocaml_ml ();
  close ();

  let close = output_to "ocaml/guestfs_c_actions.c" in
  generate_ocaml_c ();
  close ();

  let close = output_to "perl/Guestfs.xs" in
  generate_perl_xs ();
  close ();

  let close = output_to "perl/lib/Sys/Guestfs.pm" in
  generate_perl_pm ();
  close ();

  let close = output_to "python/guestfs-py.c" in
  generate_python_c ();
  close ();

  let close = output_to "python/guestfs.py" in
  generate_python_py ();
  close ();

  let close = output_to "ruby/ext/guestfs/_guestfs.c" in
  generate_ruby_c ();
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/GuestFS.java" in
  generate_java_java ();
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/PV.java" in
  generate_java_struct "PV" pv_cols;
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/VG.java" in
  generate_java_struct "VG" vg_cols;
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/LV.java" in
  generate_java_struct "LV" lv_cols;
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/Stat.java" in
  generate_java_struct "Stat" stat_cols;
  close ();

  let close = output_to "java/com/redhat/et/libguestfs/StatVFS.java" in
  generate_java_struct "StatVFS" statvfs_cols;
  close ();

  let close = output_to "java/com_redhat_et_libguestfs_GuestFS.c" in
  generate_java_c ();
  close ();
