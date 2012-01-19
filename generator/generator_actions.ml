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

(* Note about long descriptions: When referring to another
 * action, use the format C<guestfs_other> (ie. the full name of
 * the C function).  This will be replaced as appropriate in other
 * language bindings.
 *
 * Apart from that, long descriptions are just perldoc paragraphs.
 *)

open Generator_types
open Generator_utils

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
  BufferIn "bufferin";
]

let test_all_optargs = [
  OBool   "obool";
  OInt    "oint";
  OInt64  "oint64";
  OString "ostring"
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
  "test0rbufferout",   RBufferOut "valout";
]

let test_functions = [
  ("test0", (RErr, test_all_args, test_all_optargs), -1,
   [NotInFish; NotInDocs; Cancellable],
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
      [(name, (ret, [String "val"], []), -1, [NotInFish; NotInDocs],
        [],
        "internal test function - do not use",
        "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

It converts string C<val> to the return type.

You probably don't want to call this function.");
       (name ^ "err", (ret, [], []), -1, [NotInFish; NotInDocs],
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
  ("launch", (RErr, [], []), -1, [FishAlias "run"; Progress],
   [],
   "launch the qemu subprocess",
   "\
Internally libguestfs is implemented by running a virtual machine
using L<qemu(1)>.

You should call this after configuring the handle
(eg. adding drives) but before performing any actions.");

  ("wait_ready", (RErr, [], []), -1, [NotInFish; DeprecatedBy "launch"],
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

  ("kill_subprocess", (RErr, [], []), -1, [],
   [],
   "kill the qemu subprocess",
   "\
This kills the qemu subprocess.  You should never need to call this.");

  ("add_drive", (RErr, [String "filename"], []), -1, [],
   [],
   "add an image to examine or modify",
   "\
This function is the equivalent of calling C<guestfs_add_drive_opts>
with no optional parameters, so the disk is added writable, with
the format being detected automatically.

Automatic detection of the format opens you up to a potential
security hole when dealing with untrusted raw-format images.
See CVE-2010-3851 and RHBZ#642934.  Specifying the format closes
this security hole.  Therefore you should think about replacing
calls to this function with calls to C<guestfs_add_drive_opts>,
and specifying the format.");

  ("add_cdrom", (RErr, [String "filename"], []), -1, [DeprecatedBy "add_drive_opts"],
   [],
   "add a CD-ROM disk image to examine",
   "\
This function adds a virtual CD-ROM disk image to the guest.

This is equivalent to the qemu parameter I<-cdrom filename>.

Notes:

=over 4

=item *

This call checks for the existence of C<filename>.  This
stops you from specifying other types of drive which are supported
by qemu such as C<nbd:> and C<http:> URLs.  To specify those, use
the general C<guestfs_config> call instead.

=item *

If you just want to add an ISO file (often you use this as an
efficient way to transfer large files into the guest), then you
should probably use C<guestfs_add_drive_ro> instead.

=back");

  ("add_drive_ro", (RErr, [String "filename"], []), -1, [FishAlias "add-ro"],
   [],
   "add a drive in snapshot mode (read-only)",
   "\
This function is the equivalent of calling C<guestfs_add_drive_opts>
with the optional parameter C<GUESTFS_ADD_DRIVE_OPTS_READONLY> set to 1,
so the disk is added read-only, with the format being detected
automatically.");

  ("config", (RErr, [String "qemuparam"; OptString "qemuvalue"], []), -1, [],
   [],
   "add qemu parameters",
   "\
This can be used to add arbitrary qemu command line parameters
of the form I<-param value>.  Actually it's not quite arbitrary - we
prevent you from setting some parameters which would interfere with
parameters that we use.

The first character of C<param> string must be a C<-> (dash).

C<value> can be NULL.");

  ("set_qemu", (RErr, [OptString "qemu"], []), -1, [FishAlias "qemu"],
   [],
   "set the qemu binary",
   "\
Set the qemu binary that we will use.

The default is chosen when the library was compiled by the
configure script.

You can also override this by setting the C<LIBGUESTFS_QEMU>
environment variable.

Setting C<qemu> to C<NULL> restores the default qemu binary.

Note that you should call this function as early as possible
after creating the handle.  This is because some pre-launch
operations depend on testing qemu features (by running C<qemu -help>).
If the qemu binary changes, we don't retest features, and
so you might see inconsistent results.  Using the environment
variable C<LIBGUESTFS_QEMU> is safest of all since that picks
the qemu binary at the same time as the handle is created.");

  ("get_qemu", (RConstString "qemu", [], []), -1, [],
   [InitNone, Always, TestRun (
      [["get_qemu"]])],
   "get the qemu binary",
   "\
Return the current qemu binary.

This is always non-NULL.  If it wasn't set already, then this will
return the default qemu binary name.");

  ("set_path", (RErr, [OptString "searchpath"], []), -1, [FishAlias "path"],
   [],
   "set the search path",
   "\
Set the path that libguestfs searches for kernel and initrd.img.

The default is C<$libdir/guestfs> unless overridden by setting
C<LIBGUESTFS_PATH> environment variable.

Setting C<path> to C<NULL> restores the default path.");

  ("get_path", (RConstString "path", [], []), -1, [],
   [InitNone, Always, TestRun (
      [["get_path"]])],
   "get the search path",
   "\
Return the current search path.

This is always non-NULL.  If it wasn't set already, then this will
return the default path.");

  ("set_append", (RErr, [OptString "append"], []), -1, [FishAlias "append"],
   [],
   "add options to kernel command line",
   "\
This function is used to add additional options to the
guest kernel command line.

The default is C<NULL> unless overridden by setting
C<LIBGUESTFS_APPEND> environment variable.

Setting C<append> to C<NULL> means I<no> additional options
are passed (libguestfs always adds a few of its own).");

  ("get_append", (RConstOptString "append", [], []), -1, [],
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

  ("set_autosync", (RErr, [Bool "autosync"], []), -1, [FishAlias "autosync"],
   [],
   "set autosync mode",
   "\
If C<autosync> is true, this enables autosync.  Libguestfs will make a
best effort attempt to make filesystems consistent and synchronized
when the handle is closed
(also if the program exits without closing handles).

This is enabled by default (since libguestfs 1.5.24, previously it was
disabled by default).");

  ("get_autosync", (RBool "autosync", [], []), -1, [],
   [InitNone, Always, TestOutputTrue (
      [["get_autosync"]])],
   "get autosync mode",
   "\
Get the autosync flag.");

  ("set_verbose", (RErr, [Bool "verbose"], []), -1, [FishAlias "verbose"],
   [],
   "set verbose mode",
   "\
If C<verbose> is true, this turns on verbose messages.

Verbose messages are disabled unless the environment variable
C<LIBGUESTFS_DEBUG> is defined and set to C<1>.

Verbose messages are normally sent to C<stderr>, unless you
register a callback to send them somewhere else (see
C<guestfs_set_event_callback>).");

  ("get_verbose", (RBool "verbose", [], []), -1, [],
   [],
   "get verbose mode",
   "\
This returns the verbose messages flag.");

  ("is_ready", (RBool "ready", [], []), -1, [],
   [InitNone, Always, TestOutputTrue (
      [["is_ready"]])],
   "is ready to accept commands",
   "\
This returns true iff this handle is ready to accept commands
(in the C<READY> state).

For more information on states, see L<guestfs(3)>.");

  ("is_config", (RBool "config", [], []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_config"]])],
   "is in configuration state",
   "\
This returns true iff this handle is being configured
(in the C<CONFIG> state).

For more information on states, see L<guestfs(3)>.");

  ("is_launching", (RBool "launching", [], []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_launching"]])],
   "is launching subprocess",
   "\
This returns true iff this handle is launching the subprocess
(in the C<LAUNCHING> state).

For more information on states, see L<guestfs(3)>.");

  ("is_busy", (RBool "busy", [], []), -1, [],
   [InitNone, Always, TestOutputFalse (
      [["is_busy"]])],
   "is busy processing a command",
   "\
This returns true iff this handle is busy processing a command
(in the C<BUSY> state).

For more information on states, see L<guestfs(3)>.");

  ("get_state", (RInt "state", [], []), -1, [],
   [],
   "get the current state",
   "\
This returns the current state as an opaque integer.  This is
only useful for printing debug and internal error messages.

For more information on states, see L<guestfs(3)>.");

  ("set_memsize", (RErr, [Int "memsize"], []), -1, [FishAlias "memsize"],
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

  ("get_memsize", (RInt "memsize", [], []), -1, [],
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

  ("get_pid", (RInt "pid", [], []), -1, [FishAlias "pid"],
   [InitNone, Always, TestOutputIntOp (
      [["get_pid"]], ">=", 1)],
   "get PID of qemu subprocess",
   "\
Return the process ID of the qemu subprocess.  If there is no
qemu subprocess, then this will return an error.

This is an internal call used for debugging and testing.");

  ("version", (RStruct ("version", "version"), [], []), -1, [],
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
number.  From C code you can use dynamic linker functions
to find out if this symbol exists (if it doesn't, then
it's an earlier version).

The call returns a structure with four elements.  The first
three (C<major>, C<minor> and C<release>) are numbers and
correspond to the usual version triplet.  The fourth element
(C<extra>) is a string and is normally empty, but may be
used for distro-specific information.

To construct the original version string:
C<$major.$minor.$release$extra>

See also: L<guestfs(3)/LIBGUESTFS VERSION NUMBERS>.

I<Note:> Don't use this call to test for availability
of features.  In enterprise distributions we backport
features from later versions into earlier versions,
making this an unreliable way to test for features.
Use C<guestfs_available> instead.");

  ("set_selinux", (RErr, [Bool "selinux"], []), -1, [FishAlias "selinux"],
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

  ("get_selinux", (RBool "selinux", [], []), -1, [],
   [],
   "get SELinux enabled flag",
   "\
This returns the current setting of the selinux flag which
is passed to the appliance at boot time.  See C<guestfs_set_selinux>.

For more information on the architecture of libguestfs,
see L<guestfs(3)>.");

  ("set_trace", (RErr, [Bool "trace"], []), -1, [FishAlias "trace"],
   [InitNone, Always, TestOutputFalse (
      [["set_trace"; "false"];
       ["get_trace"]])],
   "enable or disable command traces",
   "\
If the command trace flag is set to 1, then libguestfs
calls, parameters and return values are traced.

If you want to trace C API calls into libguestfs (and
other libraries) then possibly a better way is to use
the external ltrace(1) command.

Command traces are disabled unless the environment variable
C<LIBGUESTFS_TRACE> is defined and set to C<1>.

Trace messages are normally sent to C<stderr>, unless you
register a callback to send them somewhere else (see
C<guestfs_set_event_callback>).");

  ("get_trace", (RBool "trace", [], []), -1, [],
   [],
   "get command trace enabled flag",
   "\
Return the command trace flag.");

  ("set_direct", (RErr, [Bool "direct"], []), -1, [FishAlias "direct"],
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

  ("get_direct", (RBool "direct", [], []), -1, [],
   [],
   "get direct appliance mode flag",
   "\
Return the direct appliance mode flag.");

  ("set_recovery_proc", (RErr, [Bool "recoveryproc"], []), -1, [FishAlias "recovery-proc"],
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

  ("get_recovery_proc", (RBool "recoveryproc", [], []), -1, [],
   [],
   "get recovery process enabled flag",
   "\
Return the recovery process enabled flag.");

  ("add_drive_with_if", (RErr, [String "filename"; String "iface"], []), -1, [DeprecatedBy "add_drive_opts"],
   [],
   "add a drive specifying the QEMU block emulation to use",
   "\
This is the same as C<guestfs_add_drive> but it allows you
to specify the QEMU interface emulation to use at run time.");

  ("add_drive_ro_with_if", (RErr, [String "filename"; String "iface"], []), -1, [DeprecatedBy "add_drive_opts"],
   [],
   "add a drive read-only specifying the QEMU block emulation to use",
   "\
This is the same as C<guestfs_add_drive_ro> but it allows you
to specify the QEMU interface emulation to use at run time.");

  ("file_architecture", (RString "arch", [Pathname "filename"], []), -1, [],
   [InitISOFS, Always, TestOutput (
      [["file_architecture"; "/bin-i586-dynamic"]], "i386");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/bin-sparc-dynamic"]], "sparc");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/bin-win32.exe"]], "i386");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/bin-win64.exe"]], "x86_64");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/bin-x86_64-dynamic"]], "x86_64");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/lib-i586.so"]], "i386");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/lib-sparc.so"]], "sparc");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/lib-win32.dll"]], "i386");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/lib-win64.dll"]], "x86_64");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/lib-x86_64.so"]], "x86_64");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/initrd-x86_64.img"]], "x86_64");
    InitISOFS, Always, TestOutput (
      [["file_architecture"; "/initrd-x86_64.img.gz"]], "x86_64");],
   "detect the architecture of a binary file",
   "\
This detects the architecture of the binary C<filename>,
and returns it if known.

Currently defined architectures are:

=over 4

=item \"i386\"

This string is returned for all 32 bit i386, i486, i586, i686 binaries
irrespective of the precise processor requirements of the binary.

=item \"x86_64\"

64 bit x86-64.

=item \"sparc\"

32 bit SPARC.

=item \"sparc64\"

64 bit SPARC V9 and above.

=item \"ia64\"

Intel Itanium.

=item \"ppc\"

32 bit Power PC.

=item \"ppc64\"

64 bit Power PC.

=back

Libguestfs may return other architecture strings in future.

The function works on at least the following types of files:

=over 4

=item *

many types of Un*x and Linux binary

=item *

many types of Un*x and Linux shared library

=item *

Windows Win32 and Win64 binaries

=item *

Windows Win32 and Win64 DLLs

Win32 binaries and DLLs return C<i386>.

Win64 binaries and DLLs return C<x86_64>.

=item *

Linux kernel modules

=item *

Linux new-style initrd images

=item *

some non-x86 Linux vmlinuz kernels

=back

What it can't do currently:

=over 4

=item *

static libraries (libfoo.a)

=item *

Linux old-style initrd as compressed ext2 filesystem (RHEL 3)

=item *

x86 Linux vmlinuz kernels

x86 vmlinuz images (bzImage format) consist of a mix of 16-, 32- and
compressed code, and are horribly hard to unpack.  If you want to find
the architecture of a kernel, use the architecture of the associated
initrd or kernel module(s) instead.

=back");

  ("inspect_os", (RStringList "roots", [], []), -1, [],
   [],
   "inspect disk and return list of operating systems found",
   "\
This function uses other libguestfs functions and certain
heuristics to inspect the disk(s) (usually disks belonging to
a virtual machine), looking for operating systems.

The list returned is empty if no operating systems were found.

If one operating system was found, then this returns a list with
a single element, which is the name of the root filesystem of
this operating system.  It is also possible for this function
to return a list containing more than one element, indicating
a dual-boot or multi-boot virtual machine, with each element being
the root filesystem of one of the operating systems.

You can pass the root string(s) returned to other
C<guestfs_inspect_get_*> functions in order to query further
information about each operating system, such as the name
and version.

This function uses other libguestfs features such as
C<guestfs_mount_ro> and C<guestfs_umount_all> in order to mount
and unmount filesystems and look at the contents.  This should
be called with no disks currently mounted.  The function may also
use Augeas, so any existing Augeas handle will be closed.

This function cannot decrypt encrypted disks.  The caller
must do that first (supplying the necessary keys) if the
disk is encrypted.

Please read L<guestfs(3)/INSPECTION> for more details.

See also C<guestfs_list_filesystems>.");

  ("inspect_get_type", (RString "name", [Device "root"], []), -1, [],
   [],
   "get type of inspected operating system",
   "\
This returns the type of the inspected operating system.
Currently defined types are:

=over 4

=item \"linux\"

Any Linux-based operating system.

=item \"windows\"

Any Microsoft Windows operating system.

=item \"freebsd\"

FreeBSD.

=item \"netbsd\"

NetBSD.

=item \"hurd\"

GNU/Hurd.

=item \"unknown\"

The operating system type could not be determined.

=back

Future versions of libguestfs may return other strings here.
The caller should be prepared to handle any string.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_arch", (RString "arch", [Device "root"], []), -1, [],
   [],
   "get architecture of inspected operating system",
   "\
This returns the architecture of the inspected operating system.
The possible return values are listed under
C<guestfs_file_architecture>.

If the architecture could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_distro", (RString "distro", [Device "root"], []), -1, [],
   [],
   "get distro of inspected operating system",
   "\
This returns the distro (distribution) of the inspected operating
system.

Currently defined distros are:

=over 4

=item \"archlinux\"

Arch Linux.

=item \"centos\"

CentOS.

=item \"debian\"

Debian.

=item \"fedora\"

Fedora.

=item \"gentoo\"

Gentoo.

=item \"linuxmint\"

Linux Mint.

=item \"mageia\"

Mageia.

=item \"mandriva\"

Mandriva.

=item \"meego\"

MeeGo.

=item \"opensuse\"

OpenSUSE.

=item \"pardus\"

Pardus.

=item \"redhat-based\"

Some Red Hat-derived distro.

=item \"rhel\"

Red Hat Enterprise Linux.

=item \"scientificlinux\"

Scientific Linux.

=item \"slackware\"

Slackware.

=item \"ttylinux\"

ttylinux.

=item \"ubuntu\"

Ubuntu.

=item \"unknown\"

The distro could not be determined.

=item \"windows\"

Windows does not have distributions.  This string is
returned if the OS type is Windows.

=back

Future versions of libguestfs may return other strings here.
The caller should be prepared to handle any string.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_major_version", (RInt "major", [Device "root"], []), -1, [],
   [],
   "get major version of inspected operating system",
   "\
This returns the major version number of the inspected operating
system.

Windows uses a consistent versioning scheme which is I<not>
reflected in the popular public names used by the operating system.
Notably the operating system known as \"Windows 7\" is really
version 6.1 (ie. major = 6, minor = 1).  You can find out the
real versions corresponding to releases of Windows by consulting
Wikipedia or MSDN.

If the version could not be determined, then C<0> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_minor_version", (RInt "minor", [Device "root"], []), -1, [],
   [],
   "get minor version of inspected operating system",
   "\
This returns the minor version number of the inspected operating
system.

If the version could not be determined, then C<0> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_major_version>.");

  ("inspect_get_product_name", (RString "product", [Device "root"], []), -1, [],
   [],
   "get product name of inspected operating system",
   "\
This returns the product name of the inspected operating
system.  The product name is generally some freeform string
which can be displayed to the user, but should not be
parsed by programs.

If the product name could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_mountpoints", (RHashtable "mountpoints", [Device "root"], []), -1, [],
   [],
   "get mountpoints of inspected operating system",
   "\
This returns a hash of where we think the filesystems
associated with this operating system should be mounted.
Callers should note that this is at best an educated guess
made by reading configuration files such as C</etc/fstab>.
I<In particular note> that this may return filesystems
which are non-existent or not mountable and callers should
be prepared to handle or ignore failures if they try to
mount them.

Each element in the returned hashtable has a key which
is the path of the mountpoint (eg. C</boot>) and a value
which is the filesystem that would be mounted there
(eg. C</dev/sda1>).

Non-mounted devices such as swap devices are I<not>
returned in this list.

For operating systems like Windows which still use drive
letters, this call will only return an entry for the first
drive \"mounted on\" C</>.  For information about the
mapping of drive letters to partitions, see
C<guestfs_inspect_get_drive_mappings>.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_filesystems>.");

  ("inspect_get_filesystems", (RStringList "filesystems", [Device "root"], []), -1, [],
   [],
   "get filesystems associated with inspected operating system",
   "\
This returns a list of all the filesystems that we think
are associated with this operating system.  This includes
the root filesystem, other ordinary filesystems, and
non-mounted devices like swap partitions.

In the case of a multi-boot virtual machine, it is possible
for a filesystem to be shared between operating systems.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_mountpoints>.");

  ("set_network", (RErr, [Bool "network"], []), -1, [FishAlias "network"],
   [],
   "set enable network flag",
   "\
If C<network> is true, then the network is enabled in the
libguestfs appliance.  The default is false.

This affects whether commands are able to access the network
(see L<guestfs(3)/RUNNING COMMANDS>).

You must call this before calling C<guestfs_launch>, otherwise
it has no effect.");

  ("get_network", (RBool "network", [], []), -1, [],
   [],
   "get enable network flag",
   "\
This returns the enable network flag.");

  ("list_filesystems", (RHashtable "fses", [], []), -1, [],
   [],
   "list filesystems",
   "\
This inspection command looks for filesystems on partitions,
block devices and logical volumes, returning a list of devices
containing filesystems and their type.

The return value is a hash, where the keys are the devices
containing filesystems, and the values are the filesystem types.
For example:

 \"/dev/sda1\" => \"ntfs\"
 \"/dev/sda2\" => \"ext2\"
 \"/dev/vg_guest/lv_root\" => \"ext4\"
 \"/dev/vg_guest/lv_swap\" => \"swap\"

The value can have the special value \"unknown\", meaning the
content of the device is undetermined or empty.
\"swap\" means a Linux swap partition.

This command runs other libguestfs commands, which might include
C<guestfs_mount> and C<guestfs_umount>, and therefore you should
use this soon after launch and only when nothing is mounted.

Not all of the filesystems returned will be mountable.  In
particular, swap partitions are returned in the list.  Also
this command does not check that each filesystem
found is valid and mountable, and some filesystems might
be mountable but require special options.  Filesystems may
not all belong to a single logical operating system
(use C<guestfs_inspect_os> to look for OSes).");

  ("add_drive_opts", (RErr, [String "filename"], [OBool "readonly"; OString "format"; OString "iface"; OString "name"]), -1, [FishAlias "add"],
   [],
   "add an image to examine or modify",
   "\
This function adds a virtual machine disk image C<filename> to
libguestfs.  The first time you call this function, the disk
appears as C</dev/sda>, the second time as C</dev/sdb>, and
so on.

You don't necessarily need to be root when using libguestfs.  However
you obviously do need sufficient permissions to access the filename
for whatever operations you want to perform (ie. read access if you
just want to read the image or write access if you want to modify the
image).

This call checks that C<filename> exists.

The optional arguments are:

=over 4

=item C<readonly>

If true then the image is treated as read-only.  Writes are still
allowed, but they are stored in a temporary snapshot overlay which
is discarded at the end.  The disk that you add is not modified.

=item C<format>

This forces the image format.  If you omit this (or use C<guestfs_add_drive>
or C<guestfs_add_drive_ro>) then the format is automatically detected.
Possible formats include C<raw> and C<qcow2>.

Automatic detection of the format opens you up to a potential
security hole when dealing with untrusted raw-format images.
See CVE-2010-3851 and RHBZ#642934.  Specifying the format closes
this security hole.

=item C<iface>

This rarely-used option lets you emulate the behaviour of the
deprecated C<guestfs_add_drive_with_if> call (q.v.)

=item C<name>

The name the drive had in the original guest, e.g. /dev/sdb. This is used as a
hint to the guest inspection process if it is available.

=back");

  ("inspect_get_windows_systemroot", (RString "systemroot", [Device "root"], []), -1, [],
   [],
   "get Windows systemroot of inspected operating system",
   "\
This returns the Windows systemroot of the inspected guest.
The systemroot is a directory path such as C</WINDOWS>.

This call assumes that the guest is Windows and that the
systemroot could be determined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_roots", (RStringList "roots", [], []), -1, [],
   [],
   "return list of operating systems found by last inspection",
   "\
This function is a convenient way to get the list of root
devices, as returned from a previous call to C<guestfs_inspect_os>,
but without redoing the whole inspection process.

This returns an empty list if either no root devices were
found or the caller has not called C<guestfs_inspect_os>.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("debug_cmdline", (RStringList "cmdline", [], []), -1, [NotInDocs],
   [],
   "debug the QEMU command line (internal use only)",
   "\
This returns the internal QEMU command line.  'debug' commands are
not part of the formal API and can be removed or changed at any time.");

  ("debug_drives", (RStringList "cmdline", [], []), -1, [NotInDocs],
   [],
   "debug the drives (internal use only)",
   "\
This returns the internal list of drives.  'debug' commands are
not part of the formal API and can be removed or changed at any time.");

  ("add_domain", (RInt "nrdisks", [String "dom"], [OString "libvirturi"; OBool "readonly"; OString "iface"; OBool "live"; OBool "allowuuid"; OString "readonlydisk"]), -1, [FishAlias "domain"],
   [],
   "add the disk(s) from a named libvirt domain",
   "\
This function adds the disk(s) attached to the named libvirt
domain C<dom>.  It works by connecting to libvirt, requesting
the domain and domain XML from libvirt, parsing it for disks,
and calling C<guestfs_add_drive_opts> on each one.

The number of disks added is returned.  This operation is atomic:
if an error is returned, then no disks are added.

This function does some minimal checks to make sure the libvirt
domain is not running (unless C<readonly> is true).  In a future
version we will try to acquire the libvirt lock on each disk.

Disks must be accessible locally.  This often means that adding disks
from a remote libvirt connection (see L<http://libvirt.org/remote.html>)
will fail unless those disks are accessible via the same device path
locally too.

The optional C<libvirturi> parameter sets the libvirt URI
(see L<http://libvirt.org/uri.html>).  If this is not set then
we connect to the default libvirt URI (or one set through an
environment variable, see the libvirt documentation for full
details).

The optional C<live> flag controls whether this call will try
to connect to a running virtual machine C<guestfsd> process if
it sees a suitable E<lt>channelE<gt> element in the libvirt
XML definition.  The default (if the flag is omitted) is never
to try.  See L<guestfs(3)/ATTACHING TO RUNNING DAEMONS> for more
information.

If the C<allowuuid> flag is true (default is false) then a UUID
I<may> be passed instead of the domain name.  The C<dom> string is
treated as a UUID first and looked up, and if that lookup fails
then we treat C<dom> as a name as usual.

The optional C<readonlydisk> parameter controls what we do for
disks which are marked E<lt>readonly/E<gt> in the libvirt XML.
Possible values are:

=over 4

=item readonlydisk = \"error\"

If C<readonly> is false:

The whole call is aborted with an error if any disk with
the E<lt>readonly/E<gt> flag is found.

If C<readonly> is true:

Disks with the E<lt>readonly/E<gt> flag are added read-only.

=item readonlydisk = \"read\"

If C<readonly> is false:

Disks with the E<lt>readonly/E<gt> flag are added read-only.
Other disks are added read/write.

If C<readonly> is true:

Disks with the E<lt>readonly/E<gt> flag are added read-only.

=item readonlydisk = \"write\" (default)

If C<readonly> is false:

Disks with the E<lt>readonly/E<gt> flag are added read/write.

If C<readonly> is true:

Disks with the E<lt>readonly/E<gt> flag are added read-only.

=item readonlydisk = \"ignore\"

If C<readonly> is true or false:

Disks with the E<lt>readonly/E<gt> flag are skipped.

=back

The other optional parameters are passed directly through to
C<guestfs_add_drive_opts>.");

(*
This interface is not quite baked yet. -- RWMJ 2010-11-11
  ("add_libvirt_dom", (RInt "nrdisks", [Pointer ("virDomainPtr", "dom")], [Bool "readonly"; String "iface"; Bool "live"; String "readonlydisk"]), -1, [NotInFish],
   [],
   "add the disk(s) from a libvirt domain",
   "\
This function adds the disk(s) attached to the libvirt domain C<dom>.
It works by requesting the domain XML from libvirt, parsing it for
disks, and calling C<guestfs_add_drive_opts> on each one.

In the C API we declare C<void *dom>, but really it has type
C<virDomainPtr dom>.  This is so we don't need E<lt>libvirt.hE<gt>.

The number of disks added is returned.  This operation is atomic:
if an error is returned, then no disks are added.

This function does some minimal checks to make sure the libvirt
domain is not running (unless C<readonly> is true).  In a future
version we will try to acquire the libvirt lock on each disk.

Disks must be accessible locally.  This often means that adding disks
from a remote libvirt connection (see L<http://libvirt.org/remote.html>)
will fail unless those disks are accessible via the same device path
locally too.

The optional C<live> flag controls whether this call will try
to connect to a running virtual machine C<guestfsd> process if
it sees a suitable E<lt>channelE<gt> element in the libvirt
XML definition.  The default (if the flag is omitted) is never
to try.  See L<guestfs(3)/ATTACHING TO RUNNING DAEMONS> for more
information.

The optional C<readonlydisk> parameter controls what we do for
disks which are marked E<lt>readonly/E<gt> in the libvirt XML.
See C<guestfs_add_domain> for possible values.

The other optional parameters are passed directly through to
C<guestfs_add_drive_opts>.");
*)

  ("inspect_get_package_format", (RString "packageformat", [Device "root"], []), -1, [],
   [],
   "get package format used by the operating system",
   "\
This function and C<guestfs_inspect_get_package_management> return
the package format and package management tool used by the
inspected operating system.  For example for Fedora these
functions would return C<rpm> (package format) and
C<yum> (package management).

This returns the string C<unknown> if we could not determine the
package format I<or> if the operating system does not have
a real packaging system (eg. Windows).

Possible strings include:
C<rpm>, C<deb>, C<ebuild>, C<pisi>, C<pacman>, C<pkgsrc>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_package_management", (RString "packagemanagement", [Device "root"], []), -1, [],
   [],
   "get package management tool used by the operating system",
   "\
C<guestfs_inspect_get_package_format> and this function return
the package format and package management tool used by the
inspected operating system.  For example for Fedora these
functions would return C<rpm> (package format) and
C<yum> (package management).

This returns the string C<unknown> if we could not determine the
package management tool I<or> if the operating system does not have
a real packaging system (eg. Windows).

Possible strings include: C<yum>, C<up2date>,
C<apt> (for all Debian derivatives),
C<portage>, C<pisi>, C<pacman>, C<urpmi>, C<zypper>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_list_applications", (RStructList ("applications", "application"), [Device "root"], []), -1, [],
   [],
   "get list of applications installed in the operating system",
   "\
Return the list of applications installed in the operating system.

I<Note:> This call works differently from other parts of the
inspection API.  You have to call C<guestfs_inspect_os>, then
C<guestfs_inspect_get_mountpoints>, then mount up the disks,
before calling this.  Listing applications is a significantly
more difficult operation which requires access to the full
filesystem.  Also note that unlike the other
C<guestfs_inspect_get_*> calls which are just returning
data cached in the libguestfs handle, this call actually reads
parts of the mounted filesystems during the call.

This returns an empty list if the inspection code was not able
to determine the list of applications.

The application structure contains the following fields:

=over 4

=item C<app_name>

The name of the application.  For Red Hat-derived and Debian-derived
Linux guests, this is the package name.

=item C<app_display_name>

The display name of the application, sometimes localized to the
install language of the guest operating system.

If unavailable this is returned as an empty string C<\"\">.
Callers needing to display something can use C<app_name> instead.

=item C<app_epoch>

For package managers which use epochs, this contains the epoch of
the package (an integer).  If unavailable, this is returned as C<0>.

=item C<app_version>

The version string of the application or package.  If unavailable
this is returned as an empty string C<\"\">.

=item C<app_release>

The release string of the application or package, for package
managers that use this.  If unavailable this is returned as an
empty string C<\"\">.

=item C<app_install_path>

The installation path of the application (on operating systems
such as Windows which use installation paths).  This path is
in the format used by the guest operating system, it is not
a libguestfs path.

If unavailable this is returned as an empty string C<\"\">.

=item C<app_trans_path>

The install path translated into a libguestfs path.
If unavailable this is returned as an empty string C<\"\">.

=item C<app_publisher>

The name of the publisher of the application, for package
managers that use this.  If unavailable this is returned
as an empty string C<\"\">.

=item C<app_url>

The URL (eg. upstream URL) of the application.
If unavailable this is returned as an empty string C<\"\">.

=item C<app_source_package>

For packaging systems which support this, the name of the source
package.  If unavailable this is returned as an empty string C<\"\">.

=item C<app_summary>

A short (usually one line) description of the application or package.
If unavailable this is returned as an empty string C<\"\">.

=item C<app_description>

A longer description of the application or package.
If unavailable this is returned as an empty string C<\"\">.

=back

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_hostname", (RString "hostname", [Device "root"], []), -1, [],
   [],
   "get hostname of the operating system",
   "\
This function returns the hostname of the operating system
as found by inspection of the guest's configuration files.

If the hostname could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_format", (RString "format", [Device "root"], []), -1, [],
   [],
   "get format of inspected operating system",
   "\
This returns the format of the inspected operating system.  You
can use it to detect install images, live CDs and similar.

Currently defined formats are:

=over 4

=item \"installed\"

This is an installed operating system.

=item \"installer\"

The disk image being inspected is not an installed operating system,
but a I<bootable> install disk, live CD, or similar.

=item \"unknown\"

The format of this disk image is not known.

=back

Future versions of libguestfs may return other strings here.
The caller should be prepared to handle any string.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_is_live", (RBool "live", [Device "root"], []), -1, [],
   [],
   "get live flag for install disk",
   "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if a live image
was detected on the disk.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_is_netinst", (RBool "netinst", [Device "root"], []), -1, [],
   [],
   "get netinst (network installer) flag for install disk",
   "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if the disk is
a network installer, ie. not a self-contained install CD but
one which is likely to require network access to complete
the install.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_is_multipart", (RBool "multipart", [Device "root"], []), -1, [],
   [],
   "get multipart flag for install disk",
   "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if the disk is
part of a set.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("set_attach_method", (RErr, [String "attachmethod"], []), -1, [FishAlias "attach-method"],
   [],
   "set the attach method",
   "\
Set the method that libguestfs uses to connect to the back end
guestfsd daemon.  Possible methods are:

=over 4

=item C<appliance>

Launch an appliance and connect to it.  This is the ordinary method
and the default.

=item C<unix:I<path>>

Connect to the Unix domain socket I<path>.

This method lets you connect to an existing daemon or (using
virtio-serial) to a live guest.  For more information, see
L<guestfs(3)/ATTACHING TO RUNNING DAEMONS>.

=back");

  ("get_attach_method", (RString "attachmethod", [], []), -1, [],
   [InitNone, Always, TestOutput (
      [["get_attach_method"]], "appliance")],
   "get the attach method",
   "\
Return the current attach method.  See C<guestfs_set_attach_method>.");

  ("inspect_get_product_variant", (RString "variant", [Device "root"], []), -1, [],
   [],
   "get product variant of inspected operating system",
   "\
This returns the product variant of the inspected operating
system.

For Windows guests, this returns the contents of the Registry key
C<HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion>
C<InstallationType> which is usually a string such as
C<Client> or C<Server> (other values are possible).  This
can be used to distinguish consumer and enterprise versions
of Windows that have the same version number (for example,
Windows 7 and Windows 2008 Server are both version 6.1,
but the former is C<Client> and the latter is C<Server>).

For enterprise Linux guests, in future we intend this to return
the product variant such as C<Desktop>, C<Server> and so on.  But
this is not implemented at present.

If the product variant could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_product_name>,
C<guestfs_inspect_get_major_version>.");

  ("inspect_get_windows_current_control_set", (RString "controlset", [Device "root"], []), -1, [],
   [],
   "get Windows CurrentControlSet of inspected operating system",
   "\
This returns the Windows CurrentControlSet of the inspected guest.
The CurrentControlSet is a registry key name such as C<ControlSet001>.

This call assumes that the guest is Windows and that the
Registry could be examined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details.");

  ("inspect_get_drive_mappings", (RHashtable "drives", [Device "root"], []), -1, [],
   [],
   "get drive letter mappings",
   "\
This call is useful for Windows which uses a primitive system
of assigning drive letters (like \"C:\") to partitions.
This inspection API examines the Windows Registry to find out
how disks/partitions are mapped to drive letters, and returns
a hash table as in the example below:

 C      =>     /dev/vda2
 E      =>     /dev/vdb1
 F      =>     /dev/vdc1

Note that keys are drive letters.  For Windows, the key is
case insensitive and just contains the drive letter, without
the customary colon separator character.

In future we may support other operating systems that also used drive
letters, but the keys for those might not be case insensitive
and might be longer than 1 character.  For example in OS-9,
hard drives were named C<h0>, C<h1> etc.

For Windows guests, currently only hard drive mappings are
returned.  Removable disks (eg. DVD-ROMs) are ignored.

For guests that do not use drive mappings, or if the drive mappings
could not be determined, this returns an empty hash table.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_mountpoints>,
C<guestfs_inspect_get_filesystems>.");

  ("inspect_get_icon", (RBufferOut "icon", [Device "root"],  [OBool "favicon"; OBool "highquality"]), -1, [],
   [],
   "get the icon corresponding to this operating system",
   "\
This function returns an icon corresponding to the inspected
operating system.  The icon is returned as a buffer containing a
PNG image (re-encoded to PNG if necessary).

If it was not possible to get an icon this function returns a
zero-length (non-NULL) buffer.  I<Callers must check for this case>.

Libguestfs will start by looking for a file called
C</etc/favicon.png> or C<C:\\etc\\favicon.png>
and if it has the correct format, the contents of this file will
be returned.  You can disable favicons by passing the
optional C<favicon> boolean as false (default is true).

If finding the favicon fails, then we look in other places in the
guest for a suitable icon.

If the optional C<highquality> boolean is true then
only high quality icons are returned, which means only icons of
high resolution with an alpha channel.  The default (false) is
to return any icon we can, even if it is of substandard quality.

Notes:

=over 4

=item *

Unlike most other inspection API calls, the guest's disks must be
mounted up before you call this, since it needs to read information
from the guest filesystem during the call.

=item *

B<Security:> The icon data comes from the untrusted guest,
and should be treated with caution.  PNG files have been
known to contain exploits.  Ensure that libpng (or other relevant
libraries) are fully up to date before trying to process or
display the icon.

=item *

The PNG image returned can be any size.  It might not be square.
Libguestfs tries to return the largest, highest quality
icon available.  The application must scale the icon to the
required size.

=item *

Extracting icons from Windows guests requires the external
C<wrestool> program from the C<icoutils> package, and
several programs (C<bmptopnm>, C<pnmtopng>, C<pamcut>)
from the C<netpbm> package.  These must be installed separately.

=item *

Operating system icons are usually trademarks.  Seek legal
advice before using trademarks in applications.

=back");

  ("set_pgroup", (RErr, [Bool "pgroup"], []), -1, [FishAlias "pgroup"],
   [],
   "set process group flag",
   "\
If C<pgroup> is true, child processes are placed into
their own process group.

The practical upshot of this is that signals like C<SIGINT> (from
users pressing C<^C>) won't be received by the child process.

The default for this flag is false, because usually you want
C<^C> to kill the subprocess.");

  ("get_pgroup", (RBool "pgroup", [], []), -1, [],
   [],
   "get process group flag",
   "\
This returns the process group flag.");

  ("set_smp", (RErr, [Int "smp"], []), -1, [FishAlias "smp"],
   [],
   "set number of virtual CPUs in appliance",
   "\
Change the number of virtual CPUs assigned to the appliance.  The
default is C<1>.  Increasing this may improve performance, though
often it has no effect.

This function must be called before C<guestfs_launch>.");

  ("get_smp", (RInt "smp", [], []), -1, [],
   [],
   "get number of virtual CPUs in appliance",
   "\
This returns the number of virtual CPUs assigned to the appliance.");

]

(* daemon_functions are any functions which cause some action
 * to take place in the daemon.
 *)

let daemon_functions = [
  ("mount", (RErr, [Device "device"; String "mountpoint"], []), 1, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount"; "/dev/sda1"; "/"];
       ["write"; "/new"; "new file contents"];
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

Before libguestfs 1.13.16, this call implicitly added the options
C<sync> and C<noatime>.  The C<sync> option greatly slowed
writes and caused many problems for users.  If your program
might need to work with older versions of libguestfs, use
C<guestfs_mount_options> instead (using an empty string for the
first parameter if you don't want any options).");

  ("sync", (RErr, [], []), 2, [],
   [ InitEmpty, Always, TestRun [["sync"]]],
   "sync disks, writes are flushed through to the disk image",
   "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
closing the handle.");

  ("touch", (RErr, [Pathname "path"], []), 3, [],
   [InitScratchFS, Always, TestOutputTrue (
      [["touch"; "/touch"];
       ["exists"; "/touch"]])],
   "update file timestamps or create a new file",
   "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.

This command only works on regular files, and will fail on other
file types such as directories, symbolic links, block special etc.");

  ("cat", (RString "content", [Pathname "path"], []), 4, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutput (
      [["cat"; "/known-2"]], "abcdef\n")],
   "list the contents of a file",
   "\
Return the contents of the file named C<path>.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_read_file>
or C<guestfs_download> functions which have a more complex interface.");

  ("ll", (RString "listing", [Pathname "directory"], []), 5, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'ls -l' command, which changes between F10 and F11.
        *)
   "list the files in a directory (long format)",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.");

  ("ls", (RStringList "listing", [Pathname "directory"], []), 6, [],
   [InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/ls"];
       ["touch"; "/ls/new"];
       ["touch"; "/ls/newer"];
       ["touch"; "/ls/newest"];
       ["ls"; "/ls"]], ["new"; "newer"; "newest"])],
   "list the files in a directory",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd).  The '.' and '..' entries are not returned, but
hidden files are shown.

This command is mostly useful for interactive sessions.  Programs
should probably use C<guestfs_readdir> instead.");

  ("list_devices", (RStringList "devices", [], []), 7, [],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["list_devices"]], ["/dev/sda"; "/dev/sdb"; "/dev/sdc"; "/dev/sdd"])],
   "list the block devices",
   "\
List all the block devices.

The full block device names are returned, eg. C</dev/sda>.

See also C<guestfs_list_filesystems>.");

  ("list_partitions", (RStringList "partitions", [], []), 8, [],
   [InitBasicFS, Always, TestOutputListOfDevices (
      [["list_partitions"]], ["/dev/sda1"; "/dev/sdb1"]);
    InitEmpty, Always, TestOutputListOfDevices (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
       ["list_partitions"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"; "/dev/sdb1"])],
   "list the partitions",
   "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. C</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.

See also C<guestfs_list_filesystems>.");

  ("pvs", (RStringList "physvols", [], []), 9, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputListOfDevices (
      [["pvs"]], ["/dev/sda1"]);
    InitEmpty, Always, TestOutputListOfDevices (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
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

  ("vgs", (RStringList "volgroups", [], []), 10, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["vgs"]], ["VG"]);
    InitEmpty, Always, TestOutputList (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
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

  ("lvs", (RStringList "logvols", [], []), 11, [Optional "lvm2"],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["lvs"]], ["/dev/VG/LV"]);
    InitEmpty, Always, TestOutputList (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
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

See also C<guestfs_lvs_full>, C<guestfs_list_filesystems>.");

  ("pvs_full", (RStructList ("physvols", "lvm_pv"), [], []), 12, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields.");

  ("vgs_full", (RStructList ("volgroups", "lvm_vg"), [], []), 13, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields.");

  ("lvs_full", (RStructList ("logvols", "lvm_lv"), [], []), 14, [Optional "lvm2"],
   [], (* XXX how to test? *)
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields.");

  ("read_lines", (RStringList "lines", [Pathname "path"], []), 15, [],
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

  ("aug_init", (RErr, [Pathname "root"; Int "flags"], []), 16, [Optional "augeas"],
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

Typecheck lenses.

This option is only useful when debugging Augeas lenses.  Use
of this option may require additional memory for the libguestfs
appliance.  You may need to set the C<LIBGUESTFS_MEMSIZE>
environment variable or call C<guestfs_set_memsize>.

=item C<AUG_NO_STDINC> = 8

Do not use standard load path for modules.

=item C<AUG_SAVE_NOOP> = 16

Make save a no-op, just record what would have been changed.

=item C<AUG_NO_LOAD> = 32

Do not load the tree in C<guestfs_aug_init>.

=back

To close the handle, you can call C<guestfs_aug_close>.

To find out more about Augeas, see L<http://augeas.net/>.");

  ("aug_close", (RErr, [], []), 26, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "close the current Augeas handle",
   "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions.");

  ("aug_defvar", (RInt "nrnodes", [String "name"; OptString "expr"], []), 17, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "define an Augeas variable",
   "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset.");

  ("aug_defnode", (RStruct ("nrnodescreated", "int_bool"), [String "name"; String "expr"; String "val"], []), 18, [Optional "augeas"],
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

  ("aug_get", (RString "val", [String "augpath"], []), 19, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "look up the value of an Augeas path",
   "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned.");

  ("aug_set", (RErr, [String "augpath"; String "val"], []), 20, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "set Augeas path to value",
   "\
Set the value associated with C<path> to C<val>.

In the Augeas API, it is possible to clear a node by setting
the value to NULL.  Due to an oversight in the libguestfs API
you cannot do that with this call.  Instead you must use the
C<guestfs_aug_clear> call.");

  ("aug_insert", (RErr, [String "augpath"; String "label"; Bool "before"], []), 21, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "insert a sibling Augeas node",
   "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain C</>, C<*> or end
with a bracketed index C<[N]>.");

  ("aug_rm", (RInt "nrnodes", [String "augpath"], []), 22, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "remove an Augeas path",
   "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed.");

  ("aug_mv", (RErr, [String "src"; String "dest"], []), 23, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "move Augeas node",
   "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists.");

  ("aug_match", (RStringList "matches", [String "augpath"], []), 24, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "return Augeas nodes which match augpath",
   "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree.");

  ("aug_save", (RErr, [], []), 25, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "write all pending Augeas changes to disk",
   "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved.");

  ("aug_load", (RErr, [], []), 27, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "load files into the tree",
   "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details.");

  ("aug_ls", (RStringList "matches", [String "augpath"], []), 28, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "list Augeas nodes under augpath",
   "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the resulting nodes into alphabetical order.");

  ("rm", (RErr, [Pathname "path"], []), 29, [],
   [InitScratchFS, Always, TestRun
      [["mkdir"; "/rm"];
       ["touch"; "/rm/new"];
       ["rm"; "/rm/new"]];
    InitScratchFS, Always, TestLastFail
      [["rm"; "/nosuchfile"]];
    InitScratchFS, Always, TestLastFail
      [["mkdir"; "/rm2"];
       ["rm"; "/rm2"]]],
   "remove a file",
   "\
Remove the single file C<path>.");

  ("rmdir", (RErr, [Pathname "path"], []), 30, [],
   [InitScratchFS, Always, TestRun
      [["mkdir"; "/rmdir"];
       ["rmdir"; "/rmdir"]];
    InitScratchFS, Always, TestLastFail
      [["rmdir"; "/rmdir2"]];
    InitScratchFS, Always, TestLastFail
      [["mkdir"; "/rmdir3"];
       ["touch"; "/rmdir3/new"];
       ["rmdir"; "/rmdir3/new"]]],
   "remove a directory",
   "\
Remove the single directory C<path>.");

  ("rm_rf", (RErr, [Pathname "path"], []), 31, [],
   [InitScratchFS, Always, TestOutputFalse
      [["mkdir"; "/rm_rf"];
       ["mkdir"; "/rm_rf/foo"];
       ["touch"; "/rm_rf/foo/bar"];
       ["rm_rf"; "/rm_rf"];
       ["exists"; "/rm_rf"]]],
   "remove a file or directory recursively",
   "\
Remove the file or directory C<path>, recursively removing the
contents if its a directory.  This is like the C<rm -rf> shell
command.");

  ("mkdir", (RErr, [Pathname "path"], []), 32, [],
   [InitScratchFS, Always, TestOutputTrue
      [["mkdir"; "/mkdir"];
       ["is_dir"; "/mkdir"]];
    InitScratchFS, Always, TestLastFail
      [["mkdir"; "/mkdir2/foo/bar"]]],
   "create a directory",
   "\
Create a directory named C<path>.");

  ("mkdir_p", (RErr, [Pathname "path"], []), 33, [],
   [InitScratchFS, Always, TestOutputTrue
      [["mkdir_p"; "/mkdir_p/foo/bar"];
       ["is_dir"; "/mkdir_p/foo/bar"]];
    InitScratchFS, Always, TestOutputTrue
      [["mkdir_p"; "/mkdir_p2/foo/bar"];
       ["is_dir"; "/mkdir_p2/foo"]];
    InitScratchFS, Always, TestOutputTrue
      [["mkdir_p"; "/mkdir_p3/foo/bar"];
       ["is_dir"; "/mkdir_p3"]];
    (* Regression tests for RHBZ#503133: *)
    InitScratchFS, Always, TestRun
      [["mkdir"; "/mkdir_p4"];
       ["mkdir_p"; "/mkdir_p4"]];
    InitScratchFS, Always, TestLastFail
      [["touch"; "/mkdir_p5"];
       ["mkdir_p"; "/mkdir_p5"]]],
   "create a directory and parents",
   "\
Create a directory named C<path>, creating any parent directories
as necessary.  This is like the C<mkdir -p> shell command.");

  ("chmod", (RErr, [Int "mode"; Pathname "path"], []), 34, [],
   [], (* XXX Need stat command to test *)
   "change file mode",
   "\
Change the mode (permissions) of C<path> to C<mode>.  Only
numeric modes are supported.

I<Note>: When using this command from guestfish, C<mode>
by default would be decimal, unless you prefix it with
C<0> to get octal, ie. use C<0700> not C<700>.

The mode actually set is affected by the umask.");

  ("chown", (RErr, [Int "owner"; Int "group"; Pathname "path"], []), 35, [],
   [], (* XXX Need stat command to test *)
   "change file owner and group",
   "\
Change the file owner to C<owner> and group to C<group>.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy).");

  ("exists", (RBool "existsflag", [Pathname "path"], []), 36, [],
   [InitISOFS, Always, TestOutputTrue (
      [["exists"; "/empty"]]);
    InitISOFS, Always, TestOutputTrue (
      [["exists"; "/directory"]])],
   "test if file or directory exists",
   "\
This returns C<true> if and only if there is a file, directory
(or anything) with the given C<path> name.

See also C<guestfs_is_file>, C<guestfs_is_dir>, C<guestfs_stat>.");

  ("is_file", (RBool "fileflag", [Pathname "path"], []), 37, [],
   [InitISOFS, Always, TestOutputTrue (
      [["is_file"; "/known-1"]]);
    InitISOFS, Always, TestOutputFalse (
      [["is_file"; "/directory"]])],
   "test if a regular file",
   "\
This returns C<true> if and only if there is a regular file
with the given C<path> name.  Note that it returns false for
other objects like directories.

See also C<guestfs_stat>.");

  ("is_dir", (RBool "dirflag", [Pathname "path"], []), 38, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_dir"; "/known-3"]]);
    InitISOFS, Always, TestOutputTrue (
      [["is_dir"; "/directory"]])],
   "test if a directory",
   "\
This returns C<true> if and only if there is a directory
with the given C<path> name.  Note that it returns false for
other objects like files.

See also C<guestfs_stat>.");

  ("pvcreate", (RErr, [Device "device"], []), 39, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
       ["pvcreate"; "/dev/sda1"];
       ["pvcreate"; "/dev/sda2"];
       ["pvcreate"; "/dev/sda3"];
       ["pvs"]], ["/dev/sda1"; "/dev/sda2"; "/dev/sda3"])],
   "create an LVM physical volume",
   "\
This creates an LVM physical volume on the named C<device>,
where C<device> should usually be a partition name such
as C</dev/sda1>.");

  ("vgcreate", (RErr, [String "volgroup"; DeviceList "physvols"], []), 40, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
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

  ("lvcreate", (RErr, [String "logvol"; String "volgroup"; Int "mbytes"], []), 41, [Optional "lvm2"],
   [InitEmpty, Always, TestOutputList (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
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
   "create an LVM logical volume",
   "\
This creates an LVM logical volume called C<logvol>
on the volume group C<volgroup>, with C<size> megabytes.");

  ("mkfs", (RErr, [String "fstype"; Device "device"], []), 42, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["write"; "/new"; "new file contents"];
       ["cat"; "/new"]], "new file contents")],
   "make a filesystem",
   "\
This creates a filesystem on C<device> (usually a partition
or LVM logical volume).  The filesystem type is C<fstype>, for
example C<ext3>.");

  ("sfdisk", (RErr, [Device "device";
                     Int "cyls"; Int "heads"; Int "sectors";
                     StringList "lines"], []), 43, [DeprecatedBy "part_add"],
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

  ("write_file", (RErr, [Pathname "path"; String "content"; Int "size"], []), 44, [ProtocolLimitWarning; DeprecatedBy "write"],
   (* Regression test for RHBZ#597135. *)
   [InitScratchFS, Always, TestLastFail
      [["write_file"; "/write_file"; "abc"; "10000"]]],
   "create a file",
   "\
This call creates a file called C<path>.  The contents of the
file is the string C<content> (which can contain any 8 bit data),
with length C<size>.

As a special case, if C<size> is C<0>
then the length is calculated using C<strlen> (so in this case
the content cannot contain embedded ASCII NULs).

I<NB.> Owing to a bug, writing content containing ASCII NUL
characters does I<not> work, even if the length is specified.");

  ("umount", (RErr, [String "pathordevice"], []), 45, [FishAlias "unmount"],
   [InitEmpty, Always, TestOutputListOfDevices (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["mounts"]], ["/dev/sda1"]);
    InitEmpty, Always, TestOutputList (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["umount"; "/"];
       ["mounts"]], [])],
   "unmount a filesystem",
   "\
This unmounts the given filesystem.  The filesystem may be
specified either by its mountpoint (path) or the device which
contains the filesystem.");

  ("mounts", (RStringList "devices", [], []), 46, [],
   [InitScratchFS, Always, TestOutputListOfDevices (
      [["mounts"]], ["/dev/sdb1"])],
   "show mounted filesystems",
   "\
This returns the list of currently mounted filesystems.  It returns
the list of devices (eg. C</dev/sda1>, C</dev/VG/LV>).

Some internal mounts are not shown.

See also: C<guestfs_mountpoints>");

  ("umount_all", (RErr, [], []), 47, [FishAlias "unmount-all"],
   [InitScratchFS, Always, TestOutputList (
      [["umount_all"];
       ["mounts"]], []);
    (* check that umount_all can unmount nested mounts correctly: *)
    InitEmpty, Always, TestOutputList (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
       ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
       ["mkfs"; "ext2"; "/dev/sda1"];
       ["mkfs"; "ext2"; "/dev/sda2"];
       ["mkfs"; "ext2"; "/dev/sda3"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["mkdir"; "/mp1"];
       ["mount_options"; ""; "/dev/sda2"; "/mp1"];
       ["mkdir"; "/mp1/mp2"];
       ["mount_options"; ""; "/dev/sda3"; "/mp1/mp2"];
       ["mkdir"; "/mp1/mp2/mp3"];
       ["umount_all"];
       ["mounts"]], [])],
   "unmount all filesystems",
   "\
This unmounts all mounted filesystems.

Some internal mounts are not unmounted by this call.");

  ("lvm_remove_all", (RErr, [], []), 48, [Optional "lvm2"],
   [],
   "remove all LVM LVs, VGs and PVs",
   "\
This command removes all LVM logical volumes, volume groups
and physical volumes.");

  ("file", (RString "description", [Dev_or_Path "path"], []), 49, [],
   [InitISOFS, Always, TestOutput (
      [["file"; "/empty"]], "empty");
    InitISOFS, Always, TestOutput (
      [["file"; "/known-1"]], "ASCII text");
    InitISOFS, Always, TestLastFail (
      [["file"; "/notexists"]]);
    InitISOFS, Always, TestOutput (
      [["file"; "/abssymlink"]], "symbolic link");
    InitISOFS, Always, TestOutput (
      [["file"; "/directory"]], "directory")],
   "determine file type",
   "\
This call uses the standard L<file(1)> command to determine
the type or contents of the file.

This call will also transparently look inside various types
of compressed file.

The exact command which runs is C<file -zb path>.  Note in
particular that the filename is not prepended to the output
(the I<-b> option).

The output depends on the output of the underlying L<file(1)>
command and it can change in future in ways beyond our control.
In other words, the output is not guaranteed by the ABI.

See also: L<file(1)>, C<guestfs_vfs_type>, C<guestfs_lstat>,
C<guestfs_is_file>, C<guestfs_is_blockdev> (etc), C<guestfs_is_zero>.");

  ("command", (RString "output", [StringList "arguments"], []), 50, [ProtocolLimitWarning],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command"];
       ["upload"; "test-command"; "/command/test-command"];
       ["chmod"; "0o755"; "/command/test-command"];
       ["command"; "/command/test-command 1"]], "Result1");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command2"];
       ["upload"; "test-command"; "/command2/test-command"];
       ["chmod"; "0o755"; "/command2/test-command"];
       ["command"; "/command2/test-command 2"]], "Result2\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command3"];
       ["upload"; "test-command"; "/command3/test-command"];
       ["chmod"; "0o755"; "/command3/test-command"];
       ["command"; "/command3/test-command 3"]], "\nResult3");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command4"];
       ["upload"; "test-command"; "/command4/test-command"];
       ["chmod"; "0o755"; "/command4/test-command"];
       ["command"; "/command4/test-command 4"]], "\nResult4\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command5"];
       ["upload"; "test-command"; "/command5/test-command"];
       ["chmod"; "0o755"; "/command5/test-command"];
       ["command"; "/command5/test-command 5"]], "\nResult5\n\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command6"];
       ["upload"; "test-command"; "/command6/test-command"];
       ["chmod"; "0o755"; "/command6/test-command"];
       ["command"; "/command6/test-command 6"]], "\n\nResult6\n\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command7"];
       ["upload"; "test-command"; "/command7/test-command"];
       ["chmod"; "0o755"; "/command7/test-command"];
       ["command"; "/command7/test-command 7"]], "");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command8"];
       ["upload"; "test-command"; "/command8/test-command"];
       ["chmod"; "0o755"; "/command8/test-command"];
       ["command"; "/command8/test-command 8"]], "\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command9"];
       ["upload"; "test-command"; "/command9/test-command"];
       ["chmod"; "0o755"; "/command9/test-command"];
       ["command"; "/command9/test-command 9"]], "\n\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command10"];
       ["upload"; "test-command"; "/command10/test-command"];
       ["chmod"; "0o755"; "/command10/test-command"];
       ["command"; "/command10/test-command 10"]], "Result10-1\nResult10-2\n");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/command11"];
       ["upload"; "test-command"; "/command11/test-command"];
       ["chmod"; "0o755"; "/command11/test-command"];
       ["command"; "/command11/test-command 11"]], "Result11-1\nResult11-2");
    InitScratchFS, Always, TestLastFail (
      [["mkdir"; "/command12"];
       ["upload"; "test-command"; "/command12/test-command"];
       ["chmod"; "0o755"; "/command12/test-command"];
       ["command"; "/command12/test-command"]])],
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

  ("command_lines", (RStringList "lines", [StringList "arguments"], []), 51, [ProtocolLimitWarning],
   [InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines"];
       ["upload"; "test-command"; "/command_lines/test-command"];
       ["chmod"; "0o755"; "/command_lines/test-command"];
       ["command_lines"; "/command_lines/test-command 1"]], ["Result1"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines2"];
       ["upload"; "test-command"; "/command_lines2/test-command"];
       ["chmod"; "0o755"; "/command_lines2/test-command"];
       ["command_lines"; "/command_lines2/test-command 2"]], ["Result2"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines3"];
       ["upload"; "test-command"; "/command_lines3/test-command"];
       ["chmod"; "0o755"; "/command_lines3/test-command"];
       ["command_lines"; "/command_lines3/test-command 3"]], ["";"Result3"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines4"];
       ["upload"; "test-command"; "/command_lines4/test-command"];
       ["chmod"; "0o755"; "/command_lines4/test-command"];
       ["command_lines"; "/command_lines4/test-command 4"]], ["";"Result4"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines5"];
       ["upload"; "test-command"; "/command_lines5/test-command"];
       ["chmod"; "0o755"; "/command_lines5/test-command"];
       ["command_lines"; "/command_lines5/test-command 5"]], ["";"Result5";""]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines6"];
       ["upload"; "test-command"; "/command_lines6/test-command"];
       ["chmod"; "0o755"; "/command_lines6/test-command"];
       ["command_lines"; "/command_lines6/test-command 6"]], ["";"";"Result6";""]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines7"];
       ["upload"; "test-command"; "/command_lines7/test-command"];
       ["chmod"; "0o755"; "/command_lines7/test-command"];
       ["command_lines"; "/command_lines7/test-command 7"]], []);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines8"];
       ["upload"; "test-command"; "/command_lines8/test-command"];
       ["chmod"; "0o755"; "/command_lines8/test-command"];
       ["command_lines"; "/command_lines8/test-command 8"]], [""]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines9"];
       ["upload"; "test-command"; "/command_lines9/test-command"];
       ["chmod"; "0o755"; "/command_lines9/test-command"];
       ["command_lines"; "/command_lines9/test-command 9"]], ["";""]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines10"];
       ["upload"; "test-command"; "/command_lines10/test-command"];
       ["chmod"; "0o755"; "/command_lines10/test-command"];
       ["command_lines"; "/command_lines10/test-command 10"]], ["Result10-1";"Result10-2"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/command_lines11"];
       ["upload"; "test-command"; "/command_lines11/test-command"];
       ["chmod"; "0o755"; "/command_lines11/test-command"];
       ["command_lines"; "/command_lines11/test-command 11"]], ["Result11-1";"Result11-2"])],
   "run a command, returning lines",
   "\
This is the same as C<guestfs_command>, but splits the
result into a list of lines.

See also: C<guestfs_sh_lines>");

  ("stat", (RStruct ("statbuf", "stat"), [Pathname "path"], []), 52, [],
   [InitISOFS, Always, TestOutputStruct (
      [["stat"; "/empty"]], [CompareWithInt ("size", 0)])],
   "get file information",
   "\
Returns file information for the given C<path>.

This is the same as the C<stat(2)> system call.");

  ("lstat", (RStruct ("statbuf", "stat"), [Pathname "path"], []), 53, [],
   [InitISOFS, Always, TestOutputStruct (
      [["lstat"; "/empty"]], [CompareWithInt ("size", 0)])],
   "get file information for a symbolic link",
   "\
Returns file information for the given C<path>.

This is the same as C<guestfs_stat> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the C<lstat(2)> system call.");

  ("statvfs", (RStruct ("statbuf", "statvfs"), [Pathname "path"], []), 54, [],
   [InitISOFS, Always, TestOutputStruct (
      [["statvfs"; "/"]], [CompareWithInt ("namemax", 255)])],
   "get file system statistics",
   "\
Returns file system statistics for any mounted file system.
C<path> should be a file or directory in the mounted file system
(typically it is the mount point itself, but it doesn't need to be).

This is the same as the C<statvfs(2)> system call.");

  ("tune2fs_l", (RHashtable "superblock", [Device "device"], []), 55, [],
   [InitScratchFS, Always, TestOutputHashtable (
      [["tune2fs_l"; "/dev/sdb1"]],
      ["Filesystem magic number", "0xEF53";
       "Filesystem OS type", "Linux"])],
   "get ext2/ext3/ext4 superblock details",
   "\
This returns the contents of the ext2, ext3 or ext4 filesystem
superblock on C<device>.

It is the same as running C<tune2fs -l device>.  See L<tune2fs(8)>
manpage for more details.  The list of fields returned isn't
clearly defined, and depends on both the version of C<tune2fs>
that libguestfs was built against, and the filesystem itself.");

  ("blockdev_setro", (RErr, [Device "device"], []), 56, [],
   [InitEmpty, Always, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-only",
   "\
Sets the block device named C<device> to read-only.

This uses the L<blockdev(8)> command.");

  ("blockdev_setrw", (RErr, [Device "device"], []), 57, [],
   [InitEmpty, Always, TestOutputFalse (
      [["blockdev_setrw"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "set block device to read-write",
   "\
Sets the block device named C<device> to read-write.

This uses the L<blockdev(8)> command.");

  ("blockdev_getro", (RBool "ro", [Device "device"], []), 58, [],
   [InitEmpty, Always, TestOutputTrue (
      [["blockdev_setro"; "/dev/sda"];
       ["blockdev_getro"; "/dev/sda"]])],
   "is block device set to read-only",
   "\
Returns a boolean indicating if the block device is read-only
(true if read-only, false if not).

This uses the L<blockdev(8)> command.");

  ("blockdev_getss", (RInt "sectorsize", [Device "device"], []), 59, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getss"; "/dev/sda"]], 512)],
   "get sectorsize of block device",
   "\
This returns the size of sectors on a block device.
Usually 512, but can be larger for modern devices.

(Note, this is not the size in sectors, use C<guestfs_blockdev_getsz>
for that).

This uses the L<blockdev(8)> command.");

  ("blockdev_getbsz", (RInt "blocksize", [Device "device"], []), 60, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getbsz"; "/dev/sda"]], 4096)],
   "get blocksize of block device",
   "\
This returns the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_setbsz", (RErr, [Device "device"; Int "blocksize"], []), 61, [],
   [], (* XXX test *)
   "set blocksize of block device",
   "\
This sets the block size of a device.

(Note this is different from both I<size in blocks> and
I<filesystem block size>).

This uses the L<blockdev(8)> command.");

  ("blockdev_getsz", (RInt64 "sizeinsectors", [Device "device"], []), 62, [],
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

  ("blockdev_getsize64", (RInt64 "sizeinbytes", [Device "device"], []), 63, [],
   [InitEmpty, Always, TestOutputInt (
      [["blockdev_getsize64"; "/dev/sda"]], 524288000)],
   "get total size of device in bytes",
   "\
This returns the size of the device in bytes.

See also C<guestfs_blockdev_getsz>.

This uses the L<blockdev(8)> command.");

  ("blockdev_flushbufs", (RErr, [Device "device"], []), 64, [],
   [InitEmpty, Always, TestRun
      [["blockdev_flushbufs"; "/dev/sda"]]],
   "flush device buffers",
   "\
This tells the kernel to flush internal buffers associated
with C<device>.

This uses the L<blockdev(8)> command.");

  ("blockdev_rereadpt", (RErr, [Device "device"], []), 65, [],
   [InitEmpty, Always, TestRun
      [["blockdev_rereadpt"; "/dev/sda"]]],
   "reread partition table",
   "\
Reread the partition table on C<device>.

This uses the L<blockdev(8)> command.");

  ("upload", (RErr, [FileIn "filename"; Dev_or_Path "remotefilename"], []), 66,
   [Progress; Cancellable],
   [InitScratchFS, Always, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
      [["mkdir"; "/upload"];
       ["upload"; "../../COPYING.LIB"; "/upload/COPYING.LIB"];
       ["checksum"; "md5"; "/upload/COPYING.LIB"]],
      Digest.to_hex (Digest.file "COPYING.LIB"))],
   "upload a file from the local machine",
   "\
Upload local file C<filename> to C<remotefilename> on the
filesystem.

C<filename> can also be a named pipe.

See also C<guestfs_download>.");

  ("download", (RErr, [Dev_or_Path "remotefilename"; FileOut "filename"], []), 67,
   [Progress; Cancellable],
   [InitScratchFS, Always, TestOutput (
      (* Pick a file from cwd which isn't likely to change. *)
      [["mkdir"; "/download"];
       ["upload"; "../../COPYING.LIB"; "/download/COPYING.LIB"];
       ["download"; "/download/COPYING.LIB"; "testdownload.tmp"];
       ["upload"; "testdownload.tmp"; "/download/upload"];
       ["checksum"; "md5"; "/download/upload"]],
      Digest.to_hex (Digest.file "COPYING.LIB"))],
   "download a file to the local machine",
   "\
Download file C<remotefilename> and save it as C<filename>
on the local machine.

C<filename> can also be a named pipe.

See also C<guestfs_upload>, C<guestfs_cat>.");

  ("checksum", (RString "checksum", [String "csumtype"; Pathname "path"], []), 68, [],
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
      [["checksum"; "sha512"; "/known-3"]], "2794062c328c6b216dca90443b7f7134c5f40e56bd0ed7853123275a09982a6f992e6ca682f9d2fba34a4c5e870d8fe077694ff831e3032a004ee077e00603f6");
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestOutput (
      [["checksum"; "sha512"; "/abssymlink"]], "5f57d0639bc95081c53afc63a449403883818edc64da48930ad6b1a4fb49be90404686877743fbcd7c99811f3def7df7bc22635c885c6a8cf79c806b43451c1a")],
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

The checksum is returned as a printable string.

To get the checksum for a device, use C<guestfs_checksum_device>.

To get the checksums for many files, use C<guestfs_checksums_out>.");

  ("tar_in", (RErr, [FileIn "tarfile"; Pathname "directory"], []), 69,
   [Cancellable],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/tar_in"];
       ["tar_in"; "../data/helloworld.tar"; "/tar_in"];
       ["cat"; "/tar_in/hello"]], "hello\n")],
   "unpack tarfile to directory",
   "\
This command uploads and unpacks local file C<tarfile> (an
I<uncompressed> tar file) into C<directory>.

To upload a compressed tarball, use C<guestfs_tgz_in>
or C<guestfs_txz_in>.");

  ("tar_out", (RErr, [String "directory"; FileOut "tarfile"], []), 70,
   [Cancellable],
   [],
   "pack directory into tarfile",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarfile>.

To download a compressed tarball, use C<guestfs_tgz_out>
or C<guestfs_txz_out>.");

  ("tgz_in", (RErr, [FileIn "tarball"; Pathname "directory"], []), 71,
   [Cancellable],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/tgz_in"];
       ["tgz_in"; "../data/helloworld.tar.gz"; "/tgz_in"];
       ["cat"; "/tgz_in/hello"]], "hello\n")],
   "unpack compressed tarball to directory",
   "\
This command uploads and unpacks local file C<tarball> (a
I<gzip compressed> tar file) into C<directory>.

To upload an uncompressed tarball, use C<guestfs_tar_in>.");

  ("tgz_out", (RErr, [Pathname "directory"; FileOut "tarball"], []), 72,
   [Cancellable],
   [],
   "pack directory into compressed tarball",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarball>.

To download an uncompressed tarball, use C<guestfs_tar_out>.");

  ("mount_ro", (RErr, [Device "device"; String "mountpoint"], []), 73, [],
   [InitBasicFS, Always, TestLastFail (
      [["umount"; "/"];
       ["mount_ro"; "/dev/sda1"; "/"];
       ["touch"; "/new"]]);
    InitBasicFS, Always, TestOutput (
      [["write"; "/new"; "data"];
       ["umount"; "/"];
       ["mount_ro"; "/dev/sda1"; "/"];
       ["cat"; "/new"]], "data")],
   "mount a guest disk, read-only",
   "\
This is the same as the C<guestfs_mount> command, but it
mounts the filesystem with the read-only (I<-o ro>) flag.");

  ("mount_options", (RErr, [String "options"; Device "device"; String "mountpoint"], []), 74, [],
   [],
   "mount a guest disk with mount options",
   "\
This is the same as the C<guestfs_mount> command, but it
allows you to set the mount options as for the
L<mount(8)> I<-o> flag.

If the C<options> parameter is an empty string, then
no options are passed (all options default to whatever
the filesystem uses).");

  ("mount_vfs", (RErr, [String "options"; String "vfstype"; Device "device"; String "mountpoint"], []), 75, [],
   [],
   "mount a guest disk with mount options and vfstype",
   "\
This is the same as the C<guestfs_mount> command, but it
allows you to set both the mount options and the vfstype
as for the L<mount(8)> I<-o> and I<-t> flags.");

  ("debug", (RString "result", [String "subcmd"; StringList "extraargs"], []), 76, [NotInDocs],
   [],
   "debugging and internals",
   "\
The C<guestfs_debug> command exposes some internals of
C<guestfsd> (the guestfs daemon) that runs inside the
qemu subprocess.

There is no comprehensive help for this command.  You have
to look at the file C<daemon/debug.c> in the libguestfs source
to find out what you can do.");

  ("lvremove", (RErr, [Device "device"], []), 77, [Optional "lvm2"],
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

  ("vgremove", (RErr, [String "vgname"], []), 78, [Optional "lvm2"],
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

  ("pvremove", (RErr, [Device "device"], []), 79, [Optional "lvm2"],
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

  ("set_e2label", (RErr, [Device "device"; String "label"], []), 80, [],
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

  ("get_e2label", (RString "label", [Device "device"], []), 81, [DeprecatedBy "vfs_label"],
   [],
   "get the ext2/3/4 filesystem label",
   "\
This returns the ext2/3/4 filesystem label of the filesystem on
C<device>.");

  ("set_e2uuid", (RErr, [Device "device"; String "uuid"], []), 82, [],
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

  ("get_e2uuid", (RString "uuid", [Device "device"], []), 83, [DeprecatedBy "vfs_uuid"],
   (* Regression test for RHBZ#597112. *)
   (let uuid = uuidgen () in
    [InitNone, Always, TestOutput (
       [["mke2journal"; "1024"; "/dev/sdc"];
        ["set_e2uuid"; "/dev/sdc"; uuid];
        ["get_e2uuid"; "/dev/sdc"]], uuid)]),
   "get the ext2/3/4 filesystem UUID",
   "\
This returns the ext2/3/4 filesystem UUID of the filesystem on
C<device>.");

  ("fsck", (RInt "status", [String "fstype"; Device "device"], []), 84, [FishOutput FishOutputHexadecimal],
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

  ("zero", (RErr, [Device "device"], []), 85, [Progress],
   [InitBasicFS, Always, TestRun (
      [["umount"; "/dev/sda1"];
       ["zero"; "/dev/sda1"]])],
   "write zeroes to the device",
   "\
This command writes zeroes over the first few blocks of C<device>.

How many blocks are zeroed isn't specified (but it's I<not> enough
to securely wipe the device).  It should be sufficient to remove
any partition tables, filesystem superblocks and so on.

If blocks are already zero, then this command avoids writing
zeroes.  This prevents the underlying device from becoming non-sparse
or growing unnecessarily.

See also: C<guestfs_zero_device>, C<guestfs_scrub_device>,
C<guestfs_is_zero_device>");

  ("grub_install", (RErr, [Pathname "root"; Device "device"], []), 86, [Optional "grub"],
   (* See:
    * https://bugzilla.redhat.com/show_bug.cgi?id=484986
    * https://bugzilla.redhat.com/show_bug.cgi?id=479760
    *)
   [InitBasicFS, Always, TestOutputTrue (
      [["mkdir_p"; "/boot/grub"];
       ["write"; "/boot/grub/device.map"; "(hd0) /dev/vda"];
       ["grub_install"; "/"; "/dev/vda"];
       ["is_dir"; "/boot"]])],
   "install GRUB 1",
   "\
This command installs GRUB 1 (the Grand Unified Bootloader) on
C<device>, with the root directory being C<root>.

Notes:

=over 4

=item *

There is currently no way in the API to install grub2, which
is used by most modern Linux guests.  It is possible to run
the grub2 command from the guest, although see the
caveats in L<guestfs(3)/RUNNING COMMANDS>.

=item *

This uses C<grub-install> from the host.  Unfortunately grub is
not always compatible with itself, so this only works in rather
narrow circumstances.  Careful testing with each guest version
is advisable.

=item *

If grub-install reports the error
\"No suitable drive was found in the generated device map.\"
it may be that you need to create a C</boot/grub/device.map>
file first that contains the mapping between grub device names
and Linux device names.  It is usually sufficient to create
a file containing:

 (hd0) /dev/vda

replacing C</dev/vda> with the name of the installation device.

=back");

  ("cp", (RErr, [Pathname "src"; Pathname "dest"], []), 87, [],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/cp"];
       ["write"; "/cp/old"; "file content"];
       ["cp"; "/cp/old"; "/cp/new"];
       ["cat"; "/cp/new"]], "file content");
    InitScratchFS, Always, TestOutputTrue (
      [["mkdir"; "/cp2"];
       ["write"; "/cp2/old"; "file content"];
       ["cp"; "/cp2/old"; "/cp2/new"];
       ["is_file"; "/cp2/old"]]);
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/cp3"];
       ["write"; "/cp3/old"; "file content"];
       ["mkdir"; "/cp3/dir"];
       ["cp"; "/cp3/old"; "/cp3/dir/new"];
       ["cat"; "/cp3/dir/new"]], "file content")],
   "copy a file",
   "\
This copies a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory.");

  ("cp_a", (RErr, [Pathname "src"; Pathname "dest"], []), 88, [],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/cp_a1"];
       ["mkdir"; "/cp_a2"];
       ["write"; "/cp_a1/file"; "file content"];
       ["cp_a"; "/cp_a1"; "/cp_a2"];
       ["cat"; "/cp_a2/cp_a1/file"]], "file content")],
   "copy a file or directory recursively",
   "\
This copies a file or directory from C<src> to C<dest>
recursively using the C<cp -a> command.");

  ("mv", (RErr, [Pathname "src"; Pathname "dest"], []), 89, [],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/mv"];
       ["write"; "/mv/old"; "file content"];
       ["mv"; "/mv/old"; "/mv/new"];
       ["cat"; "/mv/new"]], "file content");
    InitScratchFS, Always, TestOutputFalse (
      [["mkdir"; "/mv2"];
       ["write"; "/mv2/old"; "file content"];
       ["mv"; "/mv2/old"; "/mv2/new"];
       ["is_file"; "/mv2/old"]])],
   "move a file",
   "\
This moves a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory.");

  ("drop_caches", (RErr, [Int "whattodrop"], []), 90, [],
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

  ("dmesg", (RString "kmsgs", [], []), 91, [],
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

  ("ping_daemon", (RErr, [], []), 92, [],
   [InitEmpty, Always, TestRun (
      [["ping_daemon"]])],
   "ping the guest daemon",
   "\
This is a test probe into the guestfs daemon running inside
the qemu subprocess.  Calling this function checks that the
daemon responds to the ping message, without affecting the daemon
or attached block device(s) in any other way.");

  ("equal", (RBool "equality", [Pathname "file1"; Pathname "file2"], []), 93, [],
   [InitScratchFS, Always, TestOutputTrue (
      [["mkdir"; "/equal"];
       ["write"; "/equal/file1"; "contents of a file"];
       ["cp"; "/equal/file1"; "/equal/file2"];
       ["equal"; "/equal/file1"; "/equal/file2"]]);
    InitScratchFS, Always, TestOutputFalse (
      [["mkdir"; "/equal2"];
       ["write"; "/equal2/file1"; "contents of a file"];
       ["write"; "/equal2/file2"; "contents of another file"];
       ["equal"; "/equal2/file1"; "/equal2/file2"]]);
    InitScratchFS, Always, TestLastFail (
      [["mkdir"; "/equal3"];
       ["equal"; "/equal3/file1"; "/equal3/file2"]])],
   "test if two files have equal contents",
   "\
This compares the two files C<file1> and C<file2> and returns
true if their content is exactly equal, or false otherwise.

The external L<cmp(1)> program is used for the comparison.");

  ("strings", (RStringList "stringsout", [Pathname "path"], []), 94, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["strings"; "/known-5"]], ["abcdefghi"; "jklmnopqr"]);
    InitISOFS, Always, TestOutputList (
      [["strings"; "/empty"]], []);
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestRun (
      [["strings"; "/abssymlink"]])],
   "print the printable strings in a file",
   "\
This runs the L<strings(1)> command on a file and returns
the list of printable strings found.");

  ("strings_e", (RStringList "stringsout", [String "encoding"; Pathname "path"], []), 95, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["strings_e"; "b"; "/known-5"]], []);
    InitScratchFS, Always, TestOutputList (
      [["write"; "/strings_e"; "\000h\000e\000l\000l\000o\000\n\000w\000o\000r\000l\000d\000\n"];
       ["strings_e"; "b"; "/strings_e"]], ["hello"; "world"])],
   "print the printable strings in a file",
   "\
This is like the C<guestfs_strings> command, but allows you to
specify the encoding of strings that are looked for in
the source file C<path>.

Allowed encodings are:

=over 4

=item s

Single 7-bit-byte characters like ASCII and the ASCII-compatible
parts of ISO-8859-X (this is what C<guestfs_strings> uses).

=item S

Single 8-bit-byte characters.

=item b

16-bit big endian strings such as those encoded in
UTF-16BE or UCS-2BE.

=item l (lower case letter L)

16-bit little endian such as UTF-16LE and UCS-2LE.
This is useful for examining binaries in Windows guests.

=item B

32-bit big endian such as UCS-4BE.

=item L

32-bit little endian such as UCS-4LE.

=back

The returned strings are transcoded to UTF-8.");

  ("hexdump", (RString "dump", [Pathname "path"], []), 96, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutput (
      [["hexdump"; "/known-4"]], "00000000  61 62 63 0a 64 65 66 0a  67 68 69                 |abc.def.ghi|\n0000000b\n");
    (* Test for RHBZ#501888c2 regression which caused large hexdump
     * commands to segfault.
     *)
    InitISOFS, Always, TestRun (
      [["hexdump"; "/100krandom"]]);
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestRun (
      [["hexdump"; "/abssymlink"]])],
   "dump a file in hexadecimal",
   "\
This runs C<hexdump -C> on the given C<path>.  The result is
the human-readable, canonical hex dump of the file.");

  ("zerofree", (RErr, [Device "device"], []), 97, [Optional "zerofree"],
   [InitNone, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs"; "ext3"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["write"; "/new"; "test file"];
       ["umount"; "/dev/sda1"];
       ["zerofree"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
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

  ("pvresize", (RErr, [Device "device"], []), 98, [Optional "lvm2"],
   [],
   "resize an LVM physical volume",
   "\
This resizes (expands or shrinks) an existing LVM physical
volume to match the new size of the underlying device.");

  ("sfdisk_N", (RErr, [Device "device"; Int "partnum";
                       Int "cyls"; Int "heads"; Int "sectors";
                       String "line"], []), 99, [DeprecatedBy "part_add"],
   [],
   "modify a single partition on a block device",
   "\
This runs L<sfdisk(8)> option to modify just the single
partition C<n> (note: C<n> counts from 1).

For other parameters, see C<guestfs_sfdisk>.  You should usually
pass C<0> for the cyls/heads/sectors parameters.

See also: C<guestfs_part_add>");

  ("sfdisk_l", (RString "partitions", [Device "device"], []), 100, [DeprecatedBy "part_list"],
   [],
   "display the partition table",
   "\
This displays the partition table on C<device>, in the
human-readable output of the L<sfdisk(8)> command.  It is
not intended to be parsed.

See also: C<guestfs_part_list>");

  ("sfdisk_kernel_geometry", (RString "partitions", [Device "device"], []), 101, [],
   [],
   "display the kernel geometry",
   "\
This displays the kernel's idea of the geometry of C<device>.

The result is in human-readable format, and not designed to
be parsed.");

  ("sfdisk_disk_geometry", (RString "partitions", [Device "device"], []), 102, [],
   [],
   "display the disk geometry from the partition table",
   "\
This displays the disk geometry of C<device> read from the
partition table.  Especially in the case where the underlying
block device has been resized, this can be different from the
kernel's idea of the geometry (see C<guestfs_sfdisk_kernel_geometry>).

The result is in human-readable format, and not designed to
be parsed.");

  ("vg_activate_all", (RErr, [Bool "activate"], []), 103, [Optional "lvm2"],
   [],
   "activate or deactivate all volume groups",
   "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in all volume groups.

This command is the same as running C<vgchange -a y|n>");

  ("vg_activate", (RErr, [Bool "activate"; StringList "volgroups"], []), 104, [Optional "lvm2"],
   [],
   "activate or deactivate some volume groups",
   "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in the listed volume groups C<volgroups>.

This command is the same as running C<vgchange -a y|n volgroups...>

Note that if C<volgroups> is an empty list then B<all> volume groups
are activated or deactivated.");

  ("lvresize", (RErr, [Device "device"; Int "mbytes"], []), 105, [Optional "lvm2"],
   [InitNone, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV"; "VG"; "10"];
       ["mkfs"; "ext2"; "/dev/VG/LV"];
       ["mount_options"; ""; "/dev/VG/LV"; "/"];
       ["write"; "/new"; "test content"];
       ["umount"; "/"];
       ["lvresize"; "/dev/VG/LV"; "20"];
       ["e2fsck_f"; "/dev/VG/LV"];
       ["e2fsck"; "/dev/VG/LV"; "true"; "false"];
       ["e2fsck"; "/dev/VG/LV"; "false"; "true"];
       ["resize2fs"; "/dev/VG/LV"];
       ["mount_options"; ""; "/dev/VG/LV"; "/"];
       ["cat"; "/new"]], "test content");
    InitNone, Always, TestRun (
      (* Make an LV smaller to test RHBZ#587484. *)
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV"; "VG"; "20"];
       ["lvresize"; "/dev/VG/LV"; "10"]])],
   "resize an LVM logical volume",
   "\
This resizes (expands or shrinks) an existing LVM logical
volume to C<mbytes>.  When reducing, data in the reduced part
is lost.");

  ("resize2fs", (RErr, [Device "device"], []), 106, [],
   [], (* lvresize tests this *)
   "resize an ext2, ext3 or ext4 filesystem",
   "\
This resizes an ext2, ext3 or ext4 filesystem to match the size of
the underlying device.

I<Note:> It is sometimes required that you run C<guestfs_e2fsck_f>
on the C<device> before calling this command.  For unknown reasons
C<resize2fs> sometimes gives an error about this and sometimes not.
In any case, it is always safe to call C<guestfs_e2fsck_f> before
calling this function.");

  ("find", (RStringList "names", [Pathname "directory"], []), 107, [ProtocolLimitWarning],
   [InitBasicFS, Always, TestOutputList (
      [["find"; "/"]], ["lost+found"]);
    InitBasicFS, Always, TestOutputList (
      [["touch"; "/a"];
       ["mkdir"; "/b"];
       ["touch"; "/b/c"];
       ["find"; "/"]], ["a"; "b"; "b/c"; "lost+found"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir_p"; "/find/b/c"];
       ["touch"; "/find/b/c/d"];
       ["find"; "/find/b/"]], ["c"; "c/d"])],
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

  ("e2fsck_f", (RErr, [Device "device"], []), 108, [],
   [], (* lvresize tests this *)
   "check an ext2/ext3 filesystem",
   "\
This runs C<e2fsck -p -f device>, ie. runs the ext2/ext3
filesystem checker on C<device>, noninteractively (I<-p>),
even if the filesystem appears to be clean (I<-f>).

This command is only needed because of C<guestfs_resize2fs>
(q.v.).  Normally you should use C<guestfs_fsck>.");

  ("sleep", (RErr, [Int "secs"], []), 109, [],
   [InitNone, Always, TestRun (
      [["sleep"; "1"]])],
   "sleep for some seconds",
   "\
Sleep for C<secs> seconds.");

  ("ntfs_3g_probe", (RInt "status", [Bool "rw"; Device "device"], []), 110, [Optional "ntfs3g"],
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

  ("sh", (RString "output", [String "command"], []), 111, [],
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

  ("sh_lines", (RStringList "lines", [String "command"], []), 112, [],
   [], (* XXX needs tests *)
   "run a command via the shell returning lines",
   "\
This is the same as C<guestfs_sh>, but splits the result
into a list of lines.

See also: C<guestfs_command_lines>");

  ("glob_expand", (RStringList "paths", [Pathname "pattern"], []), 113, [],
   (* Use Pathname here, and hence ABS_PATH (pattern,... in generated
    * code in stubs.c, since all valid glob patterns must start with "/".
    * There is no concept of "cwd" in libguestfs, hence no "."-relative names.
    *)
   [InitScratchFS, Always, TestOutputList (
      [["mkdir_p"; "/glob_expand/b/c"];
       ["touch"; "/glob_expand/b/c/d"];
       ["touch"; "/glob_expand/b/c/e"];
       ["glob_expand"; "/glob_expand/b/c/*"]], ["/glob_expand/b/c/d"; "/glob_expand/b/c/e"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir_p"; "/glob_expand2/b/c"];
       ["touch"; "/glob_expand2/b/c/d"];
       ["touch"; "/glob_expand2/b/c/e"];
       ["glob_expand"; "/glob_expand2/*/c/*"]], ["/glob_expand2/b/c/d"; "/glob_expand2/b/c/e"]);
    InitScratchFS, Always, TestOutputList (
      [["mkdir_p"; "/glob_expand3/b/c"];
       ["touch"; "/glob_expand3/b/c/d"];
       ["touch"; "/glob_expand3/b/c/e"];
       ["glob_expand"; "/glob_expand3/*/x/*"]], [])],
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

  ("scrub_device", (RErr, [Device "device"], []), 114, [Optional "scrub"],
   [InitNone, Always, TestRun (	(* use /dev/sdc because it's smaller *)
      [["scrub_device"; "/dev/sdc"]])],
   "scrub (securely wipe) a device",
   "\
This command writes patterns over C<device> to make data retrieval
more difficult.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details.");

  ("scrub_file", (RErr, [Pathname "file"], []), 115, [Optional "scrub"],
   [InitScratchFS, Always, TestRun (
      [["write"; "/scrub_file"; "content"];
       ["scrub_file"; "/scrub_file"]])],
   "scrub (securely wipe) a file",
   "\
This command writes patterns over a file to make data retrieval
more difficult.

The file is I<removed> after scrubbing.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details.");

  ("scrub_freespace", (RErr, [Pathname "dir"], []), 116, [Optional "scrub"],
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

  ("mkdtemp", (RString "dir", [Pathname "template"], []), 117, [],
   [InitScratchFS, Always, TestRun (
      [["mkdir"; "/mkdtemp"];
       ["mkdtemp"; "/mkdtemp/tmpXXXXXX"]])],
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

  ("wc_l", (RInt "lines", [Pathname "path"], []), 118, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_l"; "/10klines"]], 10000);
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestOutputInt (
      [["wc_l"; "/abssymlink"]], 10000)],
   "count lines in a file",
   "\
This command counts the lines in a file, using the
C<wc -l> external command.");

  ("wc_w", (RInt "words", [Pathname "path"], []), 119, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_w"; "/10klines"]], 10000)],
   "count words in a file",
   "\
This command counts the words in a file, using the
C<wc -w> external command.");

  ("wc_c", (RInt "chars", [Pathname "path"], []), 120, [],
   [InitISOFS, Always, TestOutputInt (
      [["wc_c"; "/100kallspaces"]], 102400)],
   "count characters in a file",
   "\
This command counts the characters in a file, using the
C<wc -c> external command.");

  ("head", (RStringList "lines", [Pathname "path"], []), 121, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["head"; "/10klines"]], ["0abcdefghijklmnopqrstuvwxyz";"1abcdefghijklmnopqrstuvwxyz";"2abcdefghijklmnopqrstuvwxyz";"3abcdefghijklmnopqrstuvwxyz";"4abcdefghijklmnopqrstuvwxyz";"5abcdefghijklmnopqrstuvwxyz";"6abcdefghijklmnopqrstuvwxyz";"7abcdefghijklmnopqrstuvwxyz";"8abcdefghijklmnopqrstuvwxyz";"9abcdefghijklmnopqrstuvwxyz"]);
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestOutputList (
      [["head"; "/abssymlink"]], ["0abcdefghijklmnopqrstuvwxyz";"1abcdefghijklmnopqrstuvwxyz";"2abcdefghijklmnopqrstuvwxyz";"3abcdefghijklmnopqrstuvwxyz";"4abcdefghijklmnopqrstuvwxyz";"5abcdefghijklmnopqrstuvwxyz";"6abcdefghijklmnopqrstuvwxyz";"7abcdefghijklmnopqrstuvwxyz";"8abcdefghijklmnopqrstuvwxyz";"9abcdefghijklmnopqrstuvwxyz"])],
   "return first 10 lines of a file",
   "\
This command returns up to the first 10 lines of a file as
a list of strings.");

  ("head_n", (RStringList "lines", [Int "nrlines"; Pathname "path"], []), 122, [ProtocolLimitWarning],
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

  ("tail", (RStringList "lines", [Pathname "path"], []), 123, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["tail"; "/10klines"]], ["9990abcdefghijklmnopqrstuvwxyz";"9991abcdefghijklmnopqrstuvwxyz";"9992abcdefghijklmnopqrstuvwxyz";"9993abcdefghijklmnopqrstuvwxyz";"9994abcdefghijklmnopqrstuvwxyz";"9995abcdefghijklmnopqrstuvwxyz";"9996abcdefghijklmnopqrstuvwxyz";"9997abcdefghijklmnopqrstuvwxyz";"9998abcdefghijklmnopqrstuvwxyz";"9999abcdefghijklmnopqrstuvwxyz"])],
   "return last 10 lines of a file",
   "\
This command returns up to the last 10 lines of a file as
a list of strings.");

  ("tail_n", (RStringList "lines", [Int "nrlines"; Pathname "path"], []), 124, [ProtocolLimitWarning],
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

  ("df", (RString "output", [], []), 125, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'df' command and other imponderables.
        *)
   "report file system disk space usage",
   "\
This command runs the C<df> command to report disk space used.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<guestfs_statvfs> from programs.");

  ("df_h", (RString "output", [], []), 126, [],
   [], (* XXX Tricky to test because it depends on the exact format
        * of the 'df' command and other imponderables.
        *)
   "report file system disk space usage (human readable)",
   "\
This command runs the C<df -h> command to report disk space used
in human-readable format.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<guestfs_statvfs> from programs.");

  ("du", (RInt64 "sizekb", [Pathname "path"], []), 127, [Progress],
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

  ("initrd_list", (RStringList "filenames", [Pathname "path"], []), 128, [],
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

  ("mount_loop", (RErr, [Pathname "file"; Pathname "mountpoint"], []), 129, [],
   [],
   "mount a file using the loop device",
   "\
This command lets you mount C<file> (a filesystem image
in a file) on a mount point.  It is entirely equivalent to
the command C<mount -o loop file mountpoint>.");

  ("mkswap", (RErr, [Device "device"], []), 130, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkswap"; "/dev/sda1"]])],
   "create a swap partition",
   "\
Create a swap partition on C<device>.");

  ("mkswap_L", (RErr, [String "label"; Device "device"], []), 131, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkswap_L"; "hello"; "/dev/sda1"]])],
   "create a swap partition with a label",
   "\
Create a swap partition on C<device> with label C<label>.

Note that you cannot attach a swap label to a block device
(eg. C</dev/sda>), just to a partition.  This appears to be
a limitation of the kernel or swap tools.");

  ("mkswap_U", (RErr, [String "uuid"; Device "device"], []), 132, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestRun (
       [["part_disk"; "/dev/sda"; "mbr"];
        ["mkswap_U"; uuid; "/dev/sda1"]])]),
   "create a swap partition with an explicit UUID",
   "\
Create a swap partition on C<device> with UUID C<uuid>.");

  ("mknod", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], []), 133, [Optional "mknod"],
   [InitScratchFS, Always, TestOutputStruct (
      [["mknod"; "0o10777"; "0"; "0"; "/mknod"];
       (* NB: default umask 022 means 0777 -> 0755 in these tests *)
       ["stat"; "/mknod"]], [CompareWithInt ("mode", 0o10755)]);
    InitScratchFS, Always, TestOutputStruct (
      [["mknod"; "0o60777"; "66"; "99"; "/mknod2"];
       ["stat"; "/mknod2"]], [CompareWithInt ("mode", 0o60755)])],
   "make block, character or FIFO devices",
   "\
This call creates block or character special devices, or
named pipes (FIFOs).

The C<mode> parameter should be the mode, using the standard
constants.  C<devmajor> and C<devminor> are the
device major and minor numbers, only used when creating block
and character special devices.

Note that, just like L<mknod(2)>, the mode must be bitwise
OR'd with S_IFBLK, S_IFCHR, S_IFIFO or S_IFSOCK (otherwise this call
just creates a regular file).  These constants are
available in the standard Linux header files, or you can use
C<guestfs_mknod_b>, C<guestfs_mknod_c> or C<guestfs_mkfifo>
which are wrappers around this command which bitwise OR
in the appropriate constant for you.

The mode actually set is affected by the umask.");

  ("mkfifo", (RErr, [Int "mode"; Pathname "path"], []), 134, [Optional "mknod"],
   [InitScratchFS, Always, TestOutputStruct (
      [["mkfifo"; "0o777"; "/mkfifo"];
       ["stat"; "/mkfifo"]], [CompareWithInt ("mode", 0o10755)])],
   "make FIFO (named pipe)",
   "\
This call creates a FIFO (named pipe) called C<path> with
mode C<mode>.  It is just a convenient wrapper around
C<guestfs_mknod>.

The mode actually set is affected by the umask.");

  ("mknod_b", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], []), 135, [Optional "mknod"],
   [InitScratchFS, Always, TestOutputStruct (
      [["mknod_b"; "0o777"; "99"; "66"; "/mknod_b"];
       ["stat"; "/mknod_b"]], [CompareWithInt ("mode", 0o60755)])],
   "make block device node",
   "\
This call creates a block device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.

The mode actually set is affected by the umask.");

  ("mknod_c", (RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], []), 136, [Optional "mknod"],
   [InitScratchFS, Always, TestOutputStruct (
      [["mknod_c"; "0o777"; "99"; "66"; "/mknod_c"];
       ["stat"; "/mknod_c"]], [CompareWithInt ("mode", 0o20755)])],
   "make char device node",
   "\
This call creates a char device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.

The mode actually set is affected by the umask.");

  ("umask", (RInt "oldmask", [Int "mask"], []), 137, [FishOutput FishOutputOctal],
   [InitEmpty, Always, TestOutputInt (
      [["umask"; "0o22"]], 0o22)],
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

See also C<guestfs_get_umask>,
L<umask(2)>, C<guestfs_mknod>, C<guestfs_mkdir>.

This call returns the previous umask.");

  ("readdir", (RStructList ("entries", "dirent"), [Pathname "dir"], []), 138, [],
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

The L<readdir(3)> call returned a C<d_type> field with an
unexpected value

=back

This function is primarily intended for use by programs.  To
get a simple list of names, use C<guestfs_ls>.  To get a printable
directory for human consumption, use C<guestfs_ll>.");

  ("sfdiskM", (RErr, [Device "device"; StringList "lines"], []), 139, [DeprecatedBy "part_add"],
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

  ("zfile", (RString "description", [String "meth"; Pathname "path"], []), 140, [DeprecatedBy "file"],
   [],
   "determine file type inside a compressed file",
   "\
This command runs C<file> after first decompressing C<path>
using C<method>.

C<method> must be one of C<gzip>, C<compress> or C<bzip2>.

Since 1.0.63, use C<guestfs_file> instead which can now
process compressed files.");

  ("getxattrs", (RStructList ("xattrs", "xattr"), [Pathname "path"], []), 141, [Optional "linuxxattrs"],
   [],
   "list extended attributes of a file or directory",
   "\
This call lists the extended attributes of the file or directory
C<path>.

At the system call level, this is a combination of the
L<listxattr(2)> and L<getxattr(2)> calls.

See also: C<guestfs_lgetxattrs>, L<attr(5)>.");

  ("lgetxattrs", (RStructList ("xattrs", "xattr"), [Pathname "path"], []), 142, [Optional "linuxxattrs"],
   [],
   "list extended attributes of a file or directory",
   "\
This is the same as C<guestfs_getxattrs>, but if C<path>
is a symbolic link, then it returns the extended attributes
of the link itself.");

  ("setxattr", (RErr, [String "xattr";
                       String "val"; Int "vallen"; (* will be BufferIn *)
                       Pathname "path"], []), 143, [Optional "linuxxattrs"],
   [],
   "set extended attribute of a file or directory",
   "\
This call sets the extended attribute named C<xattr>
of the file C<path> to the value C<val> (of length C<vallen>).
The value is arbitrary 8 bit data.

See also: C<guestfs_lsetxattr>, L<attr(5)>.");

  ("lsetxattr", (RErr, [String "xattr";
                        String "val"; Int "vallen"; (* will be BufferIn *)
                        Pathname "path"], []), 144, [Optional "linuxxattrs"],
   [],
   "set extended attribute of a file or directory",
   "\
This is the same as C<guestfs_setxattr>, but if C<path>
is a symbolic link, then it sets an extended attribute
of the link itself.");

  ("removexattr", (RErr, [String "xattr"; Pathname "path"], []), 145, [Optional "linuxxattrs"],
   [],
   "remove extended attribute of a file or directory",
   "\
This call removes the extended attribute named C<xattr>
of the file C<path>.

See also: C<guestfs_lremovexattr>, L<attr(5)>.");

  ("lremovexattr", (RErr, [String "xattr"; Pathname "path"], []), 146, [Optional "linuxxattrs"],
   [],
   "remove extended attribute of a file or directory",
   "\
This is the same as C<guestfs_removexattr>, but if C<path>
is a symbolic link, then it removes an extended attribute
of the link itself.");

  ("mountpoints", (RHashtable "mps", [], []), 147, [],
   [],
   "show mountpoints",
   "\
This call is similar to C<guestfs_mounts>.  That call returns
a list of devices.  This one returns a hash table (map) of
device name to directory where the device is mounted.");

  ("mkmountpoint", (RErr, [String "exemptpath"], []), 148, [],
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
 mkmountpoint /sqsh
 mkmountpoint /ext3fs
 mount /dev/sda /cd
 mount-loop /cd/LiveOS/squashfs.img /sqsh
 mount-loop /sqsh/LiveOS/ext3fs.img /ext3fs

The inner filesystem is now unpacked under the /ext3fs mountpoint.

C<guestfs_mkmountpoint> is not compatible with C<guestfs_umount_all>.
You may get unexpected errors if you try to mix these calls.  It is
safest to manually unmount filesystems and remove mountpoints after use.

C<guestfs_umount_all> unmounts filesystems by sorting the paths
longest first, so for this to work for manual mountpoints, you
must ensure that the innermost mountpoints have the longest
pathnames, as in the example code above.

For more details see L<https://bugzilla.redhat.com/show_bug.cgi?id=599503>

Autosync [see C<guestfs_set_autosync>, this is set by default on
handles] can cause C<guestfs_umount_all> to be called when the handle
is closed which can also trigger these issues.");

  ("rmmountpoint", (RErr, [String "exemptpath"], []), 149, [],
   [],
   "remove a mountpoint",
   "\
This calls removes a mountpoint that was previously created
with C<guestfs_mkmountpoint>.  See C<guestfs_mkmountpoint>
for full details.");

  ("read_file", (RBufferOut "content", [Pathname "path"], []), 150, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputBuffer (
      [["read_file"; "/known-4"]], "abc\ndef\nghi");
    (* Test various near large, large and too large files (RHBZ#589039). *)
    InitScratchFS, Always, TestLastFail (
      [["touch"; "/read_file"];
       ["truncate_size"; "/read_file"; "4194303"]; (* GUESTFS_MESSAGE_MAX - 1 *)
       ["read_file"; "/read_file"]]);
    InitScratchFS, Always, TestLastFail (
      [["touch"; "/read_file2"];
       ["truncate_size"; "/read_file2"; "4194304"]; (* GUESTFS_MESSAGE_MAX *)
       ["read_file"; "/read_file2"]]);
    InitScratchFS, Always, TestLastFail (
      [["touch"; "/read_file3"];
       ["truncate_size"; "/read_file3"; "41943040"]; (* GUESTFS_MESSAGE_MAX * 10 *)
       ["read_file"; "/read_file3"]])],
   "read a file",
   "\
This calls returns the contents of the file C<path> as a
buffer.

Unlike C<guestfs_cat>, this function can correctly
handle files that contain embedded ASCII NUL characters.
However unlike C<guestfs_download>, this function is limited
in the total size of file that can be handled.");

  ("grep", (RStringList "lines", [String "regex"; Pathname "path"], []), 151, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["grep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"]);
    InitISOFS, Always, TestOutputList (
      [["grep"; "nomatch"; "/test-grep.txt"]], []);
    (* Test for RHBZ#579608, absolute symbolic links. *)
    InitISOFS, Always, TestOutputList (
      [["grep"; "nomatch"; "/abssymlink"]], [])],
   "return lines matching a pattern",
   "\
This calls the external C<grep> program and returns the
matching lines.");

  ("egrep", (RStringList "lines", [String "regex"; Pathname "path"], []), 152, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["egrep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<egrep> program and returns the
matching lines.");

  ("fgrep", (RStringList "lines", [String "pattern"; Pathname "path"], []), 153, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["fgrep"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<fgrep> program and returns the
matching lines.");

  ("grepi", (RStringList "lines", [String "regex"; Pathname "path"], []), 154, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["grepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<grep -i> program and returns the
matching lines.");

  ("egrepi", (RStringList "lines", [String "regex"; Pathname "path"], []), 155, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["egrepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<egrep -i> program and returns the
matching lines.");

  ("fgrepi", (RStringList "lines", [String "pattern"; Pathname "path"], []), 156, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["fgrepi"; "abc"; "/test-grep.txt"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<fgrep -i> program and returns the
matching lines.");

  ("zgrep", (RStringList "lines", [String "regex"; Pathname "path"], []), 157, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zgrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zgrep> program and returns the
matching lines.");

  ("zegrep", (RStringList "lines", [String "regex"; Pathname "path"], []), 158, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zegrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zegrep> program and returns the
matching lines.");

  ("zfgrep", (RStringList "lines", [String "pattern"; Pathname "path"], []), 159, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zfgrep"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"])],
   "return lines matching a pattern",
   "\
This calls the external C<zfgrep> program and returns the
matching lines.");

  ("zgrepi", (RStringList "lines", [String "regex"; Pathname "path"], []), 160, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zgrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zgrep -i> program and returns the
matching lines.");

  ("zegrepi", (RStringList "lines", [String "regex"; Pathname "path"], []), 161, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zegrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zegrep -i> program and returns the
matching lines.");

  ("zfgrepi", (RStringList "lines", [String "pattern"; Pathname "path"], []), 162, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputList (
      [["zfgrepi"; "abc"; "/test-grep.txt.gz"]], ["abc"; "abc123"; "ABC"])],
   "return lines matching a pattern",
   "\
This calls the external C<zfgrep -i> program and returns the
matching lines.");

  ("realpath", (RString "rpath", [Pathname "path"], []), 163, [Optional "realpath"],
   [InitISOFS, Always, TestOutput (
      [["realpath"; "/../directory"]], "/directory")],
   "canonicalized absolute pathname",
   "\
Return the canonicalized absolute pathname of C<path>.  The
returned path has no C<.>, C<..> or symbolic link path elements.");

  ("ln", (RErr, [String "target"; Pathname "linkname"], []), 164, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["mkdir"; "/ln"];
       ["touch"; "/ln/a"];
       ["ln"; "/ln/a"; "/ln/b"];
       ["stat"; "/ln/b"]], [CompareWithInt ("nlink", 2)])],
   "create a hard link",
   "\
This command creates a hard link using the C<ln> command.");

  ("ln_f", (RErr, [String "target"; Pathname "linkname"], []), 165, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["mkdir"; "/ln_f"];
       ["touch"; "/ln_f/a"];
       ["touch"; "/ln_f/b"];
       ["ln_f"; "/ln_f/a"; "/ln_f/b"];
       ["stat"; "/ln_f/b"]], [CompareWithInt ("nlink", 2)])],
   "create a hard link",
   "\
This command creates a hard link using the C<ln -f> command.
The I<-f> option removes the link (C<linkname>) if it exists already.");

  ("ln_s", (RErr, [String "target"; Pathname "linkname"], []), 166, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["mkdir"; "/ln_s"];
       ["touch"; "/ln_s/a"];
       ["ln_s"; "a"; "/ln_s/b"];
       ["lstat"; "/ln_s/b"]], [CompareWithInt ("mode", 0o120777)])],
   "create a symbolic link",
   "\
This command creates a symbolic link using the C<ln -s> command.");

  ("ln_sf", (RErr, [String "target"; Pathname "linkname"], []), 167, [],
   [InitScratchFS, Always, TestOutput (
      [["mkdir_p"; "/ln_sf/b"];
       ["touch"; "/ln_sf/b/c"];
       ["ln_sf"; "../d"; "/ln_sf/b/c"];
       ["readlink"; "/ln_sf/b/c"]], "../d")],
   "create a symbolic link",
   "\
This command creates a symbolic link using the C<ln -sf> command,
The I<-f> option removes the link (C<linkname>) if it exists already.");

  ("readlink", (RString "link", [Pathname "path"], []), 168, [],
   [] (* XXX tested above *),
   "read the target of a symbolic link",
   "\
This command reads the target of a symbolic link.");

  ("fallocate", (RErr, [Pathname "path"; Int "len"], []), 169, [DeprecatedBy "fallocate64"],
   [InitScratchFS, Always, TestOutputStruct (
      [["fallocate"; "/fallocate"; "1000000"];
       ["stat"; "/fallocate"]], [CompareWithInt ("size", 1_000_000)])],
   "preallocate a file in the guest filesystem",
   "\
This command preallocates a file (containing zero bytes) named
C<path> of size C<len> bytes.  If the file exists already, it
is overwritten.

Do not confuse this with the guestfish-specific
C<alloc> command which allocates a file in the host and
attaches it as a device.");

  ("swapon_device", (RErr, [Device "device"], []), 170, [],
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

  ("swapoff_device", (RErr, [Device "device"], []), 171, [],
   [], (* XXX tested by swapon_device *)
   "disable swap on device",
   "\
This command disables the libguestfs appliance swap
device or partition named C<device>.
See C<guestfs_swapon_device>.");

  ("swapon_file", (RErr, [Pathname "file"], []), 172, [],
   [InitScratchFS, Always, TestRun (
      [["fallocate"; "/swapon_file"; "8388608"];
       ["mkswap_file"; "/swapon_file"];
       ["swapon_file"; "/swapon_file"];
       ["swapoff_file"; "/swapon_file"];
       ["rm"; "/swapon_file"]])],
   "enable swap on file",
   "\
This command enables swap to a file.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_file", (RErr, [Pathname "file"], []), 173, [],
   [], (* XXX tested by swapon_file *)
   "disable swap on file",
   "\
This command disables the libguestfs appliance swap on file.");

  ("swapon_label", (RErr, [String "label"], []), 174, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkswap_L"; "swapit"; "/dev/sda1"];
       ["swapon_label"; "swapit"];
       ["swapoff_label"; "swapit"];
       ["zero"; "/dev/sda"];
       ["blockdev_rereadpt"; "/dev/sda"]])],
   "enable swap on labeled swap partition",
   "\
This command enables swap to a labeled swap partition.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_label", (RErr, [String "label"], []), 175, [],
   [], (* XXX tested by swapon_label *)
   "disable swap on labeled swap partition",
   "\
This command disables the libguestfs appliance swap on
labeled swap partition.");

  ("swapon_uuid", (RErr, [String "uuid"], []), 176, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestRun (
       [["mkswap_U"; uuid; "/dev/sdc"];
        ["swapon_uuid"; uuid];
        ["swapoff_uuid"; uuid]])]),
   "enable swap on swap partition by UUID",
   "\
This command enables swap to a swap partition with the given UUID.
See C<guestfs_swapon_device> for other notes.");

  ("swapoff_uuid", (RErr, [String "uuid"], []), 177, [Optional "linuxfsuuid"],
   [], (* XXX tested by swapon_uuid *)
   "disable swap on swap partition by UUID",
   "\
This command disables the libguestfs appliance swap partition
with the given UUID.");

  ("mkswap_file", (RErr, [Pathname "path"], []), 178, [],
   [InitScratchFS, Always, TestRun (
      [["fallocate"; "/mkswap_file"; "8388608"];
       ["mkswap_file"; "/mkswap_file"];
       ["rm"; "/mkswap_file"]])],
   "create a swap file",
   "\
Create a swap file.

This command just writes a swap file signature to an existing
file.  To create the file itself, use something like C<guestfs_fallocate>.");

  ("inotify_init", (RErr, [Int "maxevents"], []), 179, [Optional "inotify"],
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

  ("inotify_add_watch", (RInt64 "wd", [Pathname "path"; Int "mask"], []), 180, [Optional "inotify"],
   [InitScratchFS, Always, TestOutputList (
      [["mkdir"; "/inotify_add_watch"];
       ["inotify_init"; "0"];
       ["inotify_add_watch"; "/inotify_add_watch"; "1073741823"];
       ["touch"; "/inotify_add_watch/a"];
       ["touch"; "/inotify_add_watch/b"];
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

  ("inotify_rm_watch", (RErr, [Int(*XXX64*) "wd"], []), 181, [Optional "inotify"],
   [],
   "remove an inotify watch",
   "\
Remove a previously defined inotify watch.
See C<guestfs_inotify_add_watch>.");

  ("inotify_read", (RStructList ("events", "inotify_event"), [], []), 182, [Optional "inotify"],
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

  ("inotify_files", (RStringList "paths", [], []), 183, [Optional "inotify"],
   [],
   "return list of watched files that had events",
   "\
This function is a helpful wrapper around C<guestfs_inotify_read>
which just returns a list of pathnames of objects that were
touched.  The returned pathnames are sorted and deduplicated.");

  ("inotify_close", (RErr, [], []), 184, [Optional "inotify"],
   [],
   "close the inotify handle",
   "\
This closes the inotify handle which was previously
opened by inotify_init.  It removes all watches, throws
away any pending events, and deallocates all resources.");

  ("setcon", (RErr, [String "context"], []), 185, [Optional "selinux"],
   [],
   "set SELinux security context",
   "\
This sets the SELinux security context of the daemon
to the string C<context>.

See the documentation about SELINUX in L<guestfs(3)>.");

  ("getcon", (RString "context", [], []), 186, [Optional "selinux"],
   [],
   "get SELinux security context",
   "\
This gets the SELinux security context of the daemon.

See the documentation about SELINUX in L<guestfs(3)>,
and C<guestfs_setcon>");

  ("mkfs_b", (RErr, [String "fstype"; Int "blocksize"; Device "device"], []), 187, [DeprecatedBy "mkfs_opts"],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "ext2"; "4096"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["write"; "/new"; "new file contents"];
       ["cat"; "/new"]], "new file contents");
    InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "vfat"; "32768"; "/dev/sda1"]]);
    InitEmpty, Always, TestLastFail (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "vfat"; "32769"; "/dev/sda1"]]);
    InitEmpty, Always, TestLastFail (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "vfat"; "33280"; "/dev/sda1"]]);
    InitEmpty, IfAvailable "ntfsprogs", TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_b"; "ntfs"; "32768"; "/dev/sda1"]])],
   "make a filesystem with block size",
   "\
This call is similar to C<guestfs_mkfs>, but it allows you to
control the block size of the resulting filesystem.  Supported
block sizes depend on the filesystem type, but typically they
are C<1024>, C<2048> or C<4096> only.

For VFAT and NTFS the C<blocksize> parameter is treated as
the requested cluster size.");

  ("mke2journal", (RErr, [Int "blocksize"; Device "device"], []), 188, [],
   [InitEmpty, Always, TestOutput (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
       ["mke2journal"; "4096"; "/dev/sda1"];
       ["mke2fs_J"; "ext2"; "4096"; "/dev/sda2"; "/dev/sda1"];
       ["mount_options"; ""; "/dev/sda2"; "/"];
       ["write"; "/new"; "new file contents"];
       ["cat"; "/new"]], "new file contents")],
   "make ext2/3/4 external journal",
   "\
This creates an ext2 external journal on C<device>.  It is equivalent
to the command:

 mke2fs -O journal_dev -b blocksize device");

  ("mke2journal_L", (RErr, [Int "blocksize"; String "label"; Device "device"], []), 189, [],
   [InitEmpty, Always, TestOutput (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
       ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
       ["mke2journal_L"; "4096"; "JOURNAL"; "/dev/sda1"];
       ["mke2fs_JL"; "ext2"; "4096"; "/dev/sda2"; "JOURNAL"];
       ["mount_options"; ""; "/dev/sda2"; "/"];
       ["write"; "/new"; "new file contents"];
       ["cat"; "/new"]], "new file contents")],
   "make ext2/3/4 external journal with label",
   "\
This creates an ext2 external journal on C<device> with label C<label>.");

  ("mke2journal_U", (RErr, [Int "blocksize"; String "uuid"; Device "device"], []), 190, [Optional "linuxfsuuid"],
   (let uuid = uuidgen () in
    [InitEmpty, Always, TestOutput (
       [["part_init"; "/dev/sda"; "mbr"];
        ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
        ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
        ["mke2journal_U"; "4096"; uuid; "/dev/sda1"];
        ["mke2fs_JU"; "ext2"; "4096"; "/dev/sda2"; uuid];
        ["mount_options"; ""; "/dev/sda2"; "/"];
        ["write"; "/new"; "new file contents"];
        ["cat"; "/new"]], "new file contents")]),
   "make ext2/3/4 external journal with UUID",
   "\
This creates an ext2 external journal on C<device> with UUID C<uuid>.");

  ("mke2fs_J", (RErr, [String "fstype"; Int "blocksize"; Device "device"; Device "journal"], []), 191, [],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on C<journal>.  It is equivalent
to the command:

 mke2fs -t fstype -b blocksize -J device=<journal> <device>

See also C<guestfs_mke2journal>.");

  ("mke2fs_JL", (RErr, [String "fstype"; Int "blocksize"; Device "device"; String "label"], []), 192, [],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal labeled C<label>.

See also C<guestfs_mke2journal_L>.");

  ("mke2fs_JU", (RErr, [String "fstype"; Int "blocksize"; Device "device"; String "uuid"], []), 193, [Optional "linuxfsuuid"],
   [],
   "make ext2/3/4 filesystem with external journal",
   "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal with UUID C<uuid>.

See also C<guestfs_mke2journal_U>.");

  ("modprobe", (RErr, [String "modulename"], []), 194, [Optional "linuxmodules"],
   [InitNone, Always, TestRun [["modprobe"; "fat"]]],
   "load a kernel module",
   "\
This loads a kernel module in the appliance.

The kernel module must have been whitelisted when libguestfs
was built (see C<appliance/kmod.whitelist.in> in the source).");

  ("echo_daemon", (RString "output", [StringList "words"], []), 195, [],
   [InitNone, Always, TestOutput (
      [["echo_daemon"; "This is a test"]], "This is a test"
    )],
   "echo arguments back to the client",
   "\
This command concatenates the list of C<words> passed with single spaces
between them and returns the resulting string.

You can use this command to test the connection through to the daemon.

See also C<guestfs_ping_daemon>.");

  ("find0", (RErr, [Pathname "directory"; FileOut "files"], []), 196,
   [Cancellable],
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

  ("case_sensitive_path", (RString "rpath", [Pathname "path"], []), 197, [],
   [InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/DIRECTORY"]], "/directory");
    InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/DIRECTORY/"]], "/directory");
    InitISOFS, Always, TestOutput (
      [["case_sensitive_path"; "/Known-1"]], "/known-1");
    InitISOFS, Always, TestLastFail (
      [["case_sensitive_path"; "/Known-1/"]]);
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/case_sensitive_path"];
       ["mkdir"; "/case_sensitive_path/bbb"];
       ["touch"; "/case_sensitive_path/bbb/c"];
       ["case_sensitive_path"; "/CASE_SENSITIVE_path/bbB/C"]], "/case_sensitive_path/bbb/c");
    InitScratchFS, Always, TestOutput (
      [["mkdir"; "/case_sensitive_path2"];
       ["mkdir"; "/case_sensitive_path2/bbb"];
       ["touch"; "/case_sensitive_path2/bbb/c"];
       ["case_sensitive_path"; "/case_sensitive_PATH2////bbB/C"]], "/case_sensitive_path2/bbb/c");
    InitScratchFS, Always, TestLastFail (
      [["mkdir"; "/case_sensitive_path3"];
       ["mkdir"; "/case_sensitive_path3/bbb"];
       ["touch"; "/case_sensitive_path3/bbb/c"];
       ["case_sensitive_path"; "/case_SENSITIVE_path3/bbb/../bbb/C"]])],
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

  ("vfs_type", (RString "fstype", [Device "device"], []), 198, [],
   [InitScratchFS, Always, TestOutput (
      [["vfs_type"; "/dev/sdb1"]], "ext2")],
   "get the Linux VFS type corresponding to a mounted device",
   "\
This command gets the filesystem type corresponding to
the filesystem on C<device>.

For most filesystems, the result is the name of the Linux
VFS module which would be used to mount this filesystem
if you mounted it without specifying the filesystem type.
For example a string such as C<ext3> or C<ntfs>.");

  ("truncate", (RErr, [Pathname "path"], []), 199, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["write"; "/truncate"; "some stuff so size is not zero"];
       ["truncate"; "/truncate"];
       ["stat"; "/truncate"]], [CompareWithInt ("size", 0)])],
   "truncate a file to zero size",
   "\
This command truncates C<path> to a zero-length file.  The
file must exist already.");

  ("truncate_size", (RErr, [Pathname "path"; Int64 "size"], []), 200, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["touch"; "/truncate_size"];
       ["truncate_size"; "/truncate_size"; "1000"];
       ["stat"; "/truncate_size"]], [CompareWithInt ("size", 1000)])],
   "truncate a file to a particular size",
   "\
This command truncates C<path> to size C<size> bytes.  The file
must exist already.

If the current file size is less than C<size> then
the file is extended to the required size with zero bytes.
This creates a sparse file (ie. disk blocks are not allocated
for the file until you write to it).  To create a non-sparse
file of zeroes, use C<guestfs_fallocate64> instead.");

  ("utimens", (RErr, [Pathname "path"; Int64 "atsecs"; Int64 "atnsecs"; Int64 "mtsecs"; Int64 "mtnsecs"], []), 201, [],
   (* Test directories, named pipes etc (RHBZ#761451, RHBZ#761460) *)
   [InitScratchFS, Always, TestOutputStruct (
      [["touch"; "/utimens-file"];
       ["utimens"; "/utimens-file"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-file"]], [CompareWithInt ("mtime", 9876)]);
    InitScratchFS, Always, TestOutputStruct (
      [["mkdir"; "/utimens-dir"];
       ["utimens"; "/utimens-dir"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-dir"]], [CompareWithInt ("mtime", 9876)]);
    InitScratchFS, Always, TestOutputStruct (
      [["mkfifo"; "0o644"; "/utimens-fifo"];
       ["utimens"; "/utimens-fifo"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-fifo"]], [CompareWithInt ("mtime", 9876)]);
    InitScratchFS, Always, TestOutputStruct (
      [["ln_sf"; "/utimens-file"; "/utimens-link"];
       ["utimens"; "/utimens-link"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-link"]], [CompareWithInt ("mtime", 9876)]);
    InitScratchFS, Always, TestOutputStruct (
      [["mknod_b"; "0o644"; "8"; "0"; "/utimens-block"];
       ["utimens"; "/utimens-block"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-block"]], [CompareWithInt ("mtime", 9876)]);
    InitScratchFS, Always, TestOutputStruct (
      [["mknod_c"; "0o644"; "1"; "3"; "/utimens-char"];
       ["utimens"; "/utimens-char"; "12345"; "67890"; "9876"; "5432"];
       ["stat"; "/utimens-char"]], [CompareWithInt ("mtime", 9876)])],
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

  ("mkdir_mode", (RErr, [Pathname "path"; Int "mode"], []), 202, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["mkdir_mode"; "/mkdir_mode"; "0o111"];
       ["stat"; "/mkdir_mode"]], [CompareWithInt ("mode", 0o40111)])],
   "create a directory with a particular mode",
   "\
This command creates a directory, setting the initial permissions
of the directory to C<mode>.

For common Linux filesystems, the actual mode which is set will
be C<mode & ~umask & 01777>.  Non-native-Linux filesystems may
interpret the mode in other ways.

See also C<guestfs_mkdir>, C<guestfs_umask>");

  ("lchown", (RErr, [Int "owner"; Int "group"; Pathname "path"], []), 203, [],
   [], (* XXX *)
   "change file owner and group",
   "\
Change the file owner to C<owner> and group to C<group>.
This is like C<guestfs_chown> but if C<path> is a symlink then
the link itself is changed, not the target.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy).");

  ("lstatlist", (RStructList ("statbufs", "stat"), [Pathname "path"; StringList "names"], []), 204, [],
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

  ("lxattrlist", (RStructList ("xattrs", "xattr"), [Pathname "path"; StringList "names"], []), 205, [Optional "linuxxattrs"],
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

  ("readlinklist", (RStringList "links", [Pathname "path"; StringList "names"], []), 206, [],
   [], (* XXX *)
   "readlink on multiple files",
   "\
This call allows you to do a C<readlink> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of strings, with a one-to-one
correspondence to the C<names> list.  Each string is the
value of the symbolic link.

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

  ("pread", (RBufferOut "content", [Pathname "path"; Int "count"; Int64 "offset"], []), 207, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputBuffer (
      [["pread"; "/known-4"; "1"; "3"]], "\n");
    InitISOFS, Always, TestOutputBuffer (
      [["pread"; "/empty"; "0"; "100"]], "")],
   "read part of a file",
   "\
This command lets you read part of a file.  It reads C<count>
bytes of the file, starting at C<offset>, from file C<path>.

This may read fewer bytes than requested.  For further details
see the L<pread(2)> system call.

See also C<guestfs_pwrite>, C<guestfs_pread_device>.");

  ("part_init", (RErr, [Device "device"; String "parttype"], []), 208, [],
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

=item B<efi>

=item B<gpt>

Intel EFI / GPT partition table.

This is recommended for >= 2 TB partitions that will be accessed
from Linux and Intel-based Mac OS X.  It also has limited backwards
compatibility with the C<mbr> format.

=item B<mbr>

=item B<msdos>

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

=item B<amiga>

=item B<rdb>

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

  ("part_add", (RErr, [Device "device"; String "prlogex"; Int64 "startsect"; Int64 "endsect"], []), 209, [],
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

  ("part_disk", (RErr, [Device "device"; String "parttype"], []), 210, [],
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

  ("part_set_bootable", (RErr, [Device "device"; Int "partnum"; Bool "bootable"], []), 211, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["part_set_bootable"; "/dev/sda"; "1"; "true"]])],
   "make a partition bootable",
   "\
This sets the bootable flag on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The bootable flag is used by some operating systems (notably
Windows) to determine which partition to boot from.  It is by
no means universally recognized.");

  ("part_set_name", (RErr, [Device "device"; Int "partnum"; String "name"], []), 212, [],
   [InitEmpty, Always, TestRun (
      [["part_disk"; "/dev/sda"; "gpt"];
       ["part_set_name"; "/dev/sda"; "1"; "thepartname"]])],
   "set partition name",
   "\
This sets the partition name on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The partition name can only be set on certain types of partition
table.  This works on C<gpt> but not on C<mbr> partitions.");

  ("part_list", (RStructList ("partitions", "partition"), [Device "device"], []), 213, [],
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

  ("part_get_parttype", (RString "parttype", [Device "device"], []), 214, [],
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

  ("fill", (RErr, [Int "c"; Int "len"; Pathname "path"], []), 215, [Progress],
   [InitScratchFS, Always, TestOutputBuffer (
      [["fill"; "0x63"; "10"; "/fill"];
       ["read_file"; "/fill"]], "cccccccccc")],
   "fill a file with octets",
   "\
This command creates a new file called C<path>.  The initial
content of the file is C<len> octets of C<c>, where C<c>
must be a number in the range C<[0..255]>.

To fill a file with zero bytes (sparsely), it is
much more efficient to use C<guestfs_truncate_size>.
To create a file with a pattern of repeating bytes
use C<guestfs_fill_pattern>.");

  ("available", (RErr, [StringList "groups"], []), 216, [],
   [InitNone, Always, TestRun [["available"; ""]]],
   "test availability of some parts of the API",
   "\
This command is used to check the availability of some
groups of functionality in the appliance, which not all builds of
the libguestfs appliance will be able to provide.

The libguestfs groups, and the functions that those
groups correspond to, are listed in L<guestfs(3)/AVAILABILITY>.
You can also fetch this list at runtime by calling
C<guestfs_available_all_groups>.

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

  ("dd", (RErr, [Dev_or_Path "src"; Dev_or_Path "dest"], []), 217, [DeprecatedBy "copy_device_to_device"],
   [InitScratchFS, Always, TestOutputBuffer (
      [["mkdir"; "/dd"];
       ["write"; "/dd/src"; "hello, world"];
       ["dd"; "/dd/src"; "/dd/dest"];
       ["read_file"; "/dd/dest"]], "hello, world")],
   "copy from source to destination using dd",
   "\
This command copies from one source device or file C<src>
to another destination device or file C<dest>.  Normally you
would use this to copy to or from a device or partition, for
example to duplicate a filesystem.

If the destination is a device, it must be as large or larger
than the source file or device, otherwise the copy will fail.
This command cannot do partial copies
(see C<guestfs_copy_device_to_device>).");

  ("filesize", (RInt64 "size", [Pathname "file"], []), 218, [],
   [InitScratchFS, Always, TestOutputInt (
      [["write"; "/filesize"; "hello, world"];
       ["filesize"; "/filesize"]], 12)],
   "return the size of the file in bytes",
   "\
This command returns the size of C<file> in bytes.

To get other stats about a file, use C<guestfs_stat>, C<guestfs_lstat>,
C<guestfs_is_dir>, C<guestfs_is_file> etc.
To get the size of block devices, use C<guestfs_blockdev_getsize64>.");

  ("lvrename", (RErr, [String "logvol"; String "newlogvol"], []), 219, [],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["lvrename"; "/dev/VG/LV"; "/dev/VG/LV2"];
       ["lvs"]], ["/dev/VG/LV2"])],
   "rename an LVM logical volume",
   "\
Rename a logical volume C<logvol> with the new name C<newlogvol>.");

  ("vgrename", (RErr, [String "volgroup"; String "newvolgroup"], []), 220, [],
   [InitBasicFSonLVM, Always, TestOutputList (
      [["umount"; "/"];
       ["vg_activate"; "false"; "VG"];
       ["vgrename"; "VG"; "VG2"];
       ["vg_activate"; "true"; "VG2"];
       ["mount_options"; ""; "/dev/VG2/LV"; "/"];
       ["vgs"]], ["VG2"])],
   "rename an LVM volume group",
   "\
Rename a volume group C<volgroup> with the new name C<newvolgroup>.");

  ("initrd_cat", (RBufferOut "content", [Pathname "initrdpath"; String "filename"], []), 221, [ProtocolLimitWarning],
   [InitISOFS, Always, TestOutputBuffer (
      [["initrd_cat"; "/initrd"; "known-4"]], "abc\ndef\nghi")],
   "list the contents of a single file in an initrd",
   "\
This command unpacks the file C<filename> from the initrd file
called C<initrdpath>.  The filename must be given I<without> the
initial C</> character.

For example, in guestfish you could use the following command
to examine the boot script (usually called C</init>)
contained in a Linux initrd or initramfs image:

 initrd-cat /boot/initrd-<version>.img init

See also C<guestfs_initrd_list>.");

  ("pvuuid", (RString "uuid", [Device "device"], []), 222, [],
   [],
   "get the UUID of a physical volume",
   "\
This command returns the UUID of the LVM PV C<device>.");

  ("vguuid", (RString "uuid", [String "vgname"], []), 223, [],
   [],
   "get the UUID of a volume group",
   "\
This command returns the UUID of the LVM VG named C<vgname>.");

  ("lvuuid", (RString "uuid", [Device "device"], []), 224, [],
   [],
   "get the UUID of a logical volume",
   "\
This command returns the UUID of the LVM LV C<device>.");

  ("vgpvuuids", (RStringList "uuids", [String "vgname"], []), 225, [],
   [],
   "get the PV UUIDs containing the volume group",
   "\
Given a VG called C<vgname>, this returns the UUIDs of all
the physical volumes that this volume group resides on.

You can use this along with C<guestfs_pvs> and C<guestfs_pvuuid>
calls to associate physical volumes and volume groups.

See also C<guestfs_vglvuuids>.");

  ("vglvuuids", (RStringList "uuids", [String "vgname"], []), 226, [],
   [],
   "get the LV UUIDs of all LVs in the volume group",
   "\
Given a VG called C<vgname>, this returns the UUIDs of all
the logical volumes created in this volume group.

You can use this along with C<guestfs_lvs> and C<guestfs_lvuuid>
calls to associate logical volumes and volume groups.

See also C<guestfs_vgpvuuids>.");

  ("copy_size", (RErr, [Dev_or_Path "src"; Dev_or_Path "dest"; Int64 "size"], []), 227, [Progress; DeprecatedBy "copy_device_to_device"],
   [InitScratchFS, Always, TestOutputBuffer (
      [["mkdir"; "/copy_size"];
       ["write"; "/copy_size/src"; "hello, world"];
       ["copy_size"; "/copy_size/src"; "/copy_size/dest"; "5"];
       ["read_file"; "/copy_size/dest"]], "hello")],
   "copy size bytes from source to destination using dd",
   "\
This command copies exactly C<size> bytes from one source device
or file C<src> to another destination device or file C<dest>.

Note this will fail if the source is too short or if the destination
is not large enough.");

  ("zero_device", (RErr, [Device "device"], []), 228, [Progress],
   [InitBasicFSonLVM, Always, TestRun (
      [["zero_device"; "/dev/VG/LV"]])],
   "write zeroes to an entire device",
   "\
This command writes zeroes over the entire C<device>.  Compare
with C<guestfs_zero> which just zeroes the first few blocks of
a device.

If blocks are already zero, then this command avoids writing
zeroes.  This prevents the underlying device from becoming non-sparse
or growing unnecessarily.");

  ("txz_in", (RErr, [FileIn "tarball"; Pathname "directory"], []), 229,
   [Optional "xz"; Cancellable],
   [InitScratchFS, Always, TestOutput (
      [["mkdir"; "/txz_in"];
       ["txz_in"; "../data/helloworld.tar.xz"; "/txz_in"];
       ["cat"; "/txz_in/hello"]], "hello\n")],
   "unpack compressed tarball to directory",
   "\
This command uploads and unpacks local file C<tarball> (an
I<xz compressed> tar file) into C<directory>.");

  ("txz_out", (RErr, [Pathname "directory"; FileOut "tarball"], []), 230,
   [Optional "xz"; Cancellable],
   [],
   "pack directory into compressed tarball",
   "\
This command packs the contents of C<directory> and downloads
it to local file C<tarball> (as an xz compressed tar archive).");

  ("ntfsresize", (RErr, [Device "device"], []), 231, [Optional "ntfsprogs"; DeprecatedBy "ntfsresize_opts"],
   [],
   "resize an NTFS filesystem",
   "\
This command resizes an NTFS filesystem, expanding or
shrinking it to the size of the underlying device.

I<Note:> After the resize operation, the filesystem is marked
as requiring a consistency check (for safety).  You have to boot
into Windows to perform this check and clear this condition.
Furthermore, ntfsresize refuses to resize filesystems
which have been marked in this way.  So in effect it is
not possible to call ntfsresize multiple times on a single
filesystem without booting into Windows between each resize.

See also L<ntfsresize(8)>.");

  ("vgscan", (RErr, [], []), 232, [],
   [InitEmpty, Always, TestRun (
      [["vgscan"]])],
   "rescan for LVM physical volumes, volume groups and logical volumes",
   "\
This rescans all block devices and rebuilds the list of LVM
physical volumes, volume groups and logical volumes.");

  ("part_del", (RErr, [Device "device"; Int "partnum"], []), 233, [],
   [InitEmpty, Always, TestRun (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
       ["part_del"; "/dev/sda"; "1"]])],
   "delete a partition",
   "\
This command deletes the partition numbered C<partnum> on C<device>.

Note that in the case of MBR partitioning, deleting an
extended partition also deletes any logical partitions
it contains.");

  ("part_get_bootable", (RBool "bootable", [Device "device"; Int "partnum"], []), 234, [],
   [InitEmpty, Always, TestOutputTrue (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
       ["part_set_bootable"; "/dev/sda"; "1"; "true"];
       ["part_get_bootable"; "/dev/sda"; "1"]])],
   "return true if a partition is bootable",
   "\
This command returns true if the partition C<partnum> on
C<device> has the bootable flag set.

See also C<guestfs_part_set_bootable>.");

  ("part_get_mbr_id", (RInt "idbyte", [Device "device"; Int "partnum"], []), 235, [FishOutput FishOutputHexadecimal],
   [InitEmpty, Always, TestOutputInt (
      [["part_init"; "/dev/sda"; "mbr"];
       ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
       ["part_set_mbr_id"; "/dev/sda"; "1"; "0x7f"];
       ["part_get_mbr_id"; "/dev/sda"; "1"]], 0x7f)],
   "get the MBR type byte (ID byte) from a partition",
   "\
Returns the MBR type byte (also known as the ID byte) from
the numbered partition C<partnum>.

Note that only MBR (old DOS-style) partitions have type bytes.
You will get undefined results for other partition table
types (see C<guestfs_part_get_parttype>).");

  ("part_set_mbr_id", (RErr, [Device "device"; Int "partnum"; Int "idbyte"], []), 236, [],
   [], (* tested by part_get_mbr_id *)
   "set the MBR type byte (ID byte) of a partition",
   "\
Sets the MBR type byte (also known as the ID byte) of
the numbered partition C<partnum> to C<idbyte>.  Note
that the type bytes quoted in most documentation are
in fact hexadecimal numbers, but usually documented
without any leading \"0x\" which might be confusing.

Note that only MBR (old DOS-style) partitions have type bytes.
You will get undefined results for other partition table
types (see C<guestfs_part_get_parttype>).");

  ("checksum_device", (RString "checksum", [String "csumtype"; Device "device"], []), 237, [],
   [InitISOFS, Always, TestOutputFileMD5 (
      [["checksum_device"; "md5"; "/dev/sdd"]],
      "../data/test.iso")],
   "compute MD5, SHAx or CRC checksum of the contents of a device",
   "\
This call computes the MD5, SHAx or CRC checksum of the
contents of the device named C<device>.  For the types of
checksums supported see the C<guestfs_checksum> command.");

  ("lvresize_free", (RErr, [Device "lv"; Int "percent"], []), 238, [Optional "lvm2"],
   [InitNone, Always, TestRun (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["pvcreate"; "/dev/sda1"];
       ["vgcreate"; "VG"; "/dev/sda1"];
       ["lvcreate"; "LV"; "VG"; "10"];
       ["lvresize_free"; "/dev/VG/LV"; "100"]])],
   "expand an LV to fill free space",
   "\
This expands an existing logical volume C<lv> so that it fills
C<pc>% of the remaining free space in the volume group.  Commonly
you would call this with pc = 100 which expands the logical volume
as much as possible, using all remaining free space in the volume
group.");

  ("aug_clear", (RErr, [String "augpath"], []), 239, [Optional "augeas"],
   [], (* XXX Augeas code needs tests. *)
   "clear Augeas path",
   "\
Set the value associated with C<path> to C<NULL>.  This
is the same as the L<augtool(1)> C<clear> command.");

  ("get_umask", (RInt "mask", [], []), 240, [FishOutput FishOutputOctal],
   [InitEmpty, Always, TestOutputInt (
      [["get_umask"]], 0o22)],
   "get the current umask",
   "\
Return the current umask.  By default the umask is C<022>
unless it has been set by calling C<guestfs_umask>.");

  ("debug_upload", (RErr, [FileIn "filename"; String "tmpname"; Int "mode"], []), 241,
   [NotInDocs; Cancellable],
   [],
   "upload a file to the appliance (internal use only)",
   "\
The C<guestfs_debug_upload> command uploads a file to
the libguestfs appliance.

There is no comprehensive help for this command.  You have
to look at the file C<daemon/debug.c> in the libguestfs source
to find out what it is for.");

  ("base64_in", (RErr, [FileIn "base64file"; Pathname "filename"], []), 242,
   [Cancellable],
   [InitScratchFS, Always, TestOutput (
      [["base64_in"; "../data/hello.b64"; "/base64_in"];
       ["cat"; "/base64_in"]], "hello\n")],
   "upload base64-encoded data to file",
   "\
This command uploads base64-encoded data from C<base64file>
to C<filename>.");

  ("base64_out", (RErr, [Pathname "filename"; FileOut "base64file"], []), 243,
   [Cancellable],
   [],
   "download file and encode as base64",
   "\
This command downloads the contents of C<filename>, writing
it out to local file C<base64file> encoded as base64.");

  ("checksums_out", (RErr, [String "csumtype"; Pathname "directory"; FileOut "sumsfile"], []), 244,
  [Cancellable],
   [],
   "compute MD5, SHAx or CRC checksum of files in a directory",
   "\
This command computes the checksums of all regular files in
C<directory> and then emits a list of those checksums to
the local output file C<sumsfile>.

This can be used for verifying the integrity of a virtual
machine.  However to be properly secure you should pay
attention to the output of the checksum command (it uses
the ones from GNU coreutils).  In particular when the
filename is not printable, coreutils uses a special
backslash syntax.  For more information, see the GNU
coreutils info file.");

  ("fill_pattern", (RErr, [String "pattern"; Int "len"; Pathname "path"], []), 245, [Progress],
   [InitScratchFS, Always, TestOutputBuffer (
      [["fill_pattern"; "abcdefghijklmnopqrstuvwxyz"; "28"; "/fill_pattern"];
       ["read_file"; "/fill_pattern"]], "abcdefghijklmnopqrstuvwxyzab")],
   "fill a file with a repeating pattern of bytes",
   "\
This function is like C<guestfs_fill> except that it creates
a new file of length C<len> containing the repeating pattern
of bytes in C<pattern>.  The pattern is truncated if necessary
to ensure the length of the file is exactly C<len> bytes.");

  ("write", (RErr, [Pathname "path"; BufferIn "content"], []), 246, [ProtocolLimitWarning],
   [InitScratchFS, Always, TestOutput (
      [["write"; "/write"; "new file contents"];
       ["cat"; "/write"]], "new file contents");
    InitScratchFS, Always, TestOutput (
      [["write"; "/write2"; "\nnew file contents\n"];
       ["cat"; "/write2"]], "\nnew file contents\n");
    InitScratchFS, Always, TestOutput (
      [["write"; "/write3"; "\n\n"];
       ["cat"; "/write3"]], "\n\n");
    InitScratchFS, Always, TestOutput (
      [["write"; "/write4"; ""];
       ["cat"; "/write4"]], "");
    InitScratchFS, Always, TestOutput (
      [["write"; "/write5"; "\n\n\n"];
       ["cat"; "/write5"]], "\n\n\n");
    InitScratchFS, Always, TestOutput (
      [["write"; "/write6"; "\n"];
       ["cat"; "/write6"]], "\n")],
   "create a new file",
   "\
This call creates a file called C<path>.  The content of the
file is the string C<content> (which can contain any 8 bit data).

See also C<guestfs_write_append>.");

  ("pwrite", (RInt "nbytes", [Pathname "path"; BufferIn "content"; Int64 "offset"], []), 247, [ProtocolLimitWarning],
   [InitScratchFS, Always, TestOutput (
      [["write"; "/pwrite"; "new file contents"];
       ["pwrite"; "/pwrite"; "data"; "4"];
       ["cat"; "/pwrite"]], "new data contents");
    InitScratchFS, Always, TestOutput (
      [["write"; "/pwrite2"; "new file contents"];
       ["pwrite"; "/pwrite2"; "is extended"; "9"];
       ["cat"; "/pwrite2"]], "new file is extended");
    InitScratchFS, Always, TestOutput (
      [["write"; "/pwrite3"; "new file contents"];
       ["pwrite"; "/pwrite3"; ""; "4"];
       ["cat"; "/pwrite3"]], "new file contents")],
   "write to part of a file",
   "\
This command writes to part of a file.  It writes the data
buffer C<content> to the file C<path> starting at offset C<offset>.

This command implements the L<pwrite(2)> system call, and like
that system call it may not write the full data requested.  The
return value is the number of bytes that were actually written
to the file.  This could even be 0, although short writes are
unlikely for regular files in ordinary circumstances.

See also C<guestfs_pread>, C<guestfs_pwrite_device>.");

  ("resize2fs_size", (RErr, [Device "device"; Int64 "size"], []), 248, [],
   [],
   "resize an ext2, ext3 or ext4 filesystem (with size)",
   "\
This command is the same as C<guestfs_resize2fs> except that it
allows you to specify the new size (in bytes) explicitly.");

  ("pvresize_size", (RErr, [Device "device"; Int64 "size"], []), 249, [Optional "lvm2"],
   [],
   "resize an LVM physical volume (with size)",
   "\
This command is the same as C<guestfs_pvresize> except that it
allows you to specify the new size (in bytes) explicitly.");

  ("ntfsresize_size", (RErr, [Device "device"; Int64 "size"], []), 250, [Optional "ntfsprogs"; DeprecatedBy "ntfsresize_opts"],
   [],
   "resize an NTFS filesystem (with size)",
   "\
This command is the same as C<guestfs_ntfsresize> except that it
allows you to specify the new size (in bytes) explicitly.");

  ("available_all_groups", (RStringList "groups", [], []), 251, [],
   [InitNone, Always, TestRun [["available_all_groups"]]],
   "return a list of all optional groups",
   "\
This command returns a list of all optional groups that this
daemon knows about.  Note this returns both supported and unsupported
groups.  To find out which ones the daemon can actually support
you have to call C<guestfs_available> on each member of the
returned list.

See also C<guestfs_available> and L<guestfs(3)/AVAILABILITY>.");

  ("fallocate64", (RErr, [Pathname "path"; Int64 "len"], []), 252, [],
   [InitScratchFS, Always, TestOutputStruct (
      [["fallocate64"; "/fallocate64"; "1000000"];
       ["stat"; "/fallocate64"]], [CompareWithInt ("size", 1_000_000)])],
   "preallocate a file in the guest filesystem",
   "\
This command preallocates a file (containing zero bytes) named
C<path> of size C<len> bytes.  If the file exists already, it
is overwritten.

Note that this call allocates disk blocks for the file.
To create a sparse file use C<guestfs_truncate_size> instead.

The deprecated call C<guestfs_fallocate> does the same,
but owing to an oversight it only allowed 30 bit lengths
to be specified, effectively limiting the maximum size
of files created through that call to 1GB.

Do not confuse this with the guestfish-specific
C<alloc> and C<sparse> commands which create
a file in the host and attach it as a device.");

  ("vfs_label", (RString "label", [Device "device"], []), 253, [],
   [InitBasicFS, Always, TestOutput (
       [["set_e2label"; "/dev/sda1"; "LTEST"];
        ["vfs_label"; "/dev/sda1"]], "LTEST")],
   "get the filesystem label",
   "\
This returns the filesystem label of the filesystem on
C<device>.

If the filesystem is unlabeled, this returns the empty string.

To find a filesystem from the label, use C<guestfs_findfs_label>.");

  ("vfs_uuid", (RString "uuid", [Device "device"], []), 254, [],
   (let uuid = uuidgen () in
    [InitBasicFS, Always, TestOutput (
       [["set_e2uuid"; "/dev/sda1"; uuid];
        ["vfs_uuid"; "/dev/sda1"]], uuid)]),
   "get the filesystem UUID",
   "\
This returns the filesystem UUID of the filesystem on
C<device>.

If the filesystem does not have a UUID, this returns the empty string.

To find a filesystem from the UUID, use C<guestfs_findfs_uuid>.");

  ("lvm_set_filter", (RErr, [DeviceList "devices"], []), 255, [Optional "lvm2"],
   (* Can't be tested with the current framework because
    * the VG is being used by the mounted filesystem, so
    * the vgchange -an command we do first will fail.
    *)
    [],
   "set LVM device filter",
   "\
This sets the LVM device filter so that LVM will only be
able to \"see\" the block devices in the list C<devices>,
and will ignore all other attached block devices.

Where disk image(s) contain duplicate PVs or VGs, this
command is useful to get LVM to ignore the duplicates, otherwise
LVM can get confused.  Note also there are two types
of duplication possible: either cloned PVs/VGs which have
identical UUIDs; or VGs that are not cloned but just happen
to have the same name.  In normal operation you cannot
create this situation, but you can do it outside LVM, eg.
by cloning disk images or by bit twiddling inside the LVM
metadata.

This command also clears the LVM cache and performs a volume
group scan.

You can filter whole block devices or individual partitions.

You cannot use this if any VG is currently in use (eg.
contains a mounted filesystem), even if you are not
filtering out that VG.");

  ("lvm_clear_filter", (RErr, [], []), 256, [],
   [], (* see note on lvm_set_filter *)
   "clear LVM device filter",
   "\
This undoes the effect of C<guestfs_lvm_set_filter>.  LVM
will be able to see every block device.

This command also clears the LVM cache and performs a volume
group scan.");

  ("luks_open", (RErr, [Device "device"; Key "key"; String "mapname"], []), 257, [Optional "luks"],
   [],
   "open a LUKS-encrypted block device",
   "\
This command opens a block device which has been encrypted
according to the Linux Unified Key Setup (LUKS) standard.

C<device> is the encrypted block device or partition.

The caller must supply one of the keys associated with the
LUKS block device, in the C<key> parameter.

This creates a new block device called C</dev/mapper/mapname>.
Reads and writes to this block device are decrypted from and
encrypted to the underlying C<device> respectively.

If this block device contains LVM volume groups, then
calling C<guestfs_vgscan> followed by C<guestfs_vg_activate_all>
will make them visible.

Use C<guestfs_list_dm_devices> to list all device mapper
devices.");

  ("luks_open_ro", (RErr, [Device "device"; Key "key"; String "mapname"], []), 258, [Optional "luks"],
   [],
   "open a LUKS-encrypted block device read-only",
   "\
This is the same as C<guestfs_luks_open> except that a read-only
mapping is created.");

  ("luks_close", (RErr, [Device "device"], []), 259, [Optional "luks"],
   [],
   "close a LUKS device",
   "\
This closes a LUKS device that was created earlier by
C<guestfs_luks_open> or C<guestfs_luks_open_ro>.  The
C<device> parameter must be the name of the LUKS mapping
device (ie. C</dev/mapper/mapname>) and I<not> the name
of the underlying block device.");

  ("luks_format", (RErr, [Device "device"; Key "key"; Int "keyslot"], []), 260, [Optional "luks"],
   [],
   "format a block device as a LUKS encrypted device",
   "\
This command erases existing data on C<device> and formats
the device as a LUKS encrypted device.  C<key> is the
initial key, which is added to key slot C<slot>.  (LUKS
supports 8 key slots, numbered 0-7).");

  ("luks_format_cipher", (RErr, [Device "device"; Key "key"; Int "keyslot"; String "cipher"], []), 261, [Optional "luks"],
   [],
   "format a block device as a LUKS encrypted device",
   "\
This command is the same as C<guestfs_luks_format> but
it also allows you to set the C<cipher> used.");

  ("luks_add_key", (RErr, [Device "device"; Key "key"; Key "newkey"; Int "keyslot"], []), 262, [Optional "luks"],
   [],
   "add a key on a LUKS encrypted device",
   "\
This command adds a new key on LUKS device C<device>.
C<key> is any existing key, and is used to access the device.
C<newkey> is the new key to add.  C<keyslot> is the key slot
that will be replaced.

Note that if C<keyslot> already contains a key, then this
command will fail.  You have to use C<guestfs_luks_kill_slot>
first to remove that key.");

  ("luks_kill_slot", (RErr, [Device "device"; Key "key"; Int "keyslot"], []), 263, [Optional "luks"],
   [],
   "remove a key from a LUKS encrypted device",
   "\
This command deletes the key in key slot C<keyslot> from the
encrypted LUKS device C<device>.  C<key> must be one of the
I<other> keys.");

  ("is_lv", (RBool "lvflag", [Device "device"], []), 264, [Optional "lvm2"],
   [InitBasicFSonLVM, IfAvailable "lvm2", TestOutputTrue (
      [["is_lv"; "/dev/VG/LV"]]);
    InitBasicFSonLVM, IfAvailable "lvm2", TestOutputFalse (
      [["is_lv"; "/dev/sda1"]])],
   "test if device is a logical volume",
   "\
This command tests whether C<device> is a logical volume, and
returns true iff this is the case.");

  ("findfs_uuid", (RString "device", [String "uuid"], []), 265, [],
   [],
   "find a filesystem by UUID",
   "\
This command searches the filesystems and returns the one
which has the given UUID.  An error is returned if no such
filesystem can be found.

To find the UUID of a filesystem, use C<guestfs_vfs_uuid>.");

  ("findfs_label", (RString "device", [String "label"], []), 266, [],
   [],
   "find a filesystem by label",
   "\
This command searches the filesystems and returns the one
which has the given label.  An error is returned if no such
filesystem can be found.

To find the label of a filesystem, use C<guestfs_vfs_label>.");

  ("is_chardev", (RBool "flag", [Pathname "path"], []), 267, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_chardev"; "/directory"]]);
    InitScratchFS, Always, TestOutputTrue (
      [["mknod_c"; "0o777"; "99"; "66"; "/is_chardev"];
       ["is_chardev"; "/is_chardev"]])],
   "test if character device",
   "\
This returns C<true> if and only if there is a character device
with the given C<path> name.

See also C<guestfs_stat>.");

  ("is_blockdev", (RBool "flag", [Pathname "path"], []), 268, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_blockdev"; "/directory"]]);
    InitScratchFS, Always, TestOutputTrue (
      [["mknod_b"; "0o777"; "99"; "66"; "/is_blockdev"];
       ["is_blockdev"; "/is_blockdev"]])],
   "test if block device",
   "\
This returns C<true> if and only if there is a block device
with the given C<path> name.

See also C<guestfs_stat>.");

  ("is_fifo", (RBool "flag", [Pathname "path"], []), 269, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_fifo"; "/directory"]]);
    InitScratchFS, Always, TestOutputTrue (
      [["mkfifo"; "0o777"; "/is_fifo"];
       ["is_fifo"; "/is_fifo"]])],
   "test if FIFO (named pipe)",
   "\
This returns C<true> if and only if there is a FIFO (named pipe)
with the given C<path> name.

See also C<guestfs_stat>.");

  ("is_symlink", (RBool "flag", [Pathname "path"], []), 270, [],
   [InitISOFS, Always, TestOutputFalse (
      [["is_symlink"; "/directory"]]);
    InitISOFS, Always, TestOutputTrue (
      [["is_symlink"; "/abssymlink"]])],
   "test if symbolic link",
   "\
This returns C<true> if and only if there is a symbolic link
with the given C<path> name.

See also C<guestfs_stat>.");

  ("is_socket", (RBool "flag", [Pathname "path"], []), 271, [],
   (* XXX Need a positive test for sockets. *)
   [InitISOFS, Always, TestOutputFalse (
      [["is_socket"; "/directory"]])],
   "test if socket",
   "\
This returns C<true> if and only if there is a Unix domain socket
with the given C<path> name.

See also C<guestfs_stat>.");

  ("part_to_dev", (RString "device", [Device "partition"], []), 272, [],
   [InitPartition, Always, TestOutputDevice (
      [["part_to_dev"; "/dev/sda1"]], "/dev/sda");
    InitEmpty, Always, TestLastFail (
      [["part_to_dev"; "/dev/sda"]])],
   "convert partition name to device name",
   "\
This function takes a partition name (eg. \"/dev/sdb1\") and
removes the partition number, returning the device name
(eg. \"/dev/sdb\").

The named partition must exist, for example as a string returned
from C<guestfs_list_partitions>.

See also C<guestfs_part_to_partnum>.");

  ("upload_offset", (RErr, [FileIn "filename"; Dev_or_Path "remotefilename"; Int64 "offset"], []), 273,
   [Progress; Cancellable],
   (let md5 = Digest.to_hex (Digest.file "COPYING.LIB") in
    [InitScratchFS, Always, TestOutput (
       [["upload_offset"; "../../COPYING.LIB"; "/upload_offset"; "0"];
        ["checksum"; "md5"; "/upload_offset"]], md5)]),
   "upload a file from the local machine with offset",
   "\
Upload local file C<filename> to C<remotefilename> on the
filesystem.

C<remotefilename> is overwritten starting at the byte C<offset>
specified.  The intention is to overwrite parts of existing
files or devices, although if a non-existant file is specified
then it is created with a \"hole\" before C<offset>.  The
size of the data written is implicit in the size of the
source C<filename>.

Note that there is no limit on the amount of data that
can be uploaded with this call, unlike with C<guestfs_pwrite>,
and this call always writes the full amount unless an
error occurs.

See also C<guestfs_upload>, C<guestfs_pwrite>.");

  ("download_offset", (RErr, [Dev_or_Path "remotefilename"; FileOut "filename"; Int64 "offset"; Int64 "size"], []), 274,
   [Progress; Cancellable],
   (let md5 = Digest.to_hex (Digest.file "COPYING.LIB") in
    let offset = string_of_int 100 in
    let size = string_of_int ((Unix.stat "COPYING.LIB").Unix.st_size - 100) in
    [InitScratchFS, Always, TestOutput (
       (* Pick a file from cwd which isn't likely to change. *)
       [["mkdir"; "/download_offset"];
        ["upload"; "../../COPYING.LIB"; "/download_offset/COPYING.LIB"];
        ["download_offset"; "/download_offset/COPYING.LIB"; "testdownload.tmp"; offset; size];
        ["upload_offset"; "testdownload.tmp"; "/download_offset/COPYING.LIB"; offset];
        ["checksum"; "md5"; "/download_offset/COPYING.LIB"]], md5)]),
   "download a file to the local machine with offset and size",
   "\
Download file C<remotefilename> and save it as C<filename>
on the local machine.

C<remotefilename> is read for C<size> bytes starting at C<offset>
(this region must be within the file or device).

Note that there is no limit on the amount of data that
can be downloaded with this call, unlike with C<guestfs_pread>,
and this call always reads the full amount unless an
error occurs.

See also C<guestfs_download>, C<guestfs_pread>.");

  ("pwrite_device", (RInt "nbytes", [Device "device"; BufferIn "content"; Int64 "offset"], []), 275, [ProtocolLimitWarning],
   [InitPartition, Always, TestOutputListOfDevices (
      [["pwrite_device"; "/dev/sda"; "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"; "446"];
       ["blockdev_rereadpt"; "/dev/sda"];
       ["list_partitions"]], ["/dev/sdb1"])],
   "write to part of a device",
   "\
This command writes to part of a device.  It writes the data
buffer C<content> to C<device> starting at offset C<offset>.

This command implements the L<pwrite(2)> system call, and like
that system call it may not write the full data requested
(although short writes to disk devices and partitions are
probably impossible with standard Linux kernels).

See also C<guestfs_pwrite>.");

  ("pread_device", (RBufferOut "content", [Device "device"; Int "count"; Int64 "offset"], []), 276, [ProtocolLimitWarning],
   [InitEmpty, Always, TestOutputBuffer (
      [["pread_device"; "/dev/sdd"; "8"; "32768"]], "\001CD001\001\000")],
   "read part of a device",
   "\
This command lets you read part of a file.  It reads C<count>
bytes of C<device>, starting at C<offset>.

This may read fewer bytes than requested.  For further details
see the L<pread(2)> system call.

See also C<guestfs_pread>.");

  ("lvm_canonical_lv_name", (RString "lv", [Device "lvname"], []), 277, [],
   [InitBasicFSonLVM, IfAvailable "lvm2", TestOutput (
    [["lvm_canonical_lv_name"; "/dev/mapper/VG-LV"]], "/dev/VG/LV");
    InitBasicFSonLVM, IfAvailable "lvm2", TestOutput (
    [["lvm_canonical_lv_name"; "/dev/VG/LV"]], "/dev/VG/LV")],
   "get canonical name of an LV",
   "\
This converts alternative naming schemes for LVs that you
might find to the canonical name.  For example, C</dev/mapper/VG-LV>
is converted to C</dev/VG/LV>.

This command returns an error if the C<lvname> parameter does
not refer to a logical volume.

See also C<guestfs_is_lv>.");

  ("mkfs_opts", (RErr, [String "fstype"; Device "device"], [OInt "blocksize"; OString "features"; OInt "inode"; OInt "sectorsize"]), 278, [],
   [InitEmpty, Always, TestOutput (
      [["part_disk"; "/dev/sda"; "mbr"];
       ["mkfs_opts"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""];
       ["mount_options"; ""; "/dev/sda1"; "/"];
       ["write"; "/new"; "new file contents"];
       ["cat"; "/new"]], "new file contents")],
   "make a filesystem",
   "\
This function creates a filesystem on C<device>.  The filesystem
type is C<fstype>, for example C<ext3>.

The optional arguments are:

=over 4

=item C<blocksize>

The filesystem block size.  Supported block sizes depend on the
filesystem type, but typically they are C<1024>, C<2048> or C<4096>
for Linux ext2/3 filesystems.

For VFAT and NTFS the C<blocksize> parameter is treated as
the requested cluster size.

For UFS block sizes, please see L<mkfs.ufs(8)>.

=item C<features>

This passes the I<-O> parameter to the external mkfs program.

For certain filesystem types, this allows extra filesystem
features to be selected.  See L<mke2fs(8)> and L<mkfs.ufs(8)>
for more details.

You cannot use this optional parameter with the C<gfs> or
C<gfs2> filesystem type.

=item C<inode>

This passes the I<-I> parameter to the external L<mke2fs(8)> program
which sets the inode size (only for ext2/3/4 filesystems at present).

=item C<sectorsize>

This passes the I<-S> parameter to external L<mkfs.ufs(8)> program,
which sets sector size for ufs filesystem.

=back");

  ("getxattr", (RBufferOut "xattr", [Pathname "path"; String "name"], []), 279, [Optional "linuxxattrs"],
   [],
   "get a single extended attribute",
   "\
Get a single extended attribute from file C<path> named C<name>.
This call follows symlinks.  If you want to lookup an extended
attribute for the symlink itself, use C<guestfs_lgetxattr>.

Normally it is better to get all extended attributes from a file
in one go by calling C<guestfs_getxattrs>.  However some Linux
filesystem implementations are buggy and do not provide a way to
list out attributes.  For these filesystems (notably ntfs-3g)
you have to know the names of the extended attributes you want
in advance and call this function.

Extended attribute values are blobs of binary data.  If there
is no extended attribute named C<name>, this returns an error.

See also: C<guestfs_getxattrs>, C<guestfs_lgetxattr>, L<attr(5)>.");

  ("lgetxattr", (RBufferOut "xattr", [Pathname "path"; String "name"], []), 280, [Optional "linuxxattrs"],
   [],
   "get a single extended attribute",
   "\
Get a single extended attribute from file C<path> named C<name>.
If C<path> is a symlink, then this call returns an extended
attribute from the symlink.

Normally it is better to get all extended attributes from a file
in one go by calling C<guestfs_getxattrs>.  However some Linux
filesystem implementations are buggy and do not provide a way to
list out attributes.  For these filesystems (notably ntfs-3g)
you have to know the names of the extended attributes you want
in advance and call this function.

Extended attribute values are blobs of binary data.  If there
is no extended attribute named C<name>, this returns an error.

See also: C<guestfs_lgetxattrs>, C<guestfs_getxattr>, L<attr(5)>.");

  ("resize2fs_M", (RErr, [Device "device"], []), 281, [],
   [],
   "resize an ext2, ext3 or ext4 filesystem to the minimum size",
   "\
This command is the same as C<guestfs_resize2fs>, but the filesystem
is resized to its minimum size.  This works like the I<-M> option
to the C<resize2fs> command.

To get the resulting size of the filesystem you should call
C<guestfs_tune2fs_l> and read the C<Block size> and C<Block count>
values.  These two numbers, multiplied together, give the
resulting size of the minimal filesystem in bytes.");

  ("internal_autosync", (RErr, [], []), 282, [NotInFish; NotInDocs],
   [],
   "internal autosync operation",
   "\
This command performs the autosync operation just before the
handle is closed.  You should not call this command directly.
Instead, use the autosync flag (C<guestfs_set_autosync>) to
control whether or not this operation is performed when the
handle is closed.");

  ("is_zero", (RBool "zeroflag", [Pathname "path"], []), 283, [],
   [InitISOFS, Always, TestOutputTrue (
      [["is_zero"; "/100kallzeroes"]]);
    InitISOFS, Always, TestOutputFalse (
      [["is_zero"; "/100kallspaces"]])],
   "test if a file contains all zero bytes",
   "\
This returns true iff the file exists and the file is empty or
it contains all zero bytes.");

  ("is_zero_device", (RBool "zeroflag", [Device "device"], []), 284, [],
   [InitBasicFS, Always, TestOutputTrue (
      [["umount"; "/dev/sda1"];
       ["zero_device"; "/dev/sda1"];
       ["is_zero_device"; "/dev/sda1"]]);
    InitBasicFS, Always, TestOutputFalse (
      [["is_zero_device"; "/dev/sda1"]])],
   "test if a device contains all zero bytes",
   "\
This returns true iff the device exists and contains all zero bytes.

Note that for large devices this can take a long time to run.");

  ("list_9p", (RStringList "mounttags", [], []), 285, [],
   [],
   "list 9p filesystems",
   "\
List all 9p filesystems attached to the guest.  A list of
mount tags is returned.");

  ("mount_9p", (RErr, [String "mounttag"; String "mountpoint"], [OString "options"]), 286, [CamelName "Mount9P"],
   [],
   "mount 9p filesystem",
   "\
Mount the virtio-9p filesystem with the tag C<mounttag> on the
directory C<mountpoint>.

If required, C<trans=virtio> will be automatically added to the options.
Any other options required can be passed in the optional C<options>
parameter.");

  ("list_dm_devices", (RStringList "devices", [], []), 287, [],
   [],
   "list device mapper devices",
   "\
List all device mapper devices.

The returned list contains C</dev/mapper/*> devices, eg. ones created
by a previous call to C<guestfs_luks_open>.

Device mapper devices which correspond to logical volumes are I<not>
returned in this list.  Call C<guestfs_lvs> if you want to list logical
volumes.");

  ("ntfsresize_opts", (RErr, [Device "device"], [OInt64 "size"; OBool "force"]), 288, [Optional "ntfsprogs"; CamelName "NTFSResizeOpts"],
   [],
   "resize an NTFS filesystem",
   "\
This command resizes an NTFS filesystem, expanding or
shrinking it to the size of the underlying device.

The optional parameters are:

=over 4

=item C<size>

The new size (in bytes) of the filesystem.  If omitted, the filesystem
is resized to fit the container (eg. partition).

=item C<force>

If this option is true, then force the resize of the filesystem
even if the filesystem is marked as requiring a consistency check.

After the resize operation, the filesystem is always marked
as requiring a consistency check (for safety).  You have to boot
into Windows to perform this check and clear this condition.
If you I<don't> set the C<force> option then it is not
possible to call C<guestfs_ntfsresize_opts> multiple times on a
single filesystem without booting into Windows between each resize.

=back

See also L<ntfsresize(8)>.");

  ("btrfs_filesystem_resize", (RErr, [Pathname "mountpoint"], [OInt64 "size"]), 289, [Optional "btrfs"; CamelName "BTRFSFilesystemResize"],
   [],
   "resize a btrfs filesystem",
   "\
This command resizes a btrfs filesystem.

Note that unlike other resize calls, the filesystem has to be
mounted and the parameter is the mountpoint not the device
(this is a requirement of btrfs itself).

The optional parameters are:

=over 4

=item C<size>

The new size (in bytes) of the filesystem.  If omitted, the filesystem
is resized to the maximum size.

=back

See also L<btrfs(8)>.");

  ("write_append", (RErr, [Pathname "path"; BufferIn "content"], []), 290, [ProtocolLimitWarning],
   [InitScratchFS, Always, TestOutput (
      [["write"; "/write_append"; "line1\n"];
       ["write_append"; "/write_append"; "line2\n"];
       ["write_append"; "/write_append"; "line3a"];
       ["write_append"; "/write_append"; "line3b\n"];
       ["cat"; "/write_append"]], "line1\nline2\nline3aline3b\n")],
   "append content to end of file",
   "\
This call appends C<content> to the end of file C<path>.  If
C<path> does not exist, then a new file is created.

See also C<guestfs_write>.");

  ("compress_out", (RErr, [String "ctype"; Pathname "file"; FileOut "zfile"], [OInt "level"]), 291,
   [Cancellable],
   [],
   "output compressed file",
   "\
This command compresses C<file> and writes it out to the local
file C<zfile>.

The compression program used is controlled by the C<ctype> parameter.
Currently this includes: C<compress>, C<gzip>, C<bzip2>, C<xz> or C<lzop>.
Some compression types may not be supported by particular builds of
libguestfs, in which case you will get an error containing the
substring \"not supported\".

The optional C<level> parameter controls compression level.  The
meaning and default for this parameter depends on the compression
program being used.");

  ("compress_device_out", (RErr, [String "ctype"; Device "device"; FileOut "zdevice"], [OInt "level"]), 292,
   [Cancellable],
   [],
   "output compressed device",
   "\
This command compresses C<device> and writes it out to the local
file C<zdevice>.

The C<ctype> and optional C<level> parameters have the same meaning
as in C<guestfs_compress_out>.");

  ("part_to_partnum", (RInt "partnum", [Device "partition"], []), 293, [],
   [InitPartition, Always, TestOutputInt (
      [["part_to_partnum"; "/dev/sda1"]], 1);
    InitEmpty, Always, TestLastFail (
      [["part_to_partnum"; "/dev/sda"]])],
   "convert partition name to partition number",
   "\
This function takes a partition name (eg. \"/dev/sdb1\") and
returns the partition number (eg. C<1>).

The named partition must exist, for example as a string returned
from C<guestfs_list_partitions>.

See also C<guestfs_part_to_dev>.");

  ("copy_device_to_device", (RErr, [Device "src"; Device "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"]), 294, [Progress],
   [],
   "copy from source device to destination device",
   "\
The four calls C<guestfs_copy_device_to_device>,
C<guestfs_copy_device_to_file>,
C<guestfs_copy_file_to_device>, and
C<guestfs_copy_file_to_file>
let you copy from a source (device|file) to a destination
(device|file).

Partial copies can be made since you can specify optionally
the source offset, destination offset and size to copy.  These
values are all specified in bytes.  If not given, the offsets
both default to zero, and the size defaults to copying as much
as possible until we hit the end of the source.

The source and destination may be the same object.  However
overlapping regions may not be copied correctly.

If the destination is a file, it is created if required.  If
the destination file is not large enough, it is extended.");

  ("copy_device_to_file", (RErr, [Device "src"; Pathname "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"]), 295, [Progress],
   [],
   "copy from source device to destination file",
   "\
See C<guestfs_copy_device_to_device> for a general overview
of this call.");

  ("copy_file_to_device", (RErr, [Pathname "src"; Device "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"]), 296, [Progress],
   [],
   "copy from source file to destination device",
   "\
See C<guestfs_copy_device_to_device> for a general overview
of this call.");

  ("copy_file_to_file", (RErr, [Pathname "src"; Pathname "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"]), 297, [Progress],
   [InitScratchFS, Always, TestOutputBuffer (
      [["mkdir"; "/copyff"];
       ["write"; "/copyff/src"; "hello, world"];
       ["copy_file_to_file"; "/copyff/src"; "/copyff/dest"; ""; ""; ""];
       ["read_file"; "/copyff/dest"]], "hello, world")],
   "copy from source file to destination file",
   "\
See C<guestfs_copy_device_to_device> for a general overview
of this call.

This is B<not> the function you want for copying files.  This
is for copying blocks within existing files.  See C<guestfs_cp>,
C<guestfs_cp_a> and C<guestfs_mv> for general file copying and
moving functions.");

  ("tune2fs", (RErr, [Device "device"], [OBool "force"; OInt "maxmountcount"; OInt "mountcount"; OString "errorbehavior"; OInt64 "group"; OInt "intervalbetweenchecks"; OInt "reservedblockspercentage"; OString "lastmounteddirectory"; OInt64 "reservedblockscount"; OInt64 "user"]), 298, [CamelName "Tune2FS"],
   [InitScratchFS, Always, TestOutputHashtable (
     [["tune2fs"; "/dev/sdb1"; "false"; "0"; ""; "NOARG"; ""; "0"; ""; "NOARG"; ""; ""];
      ["tune2fs_l"; "/dev/sdb1"]],
     ["Check interval", "0 (<none>)";
      "Maximum mount count", "-1"]);
    InitScratchFS, Always, TestOutputHashtable (
      [["tune2fs"; "/dev/sdb1"; "false"; "0"; ""; "NOARG"; ""; "86400"; ""; "NOARG"; ""; ""];
       ["tune2fs_l"; "/dev/sdb1"]],
      ["Check interval", "86400 (1 day)";
       "Maximum mount count", "-1"]);
    InitScratchFS, Always, TestOutputHashtable (
      [["tune2fs"; "/dev/sdb1"; "false"; ""; ""; "NOARG"; "1"; ""; ""; "NOARG"; ""; "1"];
       ["tune2fs_l"; "/dev/sdb1"]],
      ["Reserved blocks uid", "1 (user bin)";
       "Reserved blocks gid", "1 (group bin)"]);
    InitScratchFS, Always, TestOutputHashtable (
      [["tune2fs"; "/dev/sdb1"; "false"; ""; ""; "NOARG"; "0"; ""; ""; "NOARG"; ""; "0"];
       ["tune2fs_l"; "/dev/sdb1"]],
      ["Reserved blocks uid", "0 (user root)";
       "Reserved blocks gid", "0 (group root)"])
   ],
   "adjust ext2/ext3/ext4 filesystem parameters",
   "\
This call allows you to adjust various filesystem parameters of
an ext2/ext3/ext4 filesystem called C<device>.

The optional parameters are:

=over 4

=item C<force>

Force tune2fs to complete the operation even in the face of errors.
This is the same as the tune2fs C<-f> option.

=item C<maxmountcount>

Set the number of mounts after which the filesystem is checked
by L<e2fsck(8)>.  If this is C<0> then the number of mounts is
disregarded.  This is the same as the tune2fs C<-c> option.

=item C<mountcount>

Set the number of times the filesystem has been mounted.
This is the same as the tune2fs C<-C> option.

=item C<errorbehavior>

Change the behavior of the kernel code when errors are detected.
Possible values currently are: C<continue>, C<remount-ro>, C<panic>.
In practice these options don't really make any difference,
particularly for write errors.

This is the same as the tune2fs C<-e> option.

=item C<group>

Set the group which can use reserved filesystem blocks.
This is the same as the tune2fs C<-g> option except that it
can only be specified as a number.

=item C<intervalbetweenchecks>

Adjust the maximal time between two filesystem checks
(in seconds).  If the option is passed as C<0> then
time-dependent checking is disabled.

This is the same as the tune2fs C<-i> option.

=item C<reservedblockspercentage>

Set the percentage of the filesystem which may only be allocated
by privileged processes.
This is the same as the tune2fs C<-m> option.

=item C<lastmounteddirectory>

Set the last mounted directory.
This is the same as the tune2fs C<-M> option.

=item C<reservedblockscount>
Set the number of reserved filesystem blocks.
This is the same as the tune2fs C<-r> option.

=item C<user>

Set the user who can use the reserved filesystem blocks.
This is the same as the tune2fs C<-u> option except that it
can only be specified as a number.

=back

To get the current values of filesystem parameters, see
C<guestfs_tune2fs_l>.  For precise details of how tune2fs
works, see the L<tune2fs(8)> man page.");

  ("md_create", (RErr, [String "name"; DeviceList "devices"], [OInt64 "missingbitmap"; OInt "nrdevices"; OInt "spare"; OInt64 "chunk"; OString "level"]), 299, [Optional "mdadm"; CamelName "MDCreate"],
   [],
   "create a Linux md (RAID) device",
   "\
Create a Linux md (RAID) device named C<name> on the devices
in the list C<devices>.

The optional parameters are:

=over 4

=item C<missingbitmap>

A bitmap of missing devices.  If a bit is set it means that a
missing device is added to the array.  The least significant bit
corresponds to the first device in the array.

As examples:

If C<devices = [\"/dev/sda\"]> and C<missingbitmap = 0x1> then
the resulting array would be C<[E<lt>missingE<gt>, \"/dev/sda\"]>.

If C<devices = [\"/dev/sda\"]> and C<missingbitmap = 0x2> then
the resulting array would be C<[\"/dev/sda\", E<lt>missingE<gt>]>.

This defaults to C<0> (no missing devices).

The length of C<devices> + the number of bits set in
C<missingbitmap> must equal C<nrdevices> + C<spare>.

=item C<nrdevices>

The number of active RAID devices.

If not set, this defaults to the length of C<devices> plus
the number of bits set in C<missingbitmap>.

=item C<spare>

The number of spare devices.

If not set, this defaults to C<0>.

=item C<chunk>

The chunk size in bytes.

=item C<level>

The RAID level, which can be one of:
I<linear>, I<raid0>, I<0>, I<stripe>, I<raid1>, I<1>, I<mirror>,
I<raid4>, I<4>, I<raid5>, I<5>, I<raid6>, I<6>, I<raid10>, I<10>.
Some of these are synonymous, and more levels may be added in future.

If not set, this defaults to C<raid1>.

=back");

  ("list_md_devices", (RStringList "devices", [], []), 300, [],
   [],
   "list Linux md (RAID) devices",
   "\
List all Linux md devices.");

  ("md_detail", (RHashtable "info", [Device "md"], []), 301,  [Optional "mdadm"],
   [],
   "obtain metadata for an MD device",
   "\
This command exposes the output of 'mdadm -DY <md>'. The following fields are
usually present in the returned hash. Other fields may also be present.

=over

=item C<level>

The raid level of the MD device.

=item C<devices>

The number of underlying devices in the MD device.

=item C<metadata>

The metadata version used.

=item C<uuid>

The UUID of the MD device.

=item C<name>

The name of the MD device.

=back");

  ("md_stop", (RErr, [Device "md"], []), 302, [Optional "mdadm"],
   [],
   "stop a Linux md (RAID) device",
   "\
This command deactivates the MD array named C<md>.  The
device is stopped, but it is not destroyed or zeroed.");

  ("blkid", (RHashtable "info", [Device "device"], []), 303, [],
   [InitScratchFS, Always, TestOutputHashtable (
      [["blkid"; "/dev/sdb1"]],
      ["TYPE", "ext2";
       "USAGE", "filesystem";
       "PART_ENTRY_NUMBER", "1";
       "PART_ENTRY_TYPE", "0x83";
       "PART_ENTRY_OFFSET", "128";
       "PART_ENTRY_SIZE", "102145"])],
   "print block device attributes",
   "\
This command returns block device attributes for C<device>. The following fields are
usually present in the returned hash. Other fields may also be present.

=over

=item C<UUID>

The uuid of this device.

=item C<LABEL>

The label of this device.

=item C<VERSION>

The version of blkid command.

=item C<TYPE>

The filesystem type or RAID of this device.

=item C<USAGE>

The usage of this device, for example C<filesystem> or C<raid>.

=back");

  ("e2fsck", (RErr, [Device "device"], [OBool "correct"; OBool "forceall"]), 304, [],
   [], (* lvresize tests this *)
   "check an ext2/ext3 filesystem",
   "\
This runs the ext2/ext3 filesystem checker on C<device>.
It can take the following optional arguments:

=over 4

=item C<correct>

Automatically repair the file system. This option will cause e2fsck
to automatically fix any filesystem problems that can be safely
fixed without human intervention.

This option may not be specified at the same time as the C<forceall> option.

=item C<forceall>

Assume an answer of 'yes' to all questions; allows e2fsck to be used
non-interactively.

This option may not be specified at the same time as the C<correct> option.

=back");

]

let all_functions = non_daemon_functions @ daemon_functions

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let all_functions_sorted = List.sort action_compare all_functions

(* This is used to generate the src/MAX_PROC_NR file which
 * contains the maximum procedure number, a surrogate for the
 * ABI version number.  See src/Makefile.am for the details.
 *)
let max_proc_nr =
  let proc_nrs = List.map (
    fun (_, _, proc_nr, _, _, _, _) -> proc_nr
  ) daemon_functions in
  List.fold_left max 0 proc_nrs

(* Non-API meta-commands available only in guestfish.
 *
 * Note (1): style, proc_nr and tests fields are all meaningless.
 * The only fields which are actually used are the shortname,
 * FishAlias flags, shortdesc and longdesc.
 *
 * Note (2): to refer to other commands, use L</shortname>.
 *
 * Note (3): keep this list sorted by shortname.
 *)
let fish_commands = [
  ("alloc", (RErr,[], []), -1, [FishAlias "allocate"], [],
   "allocate and add a disk file",
   " alloc filename size

This creates an empty (zeroed) file of the given size, and then adds
so it can be further examined.

For more advanced image creation, see L<qemu-img(1)> utility.

Size can be specified using standard suffixes, eg. C<1M>.

To create a sparse file, use L</sparse> instead.  To create a
prepared disk image, see L</PREPARED DISK IMAGES>.");

  ("copy_in", (RErr,[], []), -1, [], [],
   "copy local files or directories into an image",
   " copy-in local [local ...] /remotedir

C<copy-in> copies local files or directories recursively into the disk
image, placing them in the directory called C</remotedir> (which must
exist).  This guestfish meta-command turns into a sequence of
L</tar-in> and other commands as necessary.

Multiple local files and directories can be specified, but the last
parameter must always be a remote directory.  Wildcards cannot be
used.");

  ("copy_out", (RErr,[], []), -1, [], [],
   "copy remote files or directories out of an image",
   " copy-out remote [remote ...] localdir

C<copy-out> copies remote files or directories recursively out of the
disk image, placing them on the host disk in a local directory called
C<localdir> (which must exist).  This guestfish meta-command turns
into a sequence of L</download>, L</tar-out> and other commands as
necessary.

Multiple remote files and directories can be specified, but the last
parameter must always be a local directory.  To download to the
current directory, use C<.> as in:

 copy-out /home .

Wildcards cannot be used in the ordinary command, but you can use
them with the help of L</glob> like this:

 glob copy-out /home/* .");

  ("delete_event", (RErr,[], []), -1, [], [],
   "delete a previously registered event handler",
   " delete-event name

Delete the event handler which was previously registered as C<name>.
If multiple event handlers were registered with the same name, they
are all deleted.

See also the guestfish commands C<event> and C<list-events>.");

  ("display", (RErr,[], []), -1, [], [],
   "display an image",
   " display filename

Use C<display> (a graphical display program) to display an image
file.  It downloads the file, and runs C<display> on it.

To use an alternative program, set the C<GUESTFISH_DISPLAY_IMAGE>
environment variable.  For example to use the GNOME display program:

 export GUESTFISH_DISPLAY_IMAGE=eog

See also L<display(1)>.");

  ("echo", (RErr,[], []), -1, [], [],
   "display a line of text",
   " echo [params ...]

This echos the parameters to the terminal.");

  ("edit", (RErr,[], []), -1, [FishAlias "vi"; FishAlias "emacs"], [],
   "edit a file",
   " edit filename

This is used to edit a file.  It downloads the file, edits it
locally using your editor, then uploads the result.

The editor is C<$EDITOR>.  However if you use the alternate
commands C<vi> or C<emacs> you will get those corresponding
editors.");

  ("event", (RErr,[], []), -1, [], [],
   "register a handler for an event or events",
   " event name eventset \"shell script ...\"

Register a shell script fragment which is executed when an
event is raised.  See L<guestfs(3)/guestfs_set_event_callback>
for a discussion of the event API in libguestfs.

The C<name> parameter is a name that you give to this event
handler.  It can be any string (even the empty string) and is
simply there so you can delete the handler using the guestfish
C<delete-event> command.

The C<eventset> parameter is a comma-separated list of one
or more events, for example C<close> or C<close,trace>.  The
special value C<*> means all events.

The third and final parameter is the shell script fragment
(or any external command) that is executed when any of the
events in the eventset occurs.  It is executed using
C<$SHELL -c>, or if C<$SHELL> is not set then C</bin/sh -c>.

The shell script fragment receives callback parameters as
arguments C<$1>, C<$2> etc.  The actual event that was
called is available in the environment variable C<$EVENT>.

 event \"\" close \"echo closed\"
 event messages appliance,library,trace \"echo $@\"
 event \"\" progress \"echo progress: $3/$4\"
 event \"\" * \"echo $EVENT $@\"

See also the guestfish commands C<delete-event> and C<list-events>.");

  ("glob", (RErr,[], []), -1, [], [],
   "expand wildcards in command",
   " glob command args...

Expand wildcards in any paths in the args list, and run C<command>
repeatedly on each matching path.

See L</WILDCARDS AND GLOBBING>.");

  ("hexedit", (RErr,[], []), -1, [], [],
   "edit with a hex editor",
   " hexedit <filename|device>
 hexedit <filename|device> <max>
 hexedit <filename|device> <start> <max>

Use hexedit (a hex editor) to edit all or part of a binary file
or block device.

This command works by downloading potentially the whole file or
device, editing it locally, then uploading it.  If the file or
device is large, you have to specify which part you wish to edit
by using C<max> and/or C<start> C<max> parameters.
C<start> and C<max> are specified in bytes, with the usual
modifiers allowed such as C<1M> (1 megabyte).

For example to edit the first few sectors of a disk you
might do:

 hexedit /dev/sda 1M

which would allow you to edit anywhere within the first megabyte
of the disk.

To edit the superblock of an ext2 filesystem on C</dev/sda1>, do:

 hexedit /dev/sda1 0x400 0x400

(assuming the superblock is in the standard location).

This command requires the external L<hexedit(1)> program.  You
can specify another program to use by setting the C<HEXEDITOR>
environment variable.

See also L</hexdump>.");

  ("lcd", (RErr,[], []), -1, [], [],
   "change working directory",
   " lcd directory

Change the local directory, ie. the current directory of guestfish
itself.

Note that C<!cd> won't do what you might expect.");

  ("list_events", (RErr,[], []), -1, [], [],
   "list event handlers",
   " list-events

List the event handlers registered using the guestfish
C<event> command.");

  ("man", (RErr,[], []), -1, [FishAlias "manual"], [],
   "open the manual",
   "  man

Opens the manual page for guestfish.");

  ("more", (RErr,[], []), -1, [FishAlias "less"], [],
   "view a file",
   " more filename

 less filename

This is used to view a file.

The default viewer is C<$PAGER>.  However if you use the alternate
command C<less> you will get the C<less> command specifically.");

  ("reopen", (RErr,[], []), -1, [], [],
   "close and reopen libguestfs handle",
   "  reopen

Close and reopen the libguestfs handle.  It is not necessary to use
this normally, because the handle is closed properly when guestfish
exits.  However this is occasionally useful for testing.");

  ("setenv", (RErr,[], []), -1, [], [],
   "set an environment variable",
   "  setenv VAR value

Set the environment variable C<VAR> to the string C<value>.

To print the value of an environment variable use a shell command
such as:

 !echo $VAR");

  ("sparse", (RErr,[], []), -1, [], [],
   "create a sparse disk image and add",
   " sparse filename size

This creates an empty sparse file of the given size, and then adds
so it can be further examined.

In all respects it works the same as the L</alloc> command, except that
the image file is allocated sparsely, which means that disk blocks are
not assigned to the file until they are needed.  Sparse disk files
only use space when written to, but they are slower and there is a
danger you could run out of real disk space during a write operation.

For more advanced image creation, see L<qemu-img(1)> utility.

Size can be specified using standard suffixes, eg. C<1M>.");

  ("supported", (RErr,[], []), -1, [], [],
   "list supported groups of commands",
   " supported

This command returns a list of the optional groups
known to the daemon, and indicates which ones are
supported by this build of the libguestfs appliance.

See also L<guestfs(3)/AVAILABILITY>.");

  ("time", (RErr,[], []), -1, [], [],
   "print elapsed time taken to run a command",
   " time command args...

Run the command as usual, but print the elapsed time afterwards.  This
can be useful for benchmarking operations.");

  ("unsetenv", (RErr,[], []), -1, [], [],
   "unset an environment variable",
   "  unsetenv VAR

Remove C<VAR> from the environment.");

]
