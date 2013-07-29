(* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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

open Types
open Utils

(* Default settings for all action fields.  So we copy and override
 * this struct by writing '{ defaults with name = &c }'
 *)
let defaults = { name = "";
                 added = (-1,-1,-1);
                 style = RErr, [], []; proc_nr = None;
                 tests = []; test_excuse = "";
                 shortdesc = ""; longdesc = "";
                 protocol_limit_warning = false; fish_alias = [];
                 fish_output = None; visibility = VPublic;
                 deprecated_by = None; optional = None;
                 progress = false; camel_name = "";
                 cancellable = false; config_only = false;
                 once_had_no_optargs = false; blocking = true; wrapper = true;
                 c_name = ""; c_function = ""; c_optarg_prefix = "";
                 non_c_aliases = [] }

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
  OBool "obool";
  OInt "oint";
  OInt64 "oint64";
  OString "ostring";
  OStringList "ostringlist";
]

let test_all_rets = [
  (* except for RErr, which is tested thoroughly elsewhere *)
  "internal_test_rint",         RInt "valout";
  "internal_test_rint64",       RInt64 "valout";
  "internal_test_rbool",        RBool "valout";
  "internal_test_rconststring", RConstString "valout";
  "internal_test_rconstoptstring", RConstOptString "valout";
  "internal_test_rstring",      RString "valout";
  "internal_test_rstringlist",  RStringList "valout";
  "internal_test_rstruct",      RStruct ("valout", "lvm_pv");
  "internal_test_rstructlist",  RStructList ("valout", "lvm_pv");
  "internal_test_rhashtable",   RHashtable "valout";
  "internal_test_rbufferout",   RBufferOut "valout";
]

let test_functions = [
  { defaults with
    name = "internal_test";
    style = RErr, test_all_args, test_all_optargs;
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_only_optargs";
    style = RErr, [], [OInt "test"];
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle no args, some
optargs correctly.

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_63_optargs";
    style = RErr, [], [OInt "opt1"; OInt "opt2"; OInt "opt3"; OInt "opt4"; OInt "opt5"; OInt "opt6"; OInt "opt7"; OInt "opt8"; OInt "opt9"; OInt "opt10"; OInt "opt11"; OInt "opt12"; OInt "opt13"; OInt "opt14"; OInt "opt15"; OInt "opt16"; OInt "opt17"; OInt "opt18"; OInt "opt19"; OInt "opt20"; OInt "opt21"; OInt "opt22"; OInt "opt23"; OInt "opt24"; OInt "opt25"; OInt "opt26"; OInt "opt27"; OInt "opt28"; OInt "opt29"; OInt "opt30"; OInt "opt31"; OInt "opt32"; OInt "opt33"; OInt "opt34"; OInt "opt35"; OInt "opt36"; OInt "opt37"; OInt "opt38"; OInt "opt39"; OInt "opt40"; OInt "opt41"; OInt "opt42"; OInt "opt43"; OInt "opt44"; OInt "opt45"; OInt "opt46"; OInt "opt47"; OInt "opt48"; OInt "opt49"; OInt "opt50"; OInt "opt51"; OInt "opt52"; OInt "opt53"; OInt "opt54"; OInt "opt55"; OInt "opt56"; OInt "opt57"; OInt "opt58"; OInt "opt59"; OInt "opt60"; OInt "opt61"; OInt "opt62"; OInt "opt63"];
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle the full range
of 63 optargs correctly.  (Note that 63 is not an absolute limit
and it could be raised by changing the XDR protocol).

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." }

] @ List.flatten (
  List.map (
    fun (name, ret) -> [
      { defaults with
        name = name;
        style = ret, [String "val"], [];
        visibility = VBindTest;
        blocking = false;
        shortdesc = "internal test function - do not use";
        longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

It converts string C<val> to the return type.

You probably don't want to call this function." };
      { defaults with
        name = name ^ "err";
        style = ret, [], [];
        visibility = VBindTest;
        blocking = false;
        shortdesc = "internal test function - do not use";
        longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

This function always returns an error.

You probably don't want to call this function." }
    ]
  ) test_all_rets
)

(* non_daemon_functions are any functions which don't get processed
 * in the daemon, eg. functions for setting and getting local
 * configuration values.
 *)

let non_daemon_functions = test_functions @ [
  { defaults with
    name = "internal_test_set_output";
    style = RErr, [String "filename"], [];
    visibility = VBindTest;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It sets the output file used by C<guestfs_internal_test>.

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_close_output";
    style = RErr, [], [];
    visibility = VBindTest;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It closes the output file previously opened by
C<guestfs_internal_test_set_output>.

You probably don't want to call this function." };

  { defaults with
    name = "launch"; added = (0, 0, 3);
    style = RErr, [], [];
    fish_alias = ["run"]; progress = true; config_only = true;
    shortdesc = "launch the backend";
    longdesc = "\
You should call this after configuring the handle
(eg. adding drives) but before performing any actions.

Do not call C<guestfs_launch> twice on the same handle.  Although
it will not give an error (for historical reasons), the precise
behaviour when you do this is not well defined.  Handles are
very cheap to create, so create a new one for each launch." };

  { defaults with
    name = "wait_ready"; added = (0, 0, 3);
    style = RErr, [], [];
    visibility = VStateTest;
    deprecated_by = Some "launch";
    blocking = false;
    shortdesc = "wait until the hypervisor launches (no op)";
    longdesc = "\
This function is a no op.

In versions of the API E<lt> 1.0.71 you had to call this function
just after calling C<guestfs_launch> to wait for the launch
to complete.  However this is no longer necessary because
C<guestfs_launch> now does the waiting.

If you see any calls to this function in code then you can just
remove them, unless you want to retain compatibility with older
versions of the API." };

  { defaults with
    name = "kill_subprocess"; added = (0, 0, 3);
    style = RErr, [], [];
    deprecated_by = Some "shutdown";
    shortdesc = "kill the hypervisor";
    longdesc = "\
This kills the hypervisor.

Do not call this.  See: C<guestfs_shutdown> instead." };

  { defaults with
    name = "add_cdrom"; added = (0, 0, 3);
    style = RErr, [String "filename"], [];
    deprecated_by = Some "add_drive_ro"; config_only = true;
    blocking = false;
    shortdesc = "add a CD-ROM disk image to examine";
    longdesc = "\
This function adds a virtual CD-ROM disk image to the guest.

The image is added as read-only drive, so this function is equivalent
of C<guestfs_add_drive_ro>." };

  { defaults with
    name = "add_drive_ro"; added = (1, 0, 38);
    style = RErr, [String "filename"], [];
    fish_alias = ["add-ro"]; config_only = true;
    blocking = false;
    shortdesc = "add a drive in snapshot mode (read-only)";
    longdesc = "\
This function is the equivalent of calling C<guestfs_add_drive_opts>
with the optional parameter C<GUESTFS_ADD_DRIVE_OPTS_READONLY> set to 1,
so the disk is added read-only, with the format being detected
automatically." };

  { defaults with
    name = "config"; added = (0, 0, 3);
    style = RErr, [String "hvparam"; OptString "hvvalue"], [];
    config_only = true;
    blocking = false;
    shortdesc = "add hypervisor parameters";
    longdesc = "\
This can be used to add arbitrary hypervisor parameters of the
form I<-param value>.  Actually it's not quite arbitrary - we
prevent you from setting some parameters which would interfere with
parameters that we use.

The first character of C<hvparam> string must be a C<-> (dash).

C<hvvalue> can be NULL." };

  { defaults with
    name = "set_qemu"; added = (1, 0, 6);
    style = RErr, [OptString "hv"], [];
    fish_alias = ["qemu"]; config_only = true;
    blocking = false;
    deprecated_by = Some "set_hv";
    shortdesc = "set the hypervisor binary (usually qemu)";
    longdesc = "\
Set the hypervisor binary (usually qemu) that we will use.

The default is chosen when the library was compiled by the
configure script.

You can also override this by setting the C<LIBGUESTFS_HV>
environment variable.

Setting C<hv> to C<NULL> restores the default qemu binary.

Note that you should call this function as early as possible
after creating the handle.  This is because some pre-launch
operations depend on testing qemu features (by running C<qemu -help>).
If the qemu binary changes, we don't retest features, and
so you might see inconsistent results.  Using the environment
variable C<LIBGUESTFS_HV> is safest of all since that picks
the qemu binary at the same time as the handle is created." };

  { defaults with
    name = "get_qemu"; added = (1, 0, 6);
    style = RConstString "hv", [], [];
    blocking = false;
    deprecated_by = Some "get_hv";
    tests = [
      InitNone, Always, TestRun (
        [["get_qemu"]]), []
    ];
    shortdesc = "get the hypervisor binary (usually qemu)";
    longdesc = "\
Return the current hypervisor binary (usually qemu).

This is always non-NULL.  If it wasn't set already, then this will
return the default qemu binary name." };

  { defaults with
    name = "set_hv"; added = (1, 23, 17);
    style = RErr, [String "hv"], [];
    fish_alias = ["hv"]; config_only = true;
    blocking = false;
    shortdesc = "set the hypervisor binary";
    longdesc = "\
Set the hypervisor binary that we will use.  The hypervisor
depends on the backend, but is usually the location of the
qemu/KVM hypervisor.  For the uml backend, it is the location
of the C<linux> or C<vmlinux> binary.

The default is chosen when the library was compiled by the
configure script.

You can also override this by setting the C<LIBGUESTFS_HV>
environment variable.

Note that you should call this function as early as possible
after creating the handle.  This is because some pre-launch
operations depend on testing qemu features (by running C<qemu -help>).
If the qemu binary changes, we don't retest features, and
so you might see inconsistent results.  Using the environment
variable C<LIBGUESTFS_HV> is safest of all since that picks
the qemu binary at the same time as the handle is created." };

  { defaults with
    name = "get_hv"; added = (1, 23, 17);
    style = RString "hv", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
        [["get_hv"]]), []
    ];
    shortdesc = "get the hypervisor binary";
    longdesc = "\
Return the current hypervisor binary.

This is always non-NULL.  If it wasn't set already, then this will
return the default qemu binary name." };

  { defaults with
    name = "set_path"; added = (0, 0, 3);
    style = RErr, [OptString "searchpath"], [];
    fish_alias = ["path"]; config_only = true;
    blocking = false;
    shortdesc = "set the search path";
    longdesc = "\
Set the path that libguestfs searches for kernel and initrd.img.

The default is C<$libdir/guestfs> unless overridden by setting
C<LIBGUESTFS_PATH> environment variable.

Setting C<path> to C<NULL> restores the default path." };

  { defaults with
    name = "get_path"; added = (0, 0, 3);
    style = RConstString "path", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
      [["get_path"]]), []
    ];
    shortdesc = "get the search path";
    longdesc = "\
Return the current search path.

This is always non-NULL.  If it wasn't set already, then this will
return the default path." };

  { defaults with
    name = "set_append"; added = (1, 0, 26);
    style = RErr, [OptString "append"], [];
    fish_alias = ["append"]; config_only = true;
    blocking = false;
    shortdesc = "add options to kernel command line";
    longdesc = "\
This function is used to add additional options to the
libguestfs appliance kernel command line.

The default is C<NULL> unless overridden by setting
C<LIBGUESTFS_APPEND> environment variable.

Setting C<append> to C<NULL> means I<no> additional options
are passed (libguestfs always adds a few of its own)." };

  { defaults with
    name = "get_append"; added = (1, 0, 26);
    style = RConstOptString "append", [], [];
    blocking = false;
    (* This cannot be tested with the current framework.  The
     * function can return NULL in normal operations, which the
     * test framework interprets as an error.
     *)
    shortdesc = "get the additional kernel options";
    longdesc = "\
Return the additional kernel options which are added to the
libguestfs appliance kernel command line.

If C<NULL> then no options are added." };

  { defaults with
    name = "set_autosync"; added = (0, 0, 3);
    style = RErr, [Bool "autosync"], [];
    fish_alias = ["autosync"];
    blocking = false;
    shortdesc = "set autosync mode";
    longdesc = "\
If C<autosync> is true, this enables autosync.  Libguestfs will make a
best effort attempt to make filesystems consistent and synchronized
when the handle is closed
(also if the program exits without closing handles).

This is enabled by default (since libguestfs 1.5.24, previously it was
disabled by default)." };

  { defaults with
    name = "get_autosync"; added = (0, 0, 3);
    style = RBool "autosync", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestResultTrue (
        [["get_autosync"]]), []
    ];
    shortdesc = "get autosync mode";
    longdesc = "\
Get the autosync flag." };

  { defaults with
    name = "set_verbose"; added = (0, 0, 3);
    style = RErr, [Bool "verbose"], [];
    fish_alias = ["verbose"];
    blocking = false;
    shortdesc = "set verbose mode";
    longdesc = "\
If C<verbose> is true, this turns on verbose messages.

Verbose messages are disabled unless the environment variable
C<LIBGUESTFS_DEBUG> is defined and set to C<1>.

Verbose messages are normally sent to C<stderr>, unless you
register a callback to send them somewhere else (see
C<guestfs_set_event_callback>)." };

  { defaults with
    name = "get_verbose"; added = (0, 0, 3);
    style = RBool "verbose", [], [];
    blocking = false;
    shortdesc = "get verbose mode";
    longdesc = "\
This returns the verbose messages flag." };

  { defaults with
    name = "is_ready"; added = (1, 0, 2);
    style = RBool "ready", [], [];
    visibility = VStateTest;
    blocking = false;
    tests = [
      InitNone, Always, TestResultTrue (
      [["is_ready"]]), []
    ];
    shortdesc = "is ready to accept commands";
    longdesc = "\
This returns true iff this handle is ready to accept commands
(in the C<READY> state).

For more information on states, see L<guestfs(3)>." };

  { defaults with
    name = "is_config"; added = (1, 0, 2);
    style = RBool "config", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestResultFalse (
      [["is_config"]]), []
    ];
    shortdesc = "is in configuration state";
    longdesc = "\
This returns true iff this handle is being configured
(in the C<CONFIG> state).

For more information on states, see L<guestfs(3)>." };

  { defaults with
    name = "is_launching"; added = (1, 0, 2);
    style = RBool "launching", [], [];
    visibility = VStateTest;
    blocking = false;
    tests = [
      InitNone, Always, TestResultFalse (
        [["is_launching"]]), []
    ];
    shortdesc = "is launching subprocess";
    longdesc = "\
This returns true iff this handle is launching the subprocess
(in the C<LAUNCHING> state).

For more information on states, see L<guestfs(3)>." };

  { defaults with
    name = "is_busy"; added = (1, 0, 2);
    style = RBool "busy", [], [];
    visibility = VStateTest;
    blocking = false;
    tests = [
      InitNone, Always, TestResultFalse (
        [["is_busy"]]), []
    ];
    shortdesc = "is busy processing a command";
    longdesc = "\
This always returns false.  This function is deprecated with no
replacement.  Do not use this function.

For more information on states, see L<guestfs(3)>." };

  { defaults with
    name = "get_state"; added = (1, 0, 2);
    style = RInt "state", [], [];
    visibility = VStateTest;
    blocking = false;
    shortdesc = "get the current state";
    longdesc = "\
This returns the current state as an opaque integer.  This is
only useful for printing debug and internal error messages.

For more information on states, see L<guestfs(3)>." };

  { defaults with
    name = "set_memsize"; added = (1, 0, 55);
    style = RErr, [Int "memsize"], [];
    fish_alias = ["memsize"]; config_only = true;
    blocking = false;
    shortdesc = "set memory allocated to the hypervisor";
    longdesc = "\
This sets the memory size in megabytes allocated to the
hypervisor.  This only has any effect if called before
C<guestfs_launch>.

You can also change this by setting the environment
variable C<LIBGUESTFS_MEMSIZE> before the handle is
created.

For more information on the architecture of libguestfs,
see L<guestfs(3)>." };

  { defaults with
    name = "get_memsize"; added = (1, 0, 55);
    style = RInt "memsize", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestResult (
      [["get_memsize"]], "ret >= 256"), []
    ];
    shortdesc = "get memory allocated to the hypervisor";
    longdesc = "\
This gets the memory size in megabytes allocated to the
hypervisor.

If C<guestfs_set_memsize> was not called
on this handle, and if C<LIBGUESTFS_MEMSIZE> was not set,
then this returns the compiled-in default value for memsize.

For more information on the architecture of libguestfs,
see L<guestfs(3)>." };

  { defaults with
    name = "get_pid"; added = (1, 0, 56);
    style = RInt "pid", [], [];
    fish_alias = ["pid"];
    blocking = false;
    shortdesc = "get PID of hypervisor";
    longdesc = "\
Return the process ID of the hypervisor.  If there is no
hypervisor running, then this will return an error.

This is an internal call used for debugging and testing." };

  { defaults with
    name = "version"; added = (1, 0, 58);
    style = RStruct ("version", "version"), [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestResult (
        [["version"]], "ret->major == 1"), []
    ];
    shortdesc = "get the library version number";
    longdesc = "\
Return the libguestfs version number that the program is linked
against.

Note that because of dynamic linking this is not necessarily
the version of libguestfs that you compiled against.  You can
compile the program, and then at runtime dynamically link
against a completely different F<libguestfs.so> library.

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
Use C<guestfs_available> or C<guestfs_feature_available> instead." };

  { defaults with
    name = "set_selinux"; added = (1, 0, 67);
    style = RErr, [Bool "selinux"], [];
    fish_alias = ["selinux"]; config_only = true;
    blocking = false;
    shortdesc = "set SELinux enabled or disabled at appliance boot";
    longdesc = "\
This sets the selinux flag that is passed to the appliance
at boot time.  The default is C<selinux=0> (disabled).

Note that if SELinux is enabled, it is always in
Permissive mode (C<enforcing=0>).

For more information on the architecture of libguestfs,
see L<guestfs(3)>." };

  { defaults with
    name = "get_selinux"; added = (1, 0, 67);
    style = RBool "selinux", [], [];
    blocking = false;
    shortdesc = "get SELinux enabled flag";
    longdesc = "\
This returns the current setting of the selinux flag which
is passed to the appliance at boot time.  See C<guestfs_set_selinux>.

For more information on the architecture of libguestfs,
see L<guestfs(3)>." };

  { defaults with
    name = "set_trace"; added = (1, 0, 69);
    style = RErr, [Bool "trace"], [];
    fish_alias = ["trace"];
    blocking = false;
    tests = [
      InitNone, Always, TestResultFalse (
        [["set_trace"; "false"];
         ["get_trace"]]), []
    ];
    shortdesc = "enable or disable command traces";
    longdesc = "\
If the command trace flag is set to 1, then libguestfs
calls, parameters and return values are traced.

If you want to trace C API calls into libguestfs (and
other libraries) then possibly a better way is to use
the external L<ltrace(1)> command.

Command traces are disabled unless the environment variable
C<LIBGUESTFS_TRACE> is defined and set to C<1>.

Trace messages are normally sent to C<stderr>, unless you
register a callback to send them somewhere else (see
C<guestfs_set_event_callback>)." };

  { defaults with
    name = "get_trace"; added = (1, 0, 69);
    style = RBool "trace", [], [];
    blocking = false;
    shortdesc = "get command trace enabled flag";
    longdesc = "\
Return the command trace flag." };

  { defaults with
    name = "set_direct"; added = (1, 0, 72);
    style = RErr, [Bool "direct"], [];
    fish_alias = ["direct"]; config_only = true;
    blocking = false;
    shortdesc = "enable or disable direct appliance mode";
    longdesc = "\
If the direct appliance mode flag is enabled, then stdin and
stdout are passed directly through to the appliance once it
is launched.

One consequence of this is that log messages aren't caught
by the library and handled by C<guestfs_set_log_message_callback>,
but go straight to stdout.

You probably don't want to use this unless you know what you
are doing.

The default is disabled." };

  { defaults with
    name = "get_direct"; added = (1, 0, 72);
    style = RBool "direct", [], [];
    blocking = false;
    shortdesc = "get direct appliance mode flag";
    longdesc = "\
Return the direct appliance mode flag." };

  { defaults with
    name = "set_recovery_proc"; added = (1, 0, 77);
    style = RErr, [Bool "recoveryproc"], [];
    fish_alias = ["recovery-proc"]; config_only = true;
    blocking = false;
    shortdesc = "enable or disable the recovery process";
    longdesc = "\
If this is called with the parameter C<false> then
C<guestfs_launch> does not create a recovery process.  The
purpose of the recovery process is to stop runaway hypervisor
processes in the case where the main program aborts abruptly.

This only has any effect if called before C<guestfs_launch>,
and the default is true.

About the only time when you would want to disable this is
if the main process will fork itself into the background
(\"daemonize\" itself).  In this case the recovery process
thinks that the main program has disappeared and so kills
the hypervisor, which is not very helpful." };

  { defaults with
    name = "get_recovery_proc"; added = (1, 0, 77);
    style = RBool "recoveryproc", [], [];
    blocking = false;
    shortdesc = "get recovery process enabled flag";
    longdesc = "\
Return the recovery process enabled flag." };

  { defaults with
    name = "add_drive_with_if"; added = (1, 0, 84);
    style = RErr, [String "filename"; String "iface"], [];
    deprecated_by = Some "add_drive"; config_only = true;
    blocking = false;
    shortdesc = "add a drive specifying the QEMU block emulation to use";
    longdesc = "\
This is the same as C<guestfs_add_drive> but it allows you
to specify the QEMU interface emulation to use at run time." };

  { defaults with
    name = "add_drive_ro_with_if"; added = (1, 0, 84);
    style = RErr, [String "filename"; String "iface"], [];
    blocking = false;
    deprecated_by = Some "add_drive"; config_only = true;
    shortdesc = "add a drive read-only specifying the QEMU block emulation to use";
    longdesc = "\
This is the same as C<guestfs_add_drive_ro> but it allows you
to specify the QEMU interface emulation to use at run time." };

  { defaults with
    name = "file_architecture"; added = (1, 5, 3);
    style = RString "arch", [Pathname "filename"], [];
    tests = [
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-aarch64-dynamic"]], "aarch64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-armv7-dynamic"]], "arm"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-i586-dynamic"]], "i386"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-ppc64-dynamic"]], "ppc64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-ppc64le-dynamic"]], "ppc64le"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-sparc-dynamic"]], "sparc"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-win32.exe"]], "i386"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-win64.exe"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-x86_64-dynamic"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-aarch64.so"]], "aarch64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-armv7.so"]], "arm"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-i586.so"]], "i386"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-ppc64.so"]], "ppc64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-ppc64le.so"]], "ppc64le"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-sparc.so"]], "sparc"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-win32.dll"]], "i386"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-win64.dll"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-x86_64.so"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/initrd-x86_64.img"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/initrd-x86_64.img.gz"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/bin-x86_64-dynamic.gz"]], "x86_64"), [];
      InitISOFS, Always, TestResultString (
        [["file_architecture"; "/lib-i586.so.xz"]], "i386"), [];
    ];
    shortdesc = "detect the architecture of a binary file";
    longdesc = "\
This detects the architecture of the binary F<filename>,
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

=item \"arm\"

32 bit ARM.

=item \"aarch64\"

64 bit ARM.

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

=back" };

  { defaults with
    name = "inspect_os"; added = (1, 5, 3);
    style = RStringList "roots", [], [];
    shortdesc = "inspect disk and return list of operating systems found";
    longdesc = "\
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

See also C<guestfs_list_filesystems>." };

  { defaults with
    name = "inspect_get_type"; added = (1, 5, 3);
    style = RString "name", [Mountable "root"], [];
    shortdesc = "get type of inspected operating system";
    longdesc = "\
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

=item \"openbsd\"

OpenBSD.

=item \"hurd\"

GNU/Hurd.

=item \"dos\"

MS-DOS, FreeDOS and others.

=item \"minix\"

MINIX.

=item \"unknown\"

The operating system type could not be determined.

=back

Future versions of libguestfs may return other strings here.
The caller should be prepared to handle any string.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_arch"; added = (1, 5, 3);
    style = RString "arch", [Mountable "root"], [];
    shortdesc = "get architecture of inspected operating system";
    longdesc = "\
This returns the architecture of the inspected operating system.
The possible return values are listed under
C<guestfs_file_architecture>.

If the architecture could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_distro"; added = (1, 5, 3);
    style = RString "distro", [Mountable "root"], [];
    shortdesc = "get distro of inspected operating system";
    longdesc = "\
This returns the distro (distribution) of the inspected operating
system.

Currently defined distros are:

=over 4

=item \"alpinelinux\"

Alpine Linux.

=item \"altlinux\"

ALT Linux.

=item \"archlinux\"

Arch Linux.

=item \"buildroot\"

Buildroot-derived distro, but not one we specifically recognize.

=item \"centos\"

CentOS.

=item \"cirros\"

Cirros.

=item \"coreos\"

CoreOS.

=item \"debian\"

Debian.

=item \"fedora\"

Fedora.

=item \"freebsd\"

FreeBSD.

=item \"freedos\"

FreeDOS.

=item \"frugalware\"

Frugalware.

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

=item \"netbsd\"

NetBSD.

=item \"openbsd\"

OpenBSD.

=item \"opensuse\"

OpenSUSE.

=item \"oraclelinux\"

Oracle Linux.

=item \"pardus\"

Pardus.

=item \"pldlinux\"

PLD Linux.

=item \"redhat-based\"

Some Red Hat-derived distro.

=item \"rhel\"

Red Hat Enterprise Linux.

=item \"scientificlinux\"

Scientific Linux.

=item \"slackware\"

Slackware.

=item \"sles\"

SuSE Linux Enterprise Server or Desktop.

=item \"suse-based\"

Some openSuSE-derived distro.

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

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_major_version"; added = (1, 5, 3);
    style = RInt "major", [Mountable "root"], [];
    shortdesc = "get major version of inspected operating system";
    longdesc = "\
This returns the major version number of the inspected operating
system.

Windows uses a consistent versioning scheme which is I<not>
reflected in the popular public names used by the operating system.
Notably the operating system known as \"Windows 7\" is really
version 6.1 (ie. major = 6, minor = 1).  You can find out the
real versions corresponding to releases of Windows by consulting
Wikipedia or MSDN.

If the version could not be determined, then C<0> is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_minor_version"; added = (1, 5, 3);
    style = RInt "minor", [Mountable "root"], [];
    shortdesc = "get minor version of inspected operating system";
    longdesc = "\
This returns the minor version number of the inspected operating
system.

If the version could not be determined, then C<0> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_major_version>." };

  { defaults with
    name = "inspect_get_product_name"; added = (1, 5, 3);
    style = RString "product", [Mountable "root"], [];
    shortdesc = "get product name of inspected operating system";
    longdesc = "\
This returns the product name of the inspected operating
system.  The product name is generally some freeform string
which can be displayed to the user, but should not be
parsed by programs.

If the product name could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_mountpoints"; added = (1, 5, 3);
    style = RHashtable "mountpoints", [Mountable "root"], [];
    shortdesc = "get mountpoints of inspected operating system";
    longdesc = "\
This returns a hash of where we think the filesystems
associated with this operating system should be mounted.
Callers should note that this is at best an educated guess
made by reading configuration files such as F</etc/fstab>.
I<In particular note> that this may return filesystems
which are non-existent or not mountable and callers should
be prepared to handle or ignore failures if they try to
mount them.

Each element in the returned hashtable has a key which
is the path of the mountpoint (eg. F</boot>) and a value
which is the filesystem that would be mounted there
(eg. F</dev/sda1>).

Non-mounted devices such as swap devices are I<not>
returned in this list.

For operating systems like Windows which still use drive
letters, this call will only return an entry for the first
drive \"mounted on\" F</>.  For information about the
mapping of drive letters to partitions, see
C<guestfs_inspect_get_drive_mappings>.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_filesystems>." };

  { defaults with
    name = "inspect_get_filesystems"; added = (1, 5, 3);
    style = RStringList "filesystems", [Mountable "root"], [];
    shortdesc = "get filesystems associated with inspected operating system";
    longdesc = "\
This returns a list of all the filesystems that we think
are associated with this operating system.  This includes
the root filesystem, other ordinary filesystems, and
non-mounted devices like swap partitions.

In the case of a multi-boot virtual machine, it is possible
for a filesystem to be shared between operating systems.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_mountpoints>." };

  { defaults with
    name = "set_network"; added = (1, 5, 4);
    style = RErr, [Bool "network"], [];
    fish_alias = ["network"]; config_only = true;
    blocking = false;
    shortdesc = "set enable network flag";
    longdesc = "\
If C<network> is true, then the network is enabled in the
libguestfs appliance.  The default is false.

This affects whether commands are able to access the network
(see L<guestfs(3)/RUNNING COMMANDS>).

You must call this before calling C<guestfs_launch>, otherwise
it has no effect." };

  { defaults with
    name = "get_network"; added = (1, 5, 4);
    style = RBool "network", [], [];
    blocking = false;
    shortdesc = "get enable network flag";
    longdesc = "\
This returns the enable network flag." };

  { defaults with
    name = "list_filesystems"; added = (1, 5, 15);
    style = RHashtable "fses", [], [];
    shortdesc = "list filesystems";
    longdesc = "\
This inspection command looks for filesystems on partitions,
block devices and logical volumes, returning a list of C<mountables>
containing filesystems and their type.

The return value is a hash, where the keys are the devices
containing filesystems, and the values are the filesystem types.
For example:

 \"/dev/sda1\" => \"ntfs\"
 \"/dev/sda2\" => \"ext2\"
 \"/dev/vg_guest/lv_root\" => \"ext4\"
 \"/dev/vg_guest/lv_swap\" => \"swap\"

The key is not necessarily a block device. It may also be an opaque
'mountable' string which can be passed to C<guestfs_mount>.

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
(use C<guestfs_inspect_os> to look for OSes)." };

  { defaults with
    name = "add_drive"; added = (0, 0, 3);
    style = RErr, [String "filename"], [OBool "readonly"; OString "format"; OString "iface"; OString "name"; OString "label"; OString "protocol"; OStringList "server"; OString "username"; OString "secret"; OString "cachemode"; OString "discard"; OBool "copyonread"];
    once_had_no_optargs = true;
    blocking = false;
    fish_alias = ["add"];
    shortdesc = "add an image to examine or modify";
    longdesc = "\
This function adds a disk image called F<filename> to the handle.
F<filename> may be a regular host file or a host device.

When this function is called before C<guestfs_launch> (the
usual case) then the first time you call this function,
the disk appears in the API as F</dev/sda>, the second time
as F</dev/sdb>, and so on.

In libguestfs E<ge> 1.20 you can also call this function
after launch (with some restrictions).  This is called
\"hotplugging\".  When hotplugging, you must specify a
C<label> so that the new disk gets a predictable name.
For more information see L<guestfs(3)/HOTPLUGGING>.

You don't necessarily need to be root when using libguestfs.  However
you obviously do need sufficient permissions to access the filename
for whatever operations you want to perform (ie. read access if you
just want to read the image or write access if you want to modify the
image).

This call checks that F<filename> exists.

F<filename> may be the special string C<\"/dev/null\">.
See L<guestfs(3)/NULL DISKS>.

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

The name the drive had in the original guest, e.g. F</dev/sdb>.
This is used as a hint to the guest inspection process if
it is available.

=item C<label>

Give the disk a label.  The label should be a unique, short
string using I<only> ASCII characters C<[a-zA-Z]>.
As well as its usual name in the API (such as F</dev/sda>),
the drive will also be named F</dev/disk/guestfs/I<label>>.

See L<guestfs(3)/DISK LABELS>.

=item C<protocol>

The optional protocol argument can be used to select an alternate
source protocol.

See also: L<guestfs(3)/REMOTE STORAGE>.

=over 4

=item C<protocol = \"file\">

F<filename> is interpreted as a local file or device.
This is the default if the optional protocol parameter
is omitted.

=item C<protocol = \"nbd\">

Connect to the Network Block Device server.
The C<server> parameter must also be supplied - see below.

See also: L<guestfs(3)/NETWORK BLOCK DEVICE>.

=item C<protocol = \"rbd\">

Connect to the Ceph (librbd/RBD) server.
The C<server> parameter must also be supplied - see below.
The C<username> parameter may be supplied.  See below.
The C<secret> parameter may be supplied.  See below.

See also: L<guestfs(3)/CEPH>.

=back

=item C<server>

For protocols which require access to a remote server, this
is a list of server(s).

 Protocol       Number of servers required
 --------       --------------------------
 file           List must be empty or param not used at all
 nbd            Exactly one
 rbd            Zero or more

Each list element is a string specifying a server.  The string must be
in one of the following formats:

 hostname
 hostname:port
 tcp:hostname
 tcp:hostname:port
 unix:/path/to/socket

If the port number is omitted, then the standard port number
for the protocol is used (see F</etc/services>).

=item C<username>

For the C<rbd>
protocol, this specifies the remote username.

If not given, then no authentication
is attempted for ceph.  But note this sometimes may give unexpected results, for
example if using the libvirt backend and if the libvirt backend is configured to
start the qemu appliance as a special user such as C<qemu.qemu>.  If in doubt,
specify the remote username you want.

=item C<secret>

For the C<rbd> protocol only, this specifies the 'secret' to use when
connecting to the remote device.  It must be base64 encoded.

If not given, then a secret matching the given username will be looked up in the
default keychain locations, or if no username is given, then no authentication
will be used.

=item C<cachemode>

Choose whether or not libguestfs will obey sync operations (safe but slow)
or not (unsafe but fast).  The possible values for this string are:

=over 4

=item C<cachemode = \"writeback\">

This is the default.

Write operations in the API do not return until a L<write(2)>
call has completed in the host [but note this does not imply
that anything gets written to disk].

Sync operations in the API, including implicit syncs caused by
filesystem journalling, will not return until an L<fdatasync(2)>
call has completed in the host, indicating that data has been
committed to disk.

=item C<cachemode = \"unsafe\">

In this mode, there are no guarantees.  Libguestfs may cache
anything and ignore sync requests.  This is suitable only
for scratch or temporary disks.

=back

=item C<discard>

Enable or disable discard (a.k.a. trim or unmap) support on this
drive.  If enabled, operations such as C<guestfs_fstrim> will be able
to discard / make thin / punch holes in the underlying host file
or device.

Possible discard settings are:

=over 4

=item C<discard = \"disable\">

Disable discard support.  This is the default.

=item C<discard = \"enable\">

Enable discard support.  Fail if discard is not possible.

=item C<discard = \"besteffort\">

Enable discard support if possible, but don't fail if it is not
supported.

Since not all backends and not all underlying systems support
discard, this is a good choice if you want to use discard if
possible, but don't mind if it doesn't work.

=back

=item C<copyonread>

The boolean parameter C<copyonread> enables copy-on-read support.
This only affects disk formats which have backing files, and causes
reads to be stored in the overlay layer, speeding up multiple reads
of the same area of disk.

The default is false.

=back" };

  { defaults with
    name = "inspect_get_windows_systemroot"; added = (1, 5, 25);
    style = RString "systemroot", [Mountable "root"], [];
    shortdesc = "get Windows systemroot of inspected operating system";
    longdesc = "\
This returns the Windows systemroot of the inspected guest.
The systemroot is a directory path such as F</WINDOWS>.

This call assumes that the guest is Windows and that the
systemroot could be determined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_roots"; added = (1, 7, 3);
    style = RStringList "roots", [], [];
    shortdesc = "return list of operating systems found by last inspection";
    longdesc = "\
This function is a convenient way to get the list of root
devices, as returned from a previous call to C<guestfs_inspect_os>,
but without redoing the whole inspection process.

This returns an empty list if either no root devices were
found or the caller has not called C<guestfs_inspect_os>.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "debug_drives"; added = (1, 13, 22);
    style = RStringList "cmdline", [], [];
    visibility = VDebug;
    blocking = false;
    shortdesc = "debug the drives (internal use only)";
    longdesc = "\
This returns the internal list of drives.  'debug' commands are
not part of the formal API and can be removed or changed at any time." };

  { defaults with
    name = "add_domain"; added = (1, 7, 4);
    style = RInt "nrdisks", [String "dom"], [OString "libvirturi"; OBool "readonly"; OString "iface"; OBool "live"; OBool "allowuuid"; OString "readonlydisk"; OString "cachemode"; OString "discard"; OBool "copyonread"];
    fish_alias = ["domain"]; config_only = true;
    shortdesc = "add the disk(s) from a named libvirt domain";
    longdesc = "\
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
C<guestfs_add_drive_opts>." };

  { defaults with
    name = "add_libvirt_dom"; added = (1, 29, 14);
    style = RInt "nrdisks", [Pointer ("virDomainPtr", "dom")], [OBool "readonly"; OString "iface"; OBool "live"; OString "readonlydisk"; OString "cachemode"; OString "discard"; OBool "copyonread"];
    config_only = true;
    shortdesc = "add the disk(s) from a libvirt domain";
    longdesc = "\
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
C<guestfs_add_drive_opts>." };

  { defaults with
    name = "inspect_get_package_format"; added = (1, 7, 5);
    style = RString "packageformat", [Mountable "root"], [];
    shortdesc = "get package format used by the operating system";
    longdesc = "\
This function and C<guestfs_inspect_get_package_management> return
the package format and package management tool used by the
inspected operating system.  For example for Fedora these
functions would return C<rpm> (package format), and
C<yum> or C<dnf> (package management).

This returns the string C<unknown> if we could not determine the
package format I<or> if the operating system does not have
a real packaging system (eg. Windows).

Possible strings include:
C<rpm>, C<deb>, C<ebuild>, C<pisi>, C<pacman>, C<pkgsrc>, C<apk>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_package_management"; added = (1, 7, 5);
    style = RString "packagemanagement", [Mountable "root"], [];
    shortdesc = "get package management tool used by the operating system";
    longdesc = "\
C<guestfs_inspect_get_package_format> and this function return
the package format and package management tool used by the
inspected operating system.  For example for Fedora these
functions would return C<rpm> (package format), and
C<yum> or C<dnf> (package management).

This returns the string C<unknown> if we could not determine the
package management tool I<or> if the operating system does not have
a real packaging system (eg. Windows).

Possible strings include: C<yum>, C<dnf>, C<up2date>,
C<apt> (for all Debian derivatives),
C<portage>, C<pisi>, C<pacman>, C<urpmi>, C<zypper>, C<apk>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_list_applications"; added = (1, 7, 8);
    style = RStructList ("applications", "application"), [Mountable "root"], [];
    deprecated_by = Some "inspect_list_applications2";
    shortdesc = "get list of applications installed in the operating system";
    longdesc = "\
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

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_list_applications2"; added = (1, 19, 56);
    style = RStructList ("applications2", "application2"), [Mountable "root"], [];
    shortdesc = "get list of applications installed in the operating system";
    longdesc = "\
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

=item C<app2_name>

The name of the application.  For Red Hat-derived and Debian-derived
Linux guests, this is the package name.

=item C<app2_display_name>

The display name of the application, sometimes localized to the
install language of the guest operating system.

If unavailable this is returned as an empty string C<\"\">.
Callers needing to display something can use C<app2_name> instead.

=item C<app2_epoch>

For package managers which use epochs, this contains the epoch of
the package (an integer).  If unavailable, this is returned as C<0>.

=item C<app2_version>

The version string of the application or package.  If unavailable
this is returned as an empty string C<\"\">.

=item C<app2_release>

The release string of the application or package, for package
managers that use this.  If unavailable this is returned as an
empty string C<\"\">.

=item C<app2_arch>

The architecture string of the application or package, for package
managers that use this.  If unavailable this is returned as an empty
string C<\"\">.

=item C<app2_install_path>

The installation path of the application (on operating systems
such as Windows which use installation paths).  This path is
in the format used by the guest operating system, it is not
a libguestfs path.

If unavailable this is returned as an empty string C<\"\">.

=item C<app2_trans_path>

The install path translated into a libguestfs path.
If unavailable this is returned as an empty string C<\"\">.

=item C<app2_publisher>

The name of the publisher of the application, for package
managers that use this.  If unavailable this is returned
as an empty string C<\"\">.

=item C<app2_url>

The URL (eg. upstream URL) of the application.
If unavailable this is returned as an empty string C<\"\">.

=item C<app2_source_package>

For packaging systems which support this, the name of the source
package.  If unavailable this is returned as an empty string C<\"\">.

=item C<app2_summary>

A short (usually one line) description of the application or package.
If unavailable this is returned as an empty string C<\"\">.

=item C<app2_description>

A longer description of the application or package.
If unavailable this is returned as an empty string C<\"\">.

=back

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_hostname"; added = (1, 7, 9);
    style = RString "hostname", [Mountable "root"], [];
    shortdesc = "get hostname of the operating system";
    longdesc = "\
This function returns the hostname of the operating system
as found by inspection of the guest's configuration files.

If the hostname could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_format"; added = (1, 9, 4);
    style = RString "format", [Mountable "root"], [];
    shortdesc = "get format of inspected operating system";
    longdesc = "\
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

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_live"; added = (1, 9, 4);
    style = RBool "live", [Mountable "root"], [];
    shortdesc = "get live flag for install disk";
    longdesc = "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if a live image
was detected on the disk.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_netinst"; added = (1, 9, 4);
    style = RBool "netinst", [Mountable "root"], [];
    shortdesc = "get netinst (network installer) flag for install disk";
    longdesc = "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if the disk is
a network installer, ie. not a self-contained install CD but
one which is likely to require network access to complete
the install.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_multipart"; added = (1, 9, 4);
    style = RBool "multipart", [Mountable "root"], [];
    shortdesc = "get multipart flag for install disk";
    longdesc = "\
If C<guestfs_inspect_get_format> returns C<installer> (this
is an install disk), then this returns true if the disk is
part of a set.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "set_attach_method"; added = (1, 9, 8);
    style = RErr, [String "backend"], [];
    fish_alias = ["attach-method"]; config_only = true;
    blocking = false;
    deprecated_by = Some "set_backend";
    shortdesc = "set the backend";
    longdesc = "\
Set the method that libguestfs uses to connect to the backend
guestfsd daemon.

See L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "get_attach_method"; added = (1, 9, 8);
    style = RString "backend", [], [];
    blocking = false;
    deprecated_by = Some "get_backend";
    tests = [
      InitNone, Always, TestRun (
        [["get_attach_method"]]), []
    ];
    shortdesc = "get the backend";
    longdesc = "\
Return the current backend.

See C<guestfs_set_backend> and L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "set_backend"; added = (1, 21, 26);
    style = RErr, [String "backend"], [];
    fish_alias = ["backend"]; config_only = true;
    blocking = false;
    shortdesc = "set the backend";
    longdesc = "\
Set the method that libguestfs uses to connect to the backend
guestfsd daemon.

This handle property was previously called the \"attach method\".

See L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "get_backend"; added = (1, 21, 26);
    style = RString "backend", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
        [["get_backend"]]), []
    ];
    shortdesc = "get the backend";
    longdesc = "\
Return the current backend.

This handle property was previously called the \"attach method\".

See C<guestfs_set_backend> and L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "inspect_get_product_variant"; added = (1, 9, 13);
    style = RString "variant", [Mountable "root"], [];
    shortdesc = "get product variant of inspected operating system";
    longdesc = "\
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
C<guestfs_inspect_get_major_version>." };

  { defaults with
    name = "inspect_get_windows_current_control_set"; added = (1, 9, 17);
    style = RString "controlset", [Mountable "root"], [];
    shortdesc = "get Windows CurrentControlSet of inspected operating system";
    longdesc = "\
This returns the Windows CurrentControlSet of the inspected guest.
The CurrentControlSet is a registry key name such as C<ControlSet001>.

This call assumes that the guest is Windows and that the
Registry could be examined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_drive_mappings"; added = (1, 9, 17);
    style = RHashtable "drives", [Mountable "root"], [];
    shortdesc = "get drive letter mappings";
    longdesc = "\
This call is useful for Windows which uses a primitive system
of assigning drive letters (like F<C:\\>) to partitions.
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
C<guestfs_inspect_get_filesystems>." };

  { defaults with
    name = "inspect_get_icon"; added = (1, 11, 12);
    style = RBufferOut "icon", [Mountable "root"],  [OBool "favicon"; OBool "highquality"];
    shortdesc = "get the icon corresponding to this operating system";
    longdesc = "\
This function returns an icon corresponding to the inspected
operating system.  The icon is returned as a buffer containing a
PNG image (re-encoded to PNG if necessary).

If it was not possible to get an icon this function returns a
zero-length (non-NULL) buffer.  I<Callers must check for this case>.

Libguestfs will start by looking for a file called
F</etc/favicon.png> or F<C:\\etc\\favicon.png>
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

=back" };

  { defaults with
    name = "set_pgroup"; added = (1, 11, 18);
    style = RErr, [Bool "pgroup"], [];
    fish_alias = ["pgroup"]; config_only = true;
    blocking = false;
    shortdesc = "set process group flag";
    longdesc = "\
If C<pgroup> is true, child processes are placed into
their own process group.

The practical upshot of this is that signals like C<SIGINT> (from
users pressing C<^C>) won't be received by the child process.

The default for this flag is false, because usually you want
C<^C> to kill the subprocess.  Guestfish sets this flag to
true when used interactively, so that C<^C> can cancel
long-running commands gracefully (see C<guestfs_user_cancel>)." };

  { defaults with
    name = "get_pgroup"; added = (1, 11, 18);
    style = RBool "pgroup", [], [];
    blocking = false;
    shortdesc = "get process group flag";
    longdesc = "\
This returns the process group flag." };

  { defaults with
    name = "set_smp"; added = (1, 13, 15);
    style = RErr, [Int "smp"], [];
    fish_alias = ["smp"]; config_only = true;
    blocking = false;
    shortdesc = "set number of virtual CPUs in appliance";
    longdesc = "\
Change the number of virtual CPUs assigned to the appliance.  The
default is C<1>.  Increasing this may improve performance, though
often it has no effect.

This function must be called before C<guestfs_launch>." };

  { defaults with
    name = "get_smp"; added = (1, 13, 15);
    style = RInt "smp", [], [];
    blocking = false;
    shortdesc = "get number of virtual CPUs in appliance";
    longdesc = "\
This returns the number of virtual CPUs assigned to the appliance." };

  { defaults with
    name = "mount_local"; added = (1, 17, 22);
    style = RErr, [String "localmountpoint"], [OBool "readonly"; OString "options"; OInt "cachetimeout"; OBool "debugcalls"];
    shortdesc = "mount on the local filesystem";
    longdesc = "\
This call exports the libguestfs-accessible filesystem to
a local mountpoint (directory) called C<localmountpoint>.
Ordinary reads and writes to files and directories under
C<localmountpoint> are redirected through libguestfs.

If the optional C<readonly> flag is set to true, then
writes to the filesystem return error C<EROFS>.

C<options> is a comma-separated list of mount options.
See L<guestmount(1)> for some useful options.

C<cachetimeout> sets the timeout (in seconds) for cached directory
entries.  The default is 60 seconds.  See L<guestmount(1)>
for further information.

If C<debugcalls> is set to true, then additional debugging
information is generated for every FUSE call.

When C<guestfs_mount_local> returns, the filesystem is ready,
but is not processing requests (access to it will block).  You
have to call C<guestfs_mount_local_run> to run the main loop.

See L<guestfs(3)/MOUNT LOCAL> for full documentation." };

  { defaults with
    name = "mount_local_run"; added = (1, 17, 22);
    style = RErr, [], [];
    cancellable = true (* in a future version *);
    shortdesc = "run main loop of mount on the local filesystem";
    longdesc = "\
Run the main loop which translates kernel calls to libguestfs
calls.

This should only be called after C<guestfs_mount_local>
returns successfully.  The call will not return until the
filesystem is unmounted.

B<Note> you must I<not> make concurrent libguestfs calls
on the same handle from another thread.

You may call this from a different thread than the one which
called C<guestfs_mount_local>, subject to the usual rules
for threads and libguestfs (see
L<guestfs(3)/MULTIPLE HANDLES AND MULTIPLE THREADS>).

See L<guestfs(3)/MOUNT LOCAL> for full documentation." };

  { defaults with
    name = "umount_local"; added = (1, 17, 22);
    style = RErr, [], [OBool "retry"];
    test_excuse = "tests in fuse subdirectory";
    shortdesc = "unmount a locally mounted filesystem";
    longdesc = "\
If libguestfs is exporting the filesystem on a local
mountpoint, then this unmounts it.

See L<guestfs(3)/MOUNT LOCAL> for full documentation." };

  { defaults with
    name = "max_disks"; added = (1, 19, 7);
    style = RInt "disks", [], [];
    blocking = false;
    shortdesc = "maximum number of disks that may be added";
    longdesc = "\
Return the maximum number of disks that may be added to a
handle (eg. by C<guestfs_add_drive_opts> and similar calls).

This function was added in libguestfs 1.19.7.  In previous
versions of libguestfs the limit was 25.

See L<guestfs(3)/MAXIMUM NUMBER OF DISKS> for additional
information on this topic." };

  { defaults with
    name = "canonical_device_name"; added = (1, 19, 7);
    style = RString "canonical", [String "device"], [];
    shortdesc = "return canonical device name";
    longdesc = "\
This utility function is useful when displaying device names to
the user.  It takes a number of irregular device names and
returns them in a consistent format:

=over 4

=item F</dev/hdX>

=item F</dev/vdX>

These are returned as F</dev/sdX>.  Note this works for device
names and partition names.  This is approximately the reverse of
the algorithm described in L<guestfs(3)/BLOCK DEVICE NAMING>.

=item F</dev/mapper/VG-LV>

=item F</dev/dm-N>

Converted to F</dev/VG/LV> form using C<guestfs_lvm_canonical_lv_name>.

=back

Other strings are returned unmodified." };

  { defaults with
    name = "shutdown"; added = (1, 19, 16);
    style = RErr, [], [];
    shortdesc = "shutdown the hypervisor";
    longdesc = "\
This is the opposite of C<guestfs_launch>.  It performs an orderly
shutdown of the backend process(es).  If the autosync flag is set
(which is the default) then the disk image is synchronized.

If the subprocess exits with an error then this function will return
an error, which should I<not> be ignored (it may indicate that the
disk image could not be written out properly).

It is safe to call this multiple times.  Extra calls are ignored.

This call does I<not> close or free up the handle.  You still
need to call C<guestfs_close> afterwards.

C<guestfs_close> will call this if you don't do it explicitly,
but note that any errors are ignored in that case." };

  { defaults with
    name = "cat"; added = (0, 0, 4);
    style = RString "content", [Pathname "path"], [];
    tests = [
      InitISOFS, Always, TestResultString (
        [["cat"; "/known-2"]], "abcdef\n"), []
    ];
    shortdesc = "list the contents of a file";
    longdesc = "\
Return the contents of the file named C<path>.

Because, in C, this function returns a C<char *>, there is no
way to differentiate between a C<\\0> character in a file and
end of string.  To handle binary files, use the C<guestfs_read_file>
or C<guestfs_download> functions." };

  { defaults with
    name = "find"; added = (1, 0, 27);
    style = RStringList "names", [Pathname "directory"], [];
    tests = [
      InitBasicFS, Always, TestResult (
        [["find"; "/"]],
        "is_string_list (ret, 1, \"lost+found\")"), [];
      InitBasicFS, Always, TestResult (
        [["touch"; "/a"];
         ["mkdir"; "/b"];
         ["touch"; "/b/c"];
         ["find"; "/"]],
        "is_string_list (ret, 4, \"a\", \"b\", \"b/c\", \"lost+found\")"), [];
      InitScratchFS, Always, TestResult (
        [["mkdir_p"; "/find/b/c"];
         ["touch"; "/find/b/c/d"];
         ["find"; "/find/b/"]],
        "is_string_list (ret, 2, \"c\", \"c/d\")"), []
    ];
    shortdesc = "find all files and directories";
    longdesc = "\
This command lists out all files and directories, recursively,
starting at F<directory>.  It is essentially equivalent to
running the shell command C<find directory -print> but some
post-processing happens on the output, described below.

This returns a list of strings I<without any prefix>.  Thus
if the directory structure was:

 /tmp/a
 /tmp/b
 /tmp/c/d

then the returned list from C<guestfs_find> F</tmp> would be
4 elements:

 a
 b
 c
 c/d

If F<directory> is not a directory, then this command returns
an error.

The returned list is sorted." };

  { defaults with
    name = "read_file"; added = (1, 0, 63);
    style = RBufferOut "content", [Pathname "path"], [];
    tests = [
      InitISOFS, Always, TestResult (
        [["read_file"; "/known-4"]],
        "compare_buffers (ret, size, \"abc\\ndef\\nghi\", 11) == 0"), []
    ];
    shortdesc = "read a file";
    longdesc = "\
This calls returns the contents of the file C<path> as a
buffer.

Unlike C<guestfs_cat>, this function can correctly
handle files that contain embedded ASCII NUL characters." };

  { defaults with
    name = "read_lines"; added = (0, 0, 7);
    style = RStringList "lines", [Pathname "path"], [];
    tests = [
      InitISOFS, Always, TestResult (
        [["read_lines"; "/known-4"]],
        "is_string_list (ret, 3, \"abc\", \"def\", \"ghi\")"), [];
      InitISOFS, Always, TestResult (
        [["read_lines"; "/empty"]],
        "is_string_list (ret, 0)"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines1"; "\n"];
         ["read_lines"; "/read_lines1"]],
        "is_string_list (ret, 1, \"\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines2"; "\r\n"];
         ["read_lines"; "/read_lines2"]],
        "is_string_list (ret, 1, \"\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines3"; "\n\r\n"];
         ["read_lines"; "/read_lines3"]],
        "is_string_list (ret, 2, \"\", \"\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines4"; "a"];
         ["read_lines"; "/read_lines4"]],
        "is_string_list (ret, 1, \"a\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines5"; "a\nb"];
         ["read_lines"; "/read_lines5"]],
        "is_string_list (ret, 2, \"a\", \"b\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines6"; "a\nb\n"];
         ["read_lines"; "/read_lines6"]],
        "is_string_list (ret, 2, \"a\", \"b\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines7"; "a\nb\r\n"];
         ["read_lines"; "/read_lines7"]],
        "is_string_list (ret, 2, \"a\", \"b\")"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/read_lines8"; "a\nb\r\n\n"];
         ["read_lines"; "/read_lines8"]],
        "is_string_list (ret, 3, \"a\", \"b\", \"\")"), [];
    ];
    shortdesc = "read file as lines";
    longdesc = "\
Return the contents of the file named C<path>.

The file contents are returned as a list of lines.  Trailing
C<LF> and C<CRLF> character sequences are I<not> returned.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_read_file>
function and split the buffer into lines yourself." };

  { defaults with
    name = "write"; added = (1, 3, 14);
    style = RErr, [Pathname "path"; BufferIn "content"], [];
    tests = [
      InitScratchFS, Always, TestResultString (
        [["write"; "/write"; "new file contents"];
         ["cat"; "/write"]], "new file contents"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/write2"; "\nnew file contents\n"];
         ["cat"; "/write2"]], "\nnew file contents\n"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/write3"; "\n\n"];
         ["cat"; "/write3"]], "\n\n"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/write4"; ""];
         ["cat"; "/write4"]], ""), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/write5"; "\n\n\n"];
         ["cat"; "/write5"]], "\n\n\n"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/write6"; "\n"];
         ["cat"; "/write6"]], "\n"), []
    ];
    shortdesc = "create a new file";
    longdesc = "\
This call creates a file called C<path>.  The content of the
file is the string C<content> (which can contain any 8 bit data).

See also C<guestfs_write_append>." };

  { defaults with
    name = "write_append"; added = (1, 11, 18);
    style = RErr, [Pathname "path"; BufferIn "content"], [];
    tests = [
      InitScratchFS, Always, TestResultString (
        [["write"; "/write_append"; "line1\n"];
         ["write_append"; "/write_append"; "line2\n"];
         ["write_append"; "/write_append"; "line3a"];
         ["write_append"; "/write_append"; "line3b\n"];
         ["cat"; "/write_append"]], "line1\nline2\nline3aline3b\n"), []
    ];
    shortdesc = "append content to end of file";
    longdesc = "\
This call appends C<content> to the end of file C<path>.  If
C<path> does not exist, then a new file is created.

See also C<guestfs_write>." };

  { defaults with
    name = "lstatlist"; added = (1, 0, 77);
    style = RStructList ("statbufs", "stat"), [Pathname "path"; FilenameList "names"], [];
    deprecated_by = Some "lstatnslist";
    shortdesc = "lstat on multiple files";
    longdesc = "\
This call allows you to perform the C<guestfs_lstat> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of stat structs, with a one-to-one
correspondence to the C<names> list.  If any name did not exist
or could not be lstat'd, then the C<st_ino> field of that structure
is set to C<-1>.

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
See also C<guestfs_lxattrlist> for a similarly efficient call
for getting extended attributes." };

  { defaults with
    name = "lstatnslist"; added = (1, 27, 53);
    style = RStructList ("statbufs", "statns"), [Pathname "path"; FilenameList "names"], [];
    shortdesc = "lstat on multiple files";
    longdesc = "\
This call allows you to perform the C<guestfs_lstatns> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of stat structs, with a one-to-one
correspondence to the C<names> list.  If any name did not exist
or could not be lstat'd, then the C<st_ino> field of that structure
is set to C<-1>.

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
See also C<guestfs_lxattrlist> for a similarly efficient call
for getting extended attributes." };

  { defaults with
    name = "lxattrlist"; added = (1, 0, 77);
    style = RStructList ("xattrs", "xattr"), [Pathname "path"; FilenameList "names"], [];
    optional = Some "linuxxattrs";
    shortdesc = "lgetxattr on multiple files";
    longdesc = "\
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
for getting standard stats." };

  { defaults with
    name = "readlinklist"; added = (1, 0, 77);
    style = RStringList "links", [Pathname "path"; FilenameList "names"], [];
    shortdesc = "readlink on multiple files";
    longdesc = "\
This call allows you to do a C<readlink> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of strings, with a one-to-one
correspondence to the C<names> list.  Each string is the
value of the symbolic link.

If the L<readlink(2)> operation fails on any name, then
the corresponding result string is the empty string C<\"\">.
However the whole operation is completed even if there
were L<readlink(2)> errors, and so you can call this
function with names where you don't know if they are
symbolic links already (albeit slightly less efficient).

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips." };

  { defaults with
    name = "ls"; added = (0, 0, 4);
    style = RStringList "listing", [Pathname "directory"], [];
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/ls"];
         ["touch"; "/ls/new"];
         ["touch"; "/ls/newer"];
         ["touch"; "/ls/newest"];
         ["ls"; "/ls"]],
        "is_string_list (ret, 3, \"new\", \"newer\", \"newest\")"), []
    ];
    shortdesc = "list the files in a directory";
    longdesc = "\
List the files in F<directory> (relative to the root directory,
there is no cwd).  The '.' and '..' entries are not returned, but
hidden files are shown." };

  { defaults with
    name = "hivex_value_utf8"; added = (1, 19, 35);
    style = RString "databuf", [Int64 "valueh"], [];
    optional = Some "hivex";
    shortdesc = "return the data field from the (key, datatype, data) tuple";
    longdesc = "\
This calls C<guestfs_hivex_value_value> (which returns the
data field from a hivex value tuple).  It then assumes that
the field is a UTF-16LE string and converts the result to
UTF-8 (or if this is not possible, it returns an error).

This is useful for reading strings out of the Windows registry.
However it is not foolproof because the registry is not
strongly-typed and fields can contain arbitrary or unexpected
data." };

  { defaults with
    name = "disk_format"; added = (1, 19, 38);
    style = RString "format", [String "filename"], [];
    tests = [
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1s.raw"]], "raw"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1s.qcow2"]], "qcow2"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1K.raw"]], "raw"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1K.qcow2"]], "qcow2"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1M.raw"]], "raw"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-1M.qcow2"]], "qcow2"), [];
      InitEmpty, Always, TestResultString (
        [["disk_format"; "../../test-data/blank-disks/blank-disk-with-backing.qcow2"]], "qcow2"), [];
    ];
    shortdesc = "detect the disk format of a disk image";
    longdesc = "\
Detect and return the format of the disk image called F<filename>.
F<filename> can also be a host device, etc.  If the format of the
image could not be detected, then C<\"unknown\"> is returned.

Note that detecting the disk format can be insecure under some
circumstances.  See L<guestfs(3)/CVE-2010-3851>.

See also: L<guestfs(3)/DISK IMAGE FORMATS>" };

  { defaults with
    name = "disk_virtual_size"; added = (1, 19, 39);
    style = RInt64 "size", [String "filename"], [];
    tests = [
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1s.raw"]], "ret == 512"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1s.qcow2"]], "ret == 512"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1K.raw"]], "ret == 1024"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1K.qcow2"]], "ret == 1024"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1M.raw"]], "ret == 1024*1024"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-1M.qcow2"]], "ret == 1024*1024"), [];
      InitEmpty, Always, TestResult (
        [["disk_virtual_size"; "../../test-data/blank-disks/blank-disk-with-backing.qcow2"]], "ret == 1024*1024"), [];
    ];
    shortdesc = "return virtual size of a disk";
    longdesc = "\
Detect and return the virtual size in bytes of the disk image
called F<filename>.

Note that detecting disk features can be insecure under some
circumstances.  See L<guestfs(3)/CVE-2010-3851>." };

  { defaults with
    name = "disk_has_backing_file"; added = (1, 19, 39);
    style = RBool "backingfile", [String "filename"], [];
    tests = [
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1s.raw"]]), [];
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1s.qcow2"]]), [];
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1K.raw"]]), [];
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1K.qcow2"]]), [];
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1M.raw"]]), [];
      InitEmpty, Always, TestResultFalse (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-1M.qcow2"]]), [];
      InitEmpty, Always, TestResultTrue (
        [["disk_has_backing_file"; "../../test-data/blank-disks/blank-disk-with-backing.qcow2"]]), [];
    ];
    shortdesc = "return whether disk has a backing file";
    longdesc = "\
Detect and return whether the disk image F<filename> has a
backing file.

Note that detecting disk features can be insecure under some
circumstances.  See L<guestfs(3)/CVE-2010-3851>." };

  { defaults with
    name = "remove_drive"; added = (1, 19, 49);
    style = RErr, [String "label"], [];
    blocking = false;
    shortdesc = "remove a disk image";
    longdesc = "\
This function is conceptually the opposite of C<guestfs_add_drive_opts>.
It removes the drive that was previously added with label C<label>.

Note that in order to remove drives, you have to add them with
labels (see the optional C<label> argument to C<guestfs_add_drive_opts>).
If you didn't use a label, then they cannot be removed.

You can call this function before or after launching the handle.
If called after launch, if the backend supports it, we try to hot
unplug the drive: see L<guestfs(3)/HOTPLUGGING>.  The disk B<must not>
be in use (eg. mounted) when you do this.  We try to detect if the
disk is in use and stop you from doing this." };

  { defaults with
    name = "set_libvirt_supported_credentials"; added = (1, 19, 52);
    style = RErr, [StringList "creds"], [];
    blocking = false;
    shortdesc = "set libvirt credentials supported by calling program";
    longdesc = "\
Call this function before setting an event handler for
C<GUESTFS_EVENT_LIBVIRT_AUTH>, to supply the list of credential types
that the program knows how to process.

The C<creds> list must be a non-empty list of strings.
Possible strings are:

=over 4

=item C<username>

=item C<authname>

=item C<language>

=item C<cnonce>

=item C<passphrase>

=item C<echoprompt>

=item C<noechoprompt>

=item C<realm>

=item C<external>

=back

See libvirt documentation for the meaning of these credential types.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "get_libvirt_requested_credentials"; added = (1, 19, 52);
    style = RStringList "creds", [], [];
    blocking = false;
    shortdesc = "get list of credentials requested by libvirt";
    longdesc = "\
This should only be called during the event callback
for events of type C<GUESTFS_EVENT_LIBVIRT_AUTH>.

Return the list of credentials requested by libvirt.  Possible
values are a subset of the strings provided when you called
C<guestfs_set_libvirt_supported_credentials>.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "get_libvirt_requested_credential_prompt"; added = (1, 19, 52);
    style = RString "prompt", [Int "index"], [];
    blocking = false;
    shortdesc = "prompt of i'th requested credential";
    longdesc = "\
Get the prompt (provided by libvirt) for the C<index>'th
requested credential.  If libvirt did not provide a prompt,
this returns the empty string C<\"\">.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "get_libvirt_requested_credential_challenge"; added = (1, 19, 52);
    style = RString "challenge", [Int "index"], [];
    blocking = false;
    shortdesc = "challenge of i'th requested credential";
    longdesc = "\
Get the challenge (provided by libvirt) for the C<index>'th
requested credential.  If libvirt did not provide a challenge,
this returns the empty string C<\"\">.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "get_libvirt_requested_credential_defresult"; added = (1, 19, 52);
    style = RString "defresult", [Int "index"], [];
    blocking = false;
    shortdesc = "default result of i'th requested credential";
    longdesc = "\
Get the default result (provided by libvirt) for the C<index>'th
requested credential.  If libvirt did not provide a default result,
this returns the empty string C<\"\">.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "set_libvirt_requested_credential"; added = (1, 19, 52);
    style = RErr, [Int "index"; BufferIn "cred"], [];
    blocking = false;
    shortdesc = "pass requested credential back to libvirt";
    longdesc = "\
After requesting the C<index>'th credential from the user,
call this function to pass the answer back to libvirt.

See L<guestfs(3)/LIBVIRT AUTHENTICATION> for documentation and example code." };

  { defaults with
    name = "parse_environment"; added = (1, 19, 53);
    style = RErr, [], [];
    blocking = false;
    shortdesc = "parse the environment and set handle flags accordingly";
    longdesc = "\
Parse the program's environment and set flags in the handle
accordingly.  For example if C<LIBGUESTFS_DEBUG=1> then the
'verbose' flag is set in the handle.

I<Most programs do not need to call this>.  It is done implicitly
when you call C<guestfs_create>.

See L<guestfs(3)/ENVIRONMENT VARIABLES> for a list of environment
variables that can affect libguestfs handles.  See also
L<guestfs(3)/guestfs_create_flags>, and
C<guestfs_parse_environment_list>." };

  { defaults with
    name = "parse_environment_list"; added = (1, 19, 53);
    style = RErr, [StringList "environment"], [];
    blocking = false;
    shortdesc = "parse the environment and set handle flags accordingly";
    longdesc = "\
Parse the list of strings in the argument C<environment>
and set flags in the handle accordingly.
For example if C<LIBGUESTFS_DEBUG=1> is a string in the list,
then the 'verbose' flag is set in the handle.

This is the same as C<guestfs_parse_environment> except that
it parses an explicit list of strings instead of the program's
environment." };

  { defaults with
    name = "set_tmpdir"; added = (1, 19, 58);
    style = RErr, [OptString "tmpdir"], [];
    fish_alias = ["tmpdir"]; config_only = true;
    blocking = false;
    shortdesc = "set the temporary directory";
    longdesc = "\
Set the directory used by the handle to store temporary files.

The environment variables C<LIBGUESTFS_TMPDIR> and C<TMPDIR>
control the default value: If C<LIBGUESTFS_TMPDIR> is set, then
that is the default.  Else if C<TMPDIR> is set, then that is
the default.  Else F</tmp> is the default." };

  { defaults with
    name = "get_tmpdir"; added = (1, 19, 58);
    style = RString "tmpdir", [], [];
    blocking = false;
    shortdesc = "get the temporary directory";
    longdesc = "\
Get the directory used by the handle to store temporary files." };

  { defaults with
    name = "set_cachedir"; added = (1, 19, 58);
    style = RErr, [OptString "cachedir"], [];
    fish_alias = ["cachedir"]; config_only = true;
    blocking = false;
    shortdesc = "set the appliance cache directory";
    longdesc = "\
Set the directory used by the handle to store the appliance
cache, when using a supermin appliance.  The appliance is
cached and shared between all handles which have the same
effective user ID.

The environment variables C<LIBGUESTFS_CACHEDIR> and C<TMPDIR>
control the default value: If C<LIBGUESTFS_CACHEDIR> is set, then
that is the default.  Else if C<TMPDIR> is set, then that is
the default.  Else F</var/tmp> is the default." };

  { defaults with
    name = "get_cachedir"; added = (1, 19, 58);
    style = RString "cachedir", [], [];
    blocking = false;
    shortdesc = "get the appliance cache directory";
    longdesc = "\
Get the directory used by the handle to store the appliance cache." };

  { defaults with
    name = "user_cancel"; added = (1, 11, 18);
    style = RErr, [], [];
    blocking = false; wrapper = false;
    shortdesc = "cancel the current upload or download operation";
    longdesc = "\
This function cancels the current upload or download operation.

Unlike most other libguestfs calls, this function is signal safe and
thread safe.  You can call it from a signal handler or from another
thread, without needing to do any locking.

The transfer that was in progress (if there is one) will stop shortly
afterwards, and will return an error.  The errno (see
L</guestfs_last_errno>) is set to C<EINTR>, so you can test for this
to find out if the operation was cancelled or failed because of
another error.

No cleanup is performed: for example, if a file was being uploaded
then after cancellation there may be a partially uploaded file.  It is
the caller's responsibility to clean up if necessary.

There are two common places that you might call C<guestfs_user_cancel>:

In an interactive text-based program, you might call it from a
C<SIGINT> signal handler so that pressing C<^C> cancels the current
operation.  (You also need to call L</guestfs_set_pgroup> so that
child processes don't receive the C<^C> signal).

In a graphical program, when the main thread is displaying a progress
bar with a cancel button, wire up the cancel button to call this
function." };

  { defaults with
    name = "set_program"; added = (1, 21, 29);
    style = RErr, [String "program"], [];
    fish_alias = ["program"];
    blocking = false;
    shortdesc = "set the program name";
    longdesc = "\
Set the program name.  This is an informative string which the
main program may optionally set in the handle.

When the handle is created, the program name in the handle is
set to the basename from C<argv[0]>.  If that was not possible,
it is set to the empty string (but never C<NULL>)." };

  { defaults with
    name = "get_program"; added = (1, 21, 29);
    style = RConstString "program", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
        [["get_program"]]), []
    ];
    shortdesc = "get the program name";
    longdesc = "\
Get the program name.  See C<guestfs_set_program>." };

  { defaults with
    name = "add_drive_scratch"; added = (1, 23, 10);
    style = RErr, [Int64 "size"], [OString "name"; OString "label"];
    blocking = false;
    fish_alias = ["scratch"];
    shortdesc = "add a temporary scratch drive";
    longdesc = "\
This command adds a temporary scratch drive to the handle.  The
C<size> parameter is the virtual size (in bytes).  The scratch
drive is blank initially (all reads return zeroes until you start
writing to it).  The drive is deleted when the handle is closed.

The optional arguments C<name> and C<label> are passed through to
C<guestfs_add_drive>." };

  { defaults with
    name = "journal_get"; added = (1, 23, 11);
    style = RStructList ("fields", "xattr"), [], [];
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "read the current journal entry";
    longdesc = "\
Read the current journal entry.  This returns all the fields
in the journal as a set of C<(attrname, attrval)> pairs.  The
C<attrname> is the field name (a string).

The C<attrval> is the field value (a binary blob, often but
not always a string).  Please note that C<attrval> is a byte
array, I<not> a \\0-terminated C string.

The length of data may be truncated to the data threshold
(see: C<guestfs_journal_set_data_threshold>,
C<guestfs_journal_get_data_threshold>).

If you set the data threshold to unlimited (C<0>) then this call
can read a journal entry of any size, ie. it is not limited by
the libguestfs protocol." };

  { defaults with
    name = "disk_create"; added = (1, 25, 31);
    style = RErr, [String "filename"; String "format"; Int64 "size"], [OString "backingfile"; OString "backingformat"; OString "preallocation"; OString "compat"; OInt "clustersize"];
    test_excuse = "tests in tests/create subdirectory";
    shortdesc = "create a blank disk image";
    longdesc = "\
Create a blank disk image called F<filename> (a host file)
with format C<format> (usually C<raw> or C<qcow2>).
The size is C<size> bytes.

If used with the optional C<backingfile> parameter, then a snapshot
is created on top of the backing file.  In this case, C<size> must
be passed as C<-1>.  The size of the snapshot is the same as the
size of the backing file, which is discovered automatically.  You
are encouraged to also pass C<backingformat> to describe the format
of C<backingfile>.

If F<filename> refers to a block device, then the device is
formatted.  The C<size> is ignored since block devices have an
intrinsic size.

The other optional parameters are:

=over 4

=item C<preallocation>

If format is C<raw>, then this can be either C<off> (or C<sparse>)
or C<full> to create a sparse or fully allocated file respectively.
The default is C<off>.

If format is C<qcow2>, then this can be C<off> (or C<sparse>),
C<metadata> or C<full>.  Preallocating metadata can be faster
when doing lots of writes, but uses more space.
The default is C<off>.

=item C<compat>

C<qcow2> only:
Pass the string C<1.1> to use the advanced qcow2 format supported
by qemu E<ge> 1.1.

=item C<clustersize>

C<qcow2> only:
Change the qcow2 cluster size.  The default is 65536 (bytes) and
this setting may be any power of two between 512 and 2097152.

=back

Note that this call does not add the new disk to the handle.  You
may need to call C<guestfs_add_drive_opts> separately." };

  { defaults with
    name = "get_backend_settings"; added = (1, 25, 24);
    style = RStringList "settings", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
        [["get_backend_settings"]]), []
    ];
    shortdesc = "get per-backend settings";
    longdesc = "\
Return the current backend settings.

This call returns all backend settings strings.  If you want to
find a single backend setting, see C<guestfs_get_backend_setting>.

See L<guestfs(3)/BACKEND>, L<guestfs(3)/BACKEND SETTINGS>." };

  { defaults with
    name = "set_backend_settings"; added = (1, 25, 24);
    style = RErr, [StringList "settings"], [];
    config_only = true;
    blocking = false;
    shortdesc = "replace per-backend settings strings";
    longdesc = "\
Set a list of zero or more settings which are passed through to
the current backend.  Each setting is a string which is interpreted
in a backend-specific way, or ignored if not understood by the
backend.

The default value is an empty list, unless the environment
variable C<LIBGUESTFS_BACKEND_SETTINGS> was set when the handle
was created.  This environment variable contains a colon-separated
list of settings.

This call replaces all backend settings.  If you want to replace
a single backend setting, see C<guestfs_set_backend_setting>.
If you want to clear a single backend setting, see
C<guestfs_clear_backend_setting>.

See L<guestfs(3)/BACKEND>, L<guestfs(3)/BACKEND SETTINGS>." };

  { defaults with
    name = "get_backend_setting"; added = (1, 27, 2);
    style = RString "val", [String "name"], [];
    blocking = false;
    shortdesc = "get a single per-backend settings string";
    longdesc = "\
Find a backend setting string which is either C<\"name\"> or
begins with C<\"name=\">.  If C<\"name\">, this returns the
string C<\"1\">.  If C<\"name=\">, this returns the part
after the equals sign (which may be an empty string).

If no such setting is found, this function throws an error.
The errno (see C<guestfs_last_errno>) will be C<ESRCH> in this
case.

See L<guestfs(3)/BACKEND>, L<guestfs(3)/BACKEND SETTINGS>." };

  { defaults with
    name = "set_backend_setting"; added = (1, 27, 2);
    style = RErr, [String "name"; String "val"], [];
    config_only = true;
    blocking = false;
    shortdesc = "set a single per-backend settings string";
    longdesc = "\
Append C<\"name=value\"> to the backend settings string list.
However if a string already exists matching C<\"name\">
or beginning with C<\"name=\">, then that setting is replaced.

See L<guestfs(3)/BACKEND>, L<guestfs(3)/BACKEND SETTINGS>." };

  { defaults with
    name = "clear_backend_setting"; added = (1, 27, 2);
    style = RInt "count", [String "name"], [];
    config_only = true;
    blocking = false;
    shortdesc = "remove a single per-backend settings string";
    longdesc = "\
If there is a backend setting string matching C<\"name\"> or
beginning with C<\"name=\">, then that string is removed
from the backend settings.

This call returns the number of strings which were removed
(which may be 0, 1 or greater than 1).

See L<guestfs(3)/BACKEND>, L<guestfs(3)/BACKEND SETTINGS>." };

  { defaults with
    name = "stat"; added = (1, 9, 2);
    style = RStruct ("statbuf", "stat"), [Pathname "path"], [];
    deprecated_by = Some "statns";
    tests = [
      InitISOFS, Always, TestResult (
        [["stat"; "/empty"]], "ret->size == 0"), []
    ];
    shortdesc = "get file information";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as the L<stat(2)> system call." };

  { defaults with
    name = "lstat"; added = (1, 9, 2);
    style = RStruct ("statbuf", "stat"), [Pathname "path"], [];
    deprecated_by = Some "lstatns";
    tests = [
      InitISOFS, Always, TestResult (
        [["lstat"; "/empty"]], "ret->size == 0"), []
    ];
    shortdesc = "get file information for a symbolic link";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as C<guestfs_stat> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the L<lstat(2)> system call." };

  { defaults with
    name = "c_pointer"; added = (1, 29, 17);
    style = RInt64 "ptr", [], [];
    fish_output = Some FishOutputHexadecimal;
    tests = [
      InitNone, Always, TestRun (
        [["c_pointer"]]), []
    ];
    shortdesc = "return the C pointer to the guestfs_h handle";
    longdesc = "\
In non-C language bindings, this allows you to retrieve the underlying
C pointer to the handle (ie. C<guestfs_h *>).  The purpose of this is
to allow other libraries to interwork with libguestfs." };

  { defaults with
    name = "copy_in"; added = (1, 29, 24);
    style = RErr, [String "localpath"; Pathname "remotedir"], [];
    visibility = VPublicNoFish;
    shortdesc = "copy local files or directories into an image";
    longdesc = "\
C<guestfs_copy_in> copies local files or directories recursively into
the disk image, placing them in the directory called C<remotedir>
(which must exist).

Wildcards cannot be used." };

  { defaults with
    name = "copy_out"; added = (1, 29, 24);
    style = RErr, [Pathname "remotepath"; String "localdir"], [];
    visibility = VPublicNoFish;
    shortdesc = "copy remote files or directories out of an image";
    longdesc = "\
C<guestfs_copy_out> copies remote files or directories recursively
out of the disk image, placing them on the host disk in a local
directory called C<localdir> (which must exist).

To download to the current directory, use C<.> as in:

 C<guestfs_copy_out> /home .

Wildcards cannot be used." };

  { defaults with
    name = "set_identifier"; added = (1, 31, 14);
    style = RErr, [String "identifier"], [];
    fish_alias = ["identifier"];
    blocking = false;
    shortdesc = "set the handle identifier";
    longdesc = "\
This is an informative string which the caller may optionally
set in the handle.  It is printed in various places, allowing
the current handle to be identified in debugging output.

One important place is when tracing is enabled.  If the
identifier string is not an empty string, then trace messages
change from this:

 libguestfs: trace: get_tmpdir
 libguestfs: trace: get_tmpdir = \"/tmp\"

to this:

 libguestfs: trace: ID: get_tmpdir
 libguestfs: trace: ID: get_tmpdir = \"/tmp\"

where C<ID> is the identifier string set by this call.

The identifier must only contain alphanumeric ASCII characters,
underscore and minus sign.  The default is the empty string.

See also C<guestfs_set_program>, C<guestfs_set_trace>,
C<guestfs_get_identifier>." };

  { defaults with
    name = "get_identifier"; added = (1, 31, 14);
    style = RConstString "identifier", [], [];
    blocking = false;
    tests = [
      InitNone, Always, TestRun (
        [["get_identifier"]]), []
    ];
    shortdesc = "get the handle identifier";
    longdesc = "\
Get the handle identifier.  See C<guestfs_set_identifier>." };

  { defaults with
    name = "available"; added = (1, 0, 80);
    style = RErr, [StringList "groups"], [];
    tests = [
      InitNone, Always, TestRun [["available"; ""]], []
    ];
    shortdesc = "test availability of some parts of the API";
    longdesc = "\
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

C<guestfs_feature_available> is the same as this call, but
with a slightly simpler to use API: that call returns a boolean
true/false instead of throwing an error.

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

=back

See also C<guestfs_filesystem_available>." };

  { defaults with
    name = "feature_available"; added = (1, 21, 26);
    style = RBool "isavailable", [StringList "groups"], [];
    tests = [
      InitNone, Always, TestResultTrue [["feature_available"; ""]], []
    ];
    shortdesc = "test availability of some parts of the API";
    longdesc = "\
This is the same as C<guestfs_available>, but unlike that
call it returns a simple true/false boolean result, instead
of throwing an exception if a feature is not found.  For
other documentation see C<guestfs_available>." };

]

(* daemon_functions are any functions which cause some action
 * to take place in the daemon.
 *)

let daemon_functions = [
  { defaults with
    name = "mount"; added = (0, 0, 3);
    style = RErr, [Mountable "mountable"; String "mountpoint"], [];
    proc_nr = Some 1;
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "mount a guest disk at a position in the filesystem";
    longdesc = "\
Mount a guest disk at a position in the filesystem.  Block devices
are named F</dev/sda>, F</dev/sdb> and so on, as they were added to
the guest.  If those block devices contain partitions, they will have
the usual names (eg. F</dev/sda1>).  Also LVM F</dev/VG/LV>-style
names can be used, or 'mountable' strings returned by
C<guestfs_list_filesystems> or C<guestfs_inspect_get_mountpoints>.

The rules are the same as for L<mount(2)>:  A filesystem must
first be mounted on F</> before others can be mounted.  Other
filesystems can only be mounted on directories which already
exist.

The mounted filesystem is writable, if we have sufficient permissions
on the underlying device.

Before libguestfs 1.13.16, this call implicitly added the options
C<sync> and C<noatime>.  The C<sync> option greatly slowed
writes and caused many problems for users.  If your program
might need to work with older versions of libguestfs, use
C<guestfs_mount_options> instead (using an empty string for the
first parameter if you don't want any options)." };

  { defaults with
    name = "sync"; added = (0, 0, 3);
    style = RErr, [], [];
    proc_nr = Some 2;
    tests = [
      InitEmpty, Always, TestRun [["sync"]], []
    ];
    shortdesc = "sync disks, writes are flushed through to the disk image";
    longdesc = "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
closing the handle." };

  { defaults with
    name = "touch"; added = (0, 0, 3);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 3;
    tests = [
      InitScratchFS, Always, TestResultTrue (
        [["touch"; "/touch"];
         ["exists"; "/touch"]]), []
    ];
    shortdesc = "update file timestamps or create a new file";
    longdesc = "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.

This command only works on regular files, and will fail on other
file types such as directories, symbolic links, block special etc." };

  { defaults with
    name = "ll"; added = (0, 0, 4);
    style = RString "listing", [Pathname "directory"], [];
    proc_nr = Some 5;
    test_excuse = "tricky to test because it depends on the exact format of the 'ls -l' command, which changed between Fedora 10 and Fedora 11";
    shortdesc = "list the files in a directory (long format)";
    longdesc = "\
List the files in F<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string." };

  { defaults with
    name = "list_devices"; added = (0, 0, 4);
    style = RStringList "devices", [], [];
    proc_nr = Some 7;
    tests = [
      InitEmpty, Always, TestResult (
        [["list_devices"]],
        "is_device_list (ret, 4, \"/dev/sda\", \"/dev/sdb\", \"/dev/sdc\", \"/dev/sdd\")"), []
    ];
    shortdesc = "list the block devices";
    longdesc = "\
List all the block devices.

The full block device names are returned, eg. F</dev/sda>.

See also C<guestfs_list_filesystems>." };

  { defaults with
    name = "list_partitions"; added = (0, 0, 4);
    style = RStringList "partitions", [], [];
    proc_nr = Some 8;
    tests = [
      InitBasicFS, Always, TestResult (
        [["list_partitions"]],
        "is_device_list (ret, 2, \"/dev/sda1\", \"/dev/sdb1\")"), [];
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["list_partitions"]],
        "is_device_list (ret, 4, \"/dev/sda1\", \"/dev/sda2\", \"/dev/sda3\", \"/dev/sdb1\")"), []
    ];
    shortdesc = "list the partitions";
    longdesc = "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. F</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.

See also C<guestfs_list_filesystems>." };

  { defaults with
    name = "pvs"; added = (0, 0, 4);
    style = RStringList "physvols", [], [];
    proc_nr = Some 9;
    optional = Some "lvm2";
    tests = [
      InitBasicFSonLVM, Always, TestResult (
        [["pvs"]], "is_device_list (ret, 1, \"/dev/sda1\")"), [];
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["pvcreate"; "/dev/sda1"];
         ["pvcreate"; "/dev/sda2"];
         ["pvcreate"; "/dev/sda3"];
         ["pvs"]],
        "is_device_list (ret, 3, \"/dev/sda1\", \"/dev/sda2\", \"/dev/sda3\")"), []
    ];
    shortdesc = "list the LVM physical volumes (PVs)";
    longdesc = "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.

This returns a list of just the device names that contain
PVs (eg. F</dev/sda2>).

See also C<guestfs_pvs_full>." };

  { defaults with
    name = "vgs"; added = (0, 0, 4);
    style = RStringList "volgroups", [], [];
    proc_nr = Some 10;
    optional = Some "lvm2";
    tests = [
      InitBasicFSonLVM, Always, TestResult (
        [["vgs"]], "is_string_list (ret, 1, \"VG\")"), [];
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["pvcreate"; "/dev/sda1"];
         ["pvcreate"; "/dev/sda2"];
         ["pvcreate"; "/dev/sda3"];
         ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
         ["vgcreate"; "VG2"; "/dev/sda3"];
         ["vgs"]],
        "is_string_list (ret, 2, \"VG1\", \"VG2\")"), []
    ];
    shortdesc = "list the LVM volume groups (VGs)";
    longdesc = "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.

This returns a list of just the volume group names that were
detected (eg. C<VolGroup00>).

See also C<guestfs_vgs_full>." };

  { defaults with
    name = "lvs"; added = (0, 0, 4);
    style = RStringList "logvols", [], [];
    proc_nr = Some 11;
    optional = Some "lvm2";
    tests = [
      InitBasicFSonLVM, Always, TestResult (
        [["lvs"]],
        "is_string_list (ret, 1, \"/dev/VG/LV\")"), [];
      InitEmpty, Always, TestResult (
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
         ["lvs"]],
        "is_string_list (ret, 3, \"/dev/VG1/LV1\", \"/dev/VG1/LV2\", \"/dev/VG2/LV3\")"), []
    ];
    shortdesc = "list the LVM logical volumes (LVs)";
    longdesc = "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.

This returns a list of the logical volume device names
(eg. F</dev/VolGroup00/LogVol00>).

See also C<guestfs_lvs_full>, C<guestfs_list_filesystems>." };

  { defaults with
    name = "pvs_full"; added = (0, 0, 4);
    style = RStructList ("physvols", "lvm_pv"), [], [];
    proc_nr = Some 12;
    optional = Some "lvm2";
    shortdesc = "list the LVM physical volumes (PVs)";
    longdesc = "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields." };

  { defaults with
    name = "vgs_full"; added = (0, 0, 4);
    style = RStructList ("volgroups", "lvm_vg"), [], [];
    proc_nr = Some 13;
    optional = Some "lvm2";
    shortdesc = "list the LVM volume groups (VGs)";
    longdesc = "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields." };

  { defaults with
    name = "lvs_full"; added = (0, 0, 4);
    style = RStructList ("logvols", "lvm_lv"), [], [];
    proc_nr = Some 14;
    optional = Some "lvm2";
    shortdesc = "list the LVM logical volumes (LVs)";
    longdesc = "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields." };

  { defaults with
    name = "aug_init"; added = (0, 0, 7);
    style = RErr, [Pathname "root"; Int "flags"], [];
    proc_nr = Some 16;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hostname"; "test.example.org"];
         ["aug_init"; "/"; "0"];
         ["aug_get"; "/files/etc/hostname/hostname"]], "test.example.org"), [["aug_close"]]
    ];
    shortdesc = "create a new Augeas handle";
    longdesc = "\
Create a new Augeas handle for editing configuration files.
If there was any previous Augeas handle associated with this
guestfs session, then it is closed.

You must call this before using any other C<guestfs_aug_*>
commands.

C<root> is the filesystem root.  C<root> must not be NULL,
use F</> instead.

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

To find out more about Augeas, see L<http://augeas.net/>." };

  { defaults with
    name = "aug_close"; added = (0, 0, 7);
    style = RErr, [], [];
    proc_nr = Some 26;
    shortdesc = "close the current Augeas handle";
    longdesc = "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions." };

  { defaults with
    name = "aug_defvar"; added = (0, 0, 7);
    style = RInt "nrnodes", [String "name"; OptString "expr"], [];
    proc_nr = Some 17;
    shortdesc = "define an Augeas variable";
    longdesc = "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset." };

  { defaults with
    name = "aug_defnode"; added = (0, 0, 7);
    style = RStruct ("nrnodescreated", "int_bool"), [String "name"; String "expr"; String "val"], [];
    proc_nr = Some 18;
    shortdesc = "define an Augeas node";
    longdesc = "\
Defines a variable C<name> whose value is the result of
evaluating C<expr>.

If C<expr> evaluates to an empty nodeset, a node is created,
equivalent to calling C<guestfs_aug_set> C<expr>, C<value>.
C<name> will be the nodeset containing that single node.

On success this returns a pair containing the
number of nodes in the nodeset, and a boolean flag
if a node was created." };

  { defaults with
    name = "aug_get"; added = (0, 0, 7);
    style = RString "val", [String "augpath"], [];
    proc_nr = Some 19;
    shortdesc = "look up the value of an Augeas path";
    longdesc = "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned." };

  { defaults with
    name = "aug_set"; added = (0, 0, 7);
    style = RErr, [String "augpath"; String "val"], [];
    proc_nr = Some 20;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hostname"; "test.example.org"];
         ["aug_init"; "/"; "0"];
         ["aug_set"; "/files/etc/hostname/hostname"; "replace.example.com"];
         ["aug_get"; "/files/etc/hostname/hostname"]], "replace.example.com"), [["aug_close"]]
    ];
    shortdesc = "set Augeas path to value";
    longdesc = "\
Set the value associated with C<path> to C<val>.

In the Augeas API, it is possible to clear a node by setting
the value to NULL.  Due to an oversight in the libguestfs API
you cannot do that with this call.  Instead you must use the
C<guestfs_aug_clear> call." };

  { defaults with
    name = "aug_insert"; added = (0, 0, 7);
    style = RErr, [String "augpath"; String "label"; Bool "before"], [];
    proc_nr = Some 21;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hosts"; ""];
         ["aug_init"; "/"; "0"];
         ["aug_insert"; "/files/etc/hosts"; "1"; "false"];
         ["aug_set"; "/files/etc/hosts/1/ipaddr"; "127.0.0.1"];
         ["aug_set"; "/files/etc/hosts/1/canonical"; "foobar"];
         ["aug_clear"; "/files/etc/hosts/1/canonical"];
         ["aug_set"; "/files/etc/hosts/1/canonical"; "localhost"];
         ["aug_save"];
         ["cat"; "/etc/hosts"]], "\n127.0.0.1\tlocalhost\n"), [["aug_close"]]
    ];
    shortdesc = "insert a sibling Augeas node";
    longdesc = "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain F</>, C<*> or end
with a bracketed index C<[N]>." };

  { defaults with
    name = "aug_rm"; added = (0, 0, 7);
    style = RInt "nrnodes", [String "augpath"], [];
    proc_nr = Some 22;
    shortdesc = "remove an Augeas path";
    longdesc = "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed." };

  { defaults with
    name = "aug_mv"; added = (0, 0, 7);
    style = RErr, [String "src"; String "dest"], [];
    proc_nr = Some 23;
    shortdesc = "move Augeas node";
    longdesc = "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists." };

  { defaults with
    name = "aug_match"; added = (0, 0, 7);
    style = RStringList "matches", [String "augpath"], [];
    proc_nr = Some 24;
    shortdesc = "return Augeas nodes which match augpath";
    longdesc = "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree." };

  { defaults with
    name = "aug_save"; added = (0, 0, 7);
    style = RErr, [], [];
    proc_nr = Some 25;
    shortdesc = "write all pending Augeas changes to disk";
    longdesc = "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved." };

  { defaults with
    name = "aug_load"; added = (0, 0, 7);
    style = RErr, [], [];
    proc_nr = Some 27;
    shortdesc = "load files into the tree";
    longdesc = "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details." };

  { defaults with
    name = "aug_ls"; added = (0, 0, 8);
    style = RStringList "matches", [String "augpath"], [];
    proc_nr = Some 28;
    tests = [
      InitBasicFS, Always, TestResult (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hosts"; "127.0.0.1 localhost"];
         ["aug_init"; "/"; "0"];
         ["aug_ls"; "/files/etc/hosts/1"]],
        "is_string_list (ret, 2, \"/files/etc/hosts/1/canonical\", \"/files/etc/hosts/1/ipaddr\")"), [["aug_close"]]
    ];
    shortdesc = "list Augeas nodes under augpath";
    longdesc = "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the resulting nodes into alphabetical order." };

  { defaults with
    name = "rm"; added = (0, 0, 8);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 29;
    tests = [
      InitScratchFS, Always, TestRun
        [["mkdir"; "/rm"];
         ["touch"; "/rm/new"];
         ["rm"; "/rm/new"]], [];
      InitScratchFS, Always, TestLastFail
        [["rm"; "/nosuchfile"]], [];
      InitScratchFS, Always, TestLastFail
        [["mkdir"; "/rm2"];
         ["rm"; "/rm2"]], []
    ];
    shortdesc = "remove a file";
    longdesc = "\
Remove the single file C<path>." };

  { defaults with
    name = "rmdir"; added = (0, 0, 8);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 30;
    tests = [
      InitScratchFS, Always, TestRun
        [["mkdir"; "/rmdir"];
         ["rmdir"; "/rmdir"]], [];
      InitScratchFS, Always, TestLastFail
        [["rmdir"; "/rmdir2"]], [];
      InitScratchFS, Always, TestLastFail
        [["mkdir"; "/rmdir3"];
         ["touch"; "/rmdir3/new"];
         ["rmdir"; "/rmdir3/new"]], []
    ];
    shortdesc = "remove a directory";
    longdesc = "\
Remove the single directory C<path>." };

  { defaults with
    name = "rm_rf"; added = (0, 0, 8);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 31;
    tests = [
      InitScratchFS, Always, TestResultFalse
        [["mkdir"; "/rm_rf"];
         ["mkdir"; "/rm_rf/foo"];
         ["touch"; "/rm_rf/foo/bar"];
         ["rm_rf"; "/rm_rf"];
         ["exists"; "/rm_rf"]], []
    ];
    shortdesc = "remove a file or directory recursively";
    longdesc = "\
Remove the file or directory C<path>, recursively removing the
contents if its a directory.  This is like the C<rm -rf> shell
command." };

  { defaults with
    name = "mkdir"; added = (0, 0, 8);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 32;
    tests = [
      InitScratchFS, Always, TestResultTrue
        [["mkdir"; "/mkdir"];
         ["is_dir"; "/mkdir"; ""]], [];
      InitScratchFS, Always, TestLastFail
        [["mkdir"; "/mkdir2/foo/bar"]], []
    ];
    shortdesc = "create a directory";
    longdesc = "\
Create a directory named C<path>." };

  { defaults with
    name = "mkdir_p"; added = (0, 0, 8);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 33;
    tests = [
      InitScratchFS, Always, TestResultTrue
        [["mkdir_p"; "/mkdir_p/foo/bar"];
         ["is_dir"; "/mkdir_p/foo/bar"; ""]], [];
      InitScratchFS, Always, TestResultTrue
        [["mkdir_p"; "/mkdir_p2/foo/bar"];
         ["is_dir"; "/mkdir_p2/foo"; ""]], [];
      InitScratchFS, Always, TestResultTrue
        [["mkdir_p"; "/mkdir_p3/foo/bar"];
         ["is_dir"; "/mkdir_p3"; ""]], [];
      (* Regression tests for RHBZ#503133: *)
      InitScratchFS, Always, TestRun
        [["mkdir"; "/mkdir_p4"];
         ["mkdir_p"; "/mkdir_p4"]], [];
      InitScratchFS, Always, TestLastFail
        [["touch"; "/mkdir_p5"];
         ["mkdir_p"; "/mkdir_p5"]], []
    ];
    shortdesc = "create a directory and parents";
    longdesc = "\
Create a directory named C<path>, creating any parent directories
as necessary.  This is like the C<mkdir -p> shell command." };

  { defaults with
    name = "chmod"; added = (0, 0, 8);
    style = RErr, [Int "mode"; Pathname "path"], [];
    proc_nr = Some 34;
    shortdesc = "change file mode";
    longdesc = "\
Change the mode (permissions) of C<path> to C<mode>.  Only
numeric modes are supported.

I<Note>: When using this command from guestfish, C<mode>
by default would be decimal, unless you prefix it with
C<0> to get octal, ie. use C<0700> not C<700>.

The mode actually set is affected by the umask." };

  { defaults with
    name = "chown"; added = (0, 0, 8);
    style = RErr, [Int "owner"; Int "group"; Pathname "path"], [];
    proc_nr = Some 35;
    shortdesc = "change file owner and group";
    longdesc = "\
Change the file owner to C<owner> and group to C<group>.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy)." };

  { defaults with
    name = "exists"; added = (0, 0, 8);
    style = RBool "existsflag", [Pathname "path"], [];
    proc_nr = Some 36;
    tests = [
      InitISOFS, Always, TestResultTrue (
        [["exists"; "/empty"]]), [];
      InitISOFS, Always, TestResultTrue (
        [["exists"; "/directory"]]), []
    ];
    shortdesc = "test if file or directory exists";
    longdesc = "\
This returns C<true> if and only if there is a file, directory
(or anything) with the given C<path> name.

See also C<guestfs_is_file>, C<guestfs_is_dir>, C<guestfs_stat>." };

  { defaults with
    name = "is_file"; added = (0, 0, 8);
    style = RBool "fileflag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 37;
    once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResultTrue (
        [["is_file"; "/known-1"; ""]]), [];
      InitISOFS, Always, TestResultFalse (
        [["is_file"; "/directory"; ""]]), [];
      InitISOFS, Always, TestResultTrue (
        [["is_file"; "/abssymlink"; "true"]]), []
    ];
    shortdesc = "test if a regular file";
    longdesc = "\
This returns C<true> if and only if there is a regular file
with the given C<path> name.  Note that it returns false for
other objects like directories.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a file also causes the
function to return true.

See also C<guestfs_stat>." };

  { defaults with
    name = "is_dir"; added = (0, 0, 8);
    style = RBool "dirflag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 38;
    once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_dir"; "/known-3"; ""]]), [];
      InitISOFS, Always, TestResultTrue (
        [["is_dir"; "/directory"; ""]]), []
    ];
    shortdesc = "test if a directory";
    longdesc = "\
This returns C<true> if and only if there is a directory
with the given C<path> name.  Note that it returns false for
other objects like files.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a directory also causes the
function to return true.

See also C<guestfs_stat>." };

  { defaults with
    name = "pvcreate"; added = (0, 0, 8);
    style = RErr, [Device "device"], [];
    proc_nr = Some 39;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["pvcreate"; "/dev/sda1"];
         ["pvcreate"; "/dev/sda2"];
         ["pvcreate"; "/dev/sda3"];
         ["pvs"]],
        "is_device_list (ret, 3, \"/dev/sda1\", \"/dev/sda2\", \"/dev/sda3\")"), []
    ];
    shortdesc = "create an LVM physical volume";
    longdesc = "\
This creates an LVM physical volume on the named C<device>,
where C<device> should usually be a partition name such
as F</dev/sda1>." };

  { defaults with
    name = "vgcreate"; added = (0, 0, 8);
    style = RErr, [String "volgroup"; DeviceList "physvols"], [];
    proc_nr = Some 40;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["pvcreate"; "/dev/sda1"];
         ["pvcreate"; "/dev/sda2"];
         ["pvcreate"; "/dev/sda3"];
         ["vgcreate"; "VG1"; "/dev/sda1 /dev/sda2"];
         ["vgcreate"; "VG2"; "/dev/sda3"];
         ["vgs"]],
        "is_string_list (ret, 2, \"VG1\", \"VG2\")"), [];
      InitEmpty, Always, TestLastFail (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["pvcreate"; "/dev/sda1"];
         ["pvcreate"; "/dev/sda2"];
         ["pvcreate"; "/dev/sda3"];
         ["vgcreate"; "VG1"; "/foo/bar /dev/sda2"]]), [];
    ];
    shortdesc = "create an LVM volume group";
    longdesc = "\
This creates an LVM volume group called C<volgroup>
from the non-empty list of physical volumes C<physvols>." };

  { defaults with
    name = "lvcreate"; added = (0, 0, 8);
    style = RErr, [String "logvol"; String "volgroup"; Int "mbytes"], [];
    proc_nr = Some 41;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
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
        "is_string_list (ret, 5, \"/dev/VG1/LV1\", \"/dev/VG1/LV2\", \"/dev/VG2/LV3\", \"/dev/VG2/LV4\", \"/dev/VG2/LV5\")"), []
    ];
    shortdesc = "create an LVM logical volume";
    longdesc = "\
This creates an LVM logical volume called C<logvol>
on the volume group C<volgroup>, with C<size> megabytes." };

  { defaults with
    name = "sfdisk"; added = (0, 0, 8);
    style = RErr, [Device "device";
                   Int "cyls"; Int "heads"; Int "sectors";
                   StringList "lines"], [];
    proc_nr = Some 43;
    deprecated_by = Some "part_add";
    shortdesc = "create partitions on a block device";
    longdesc = "\
This is a direct interface to the L<sfdisk(8)> program for creating
partitions on block devices.

C<device> should be a block device, for example F</dev/sda>.

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
C<guestfs_part_init>" };

  { defaults with
    name = "write_file"; added = (0, 0, 8);
    style = RErr, [Pathname "path"; String "content"; Int "size"], [];
    proc_nr = Some 44;
    protocol_limit_warning = true; deprecated_by = Some "write";
    (* Regression test for RHBZ#597135. *)
    tests = [
      InitScratchFS, Always, TestLastFail
        [["write_file"; "/write_file"; "abc"; "10000"]], []
    ];
    shortdesc = "create a file";
    longdesc = "\
This call creates a file called C<path>.  The contents of the
file is the string C<content> (which can contain any 8 bit data),
with length C<size>.

As a special case, if C<size> is C<0>
then the length is calculated using C<strlen> (so in this case
the content cannot contain embedded ASCII NULs).

I<NB.> Owing to a bug, writing content containing ASCII NUL
characters does I<not> work, even if the length is specified." };

  { defaults with
    name = "umount"; added = (0, 0, 8);
    style = RErr, [Dev_or_Path "pathordevice"], [OBool "force"; OBool "lazyunmount"];
    proc_nr = Some 45;
    fish_alias = ["unmount"];
    once_had_no_optargs = true;
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["mounts"]], "is_device_list (ret, 1, \"/dev/sda1\")"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["umount"; "/"; "false"; "false"];
         ["mounts"]], "is_string_list (ret, 0)"), []
    ];
    shortdesc = "unmount a filesystem";
    longdesc = "\
This unmounts the given filesystem.  The filesystem may be
specified either by its mountpoint (path) or the device which
contains the filesystem." };

  { defaults with
    name = "mounts"; added = (0, 0, 8);
    style = RStringList "devices", [], [];
    proc_nr = Some 46;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mounts"]], "is_device_list (ret, 1, \"/dev/sdb1\")"), []
    ];
    shortdesc = "show mounted filesystems";
    longdesc = "\
This returns the list of currently mounted filesystems.  It returns
the list of devices (eg. F</dev/sda1>, F</dev/VG/LV>).

Some internal mounts are not shown.

See also: C<guestfs_mountpoints>" };

  { defaults with
    name = "umount_all"; added = (0, 0, 8);
    style = RErr, [], [];
    proc_nr = Some 47;
    fish_alias = ["unmount-all"];
    tests = [
      InitScratchFS, Always, TestResult (
        [["umount_all"];
         ["mounts"]], "is_string_list (ret, 0)"), [];
      (* check that umount_all can unmount nested mounts correctly: *)
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "409599"];
         ["part_add"; "/dev/sda"; "p"; "409600"; "-64"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mkfs"; "ext2"; "/dev/sda2"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mkfs"; "ext2"; "/dev/sda3"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["mkdir"; "/mp1"];
         ["mount"; "/dev/sda2"; "/mp1"];
         ["mkdir"; "/mp1/mp2"];
         ["mount"; "/dev/sda3"; "/mp1/mp2"];
         ["mkdir"; "/mp1/mp2/mp3"];
         ["umount_all"];
         ["mounts"]], "is_string_list (ret, 0)"), []
    ];
    shortdesc = "unmount all filesystems";
    longdesc = "\
This unmounts all mounted filesystems.

Some internal mounts are not unmounted by this call." };

  { defaults with
    name = "lvm_remove_all"; added = (0, 0, 8);
    style = RErr, [], [];
    proc_nr = Some 48;
    optional = Some "lvm2";
    shortdesc = "remove all LVM LVs, VGs and PVs";
    longdesc = "\
This command removes all LVM logical volumes, volume groups
and physical volumes." };

  { defaults with
    name = "file"; added = (1, 9, 1);
    style = RString "description", [Dev_or_Path "path"], [];
    proc_nr = Some 49;
    tests = [
      InitISOFS, Always, TestResultString (
        [["file"; "/empty"]], "empty"), [];
      InitISOFS, Always, TestResultString (
        [["file"; "/known-1"]], "ASCII text"), [];
      InitISOFS, Always, TestLastFail (
        [["file"; "/notexists"]]), [];
      InitISOFS, Always, TestResultString (
        [["file"; "/abssymlink"]], "symbolic link"), [];
      InitISOFS, Always, TestResultString (
        [["file"; "/directory"]], "directory"), []
    ];
    shortdesc = "determine file type";
    longdesc = "\
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
C<guestfs_is_file>, C<guestfs_is_blockdev> (etc), C<guestfs_is_zero>." };

  { defaults with
    name = "command"; added = (1, 9, 1);
    style = RString "output", [StringList "arguments"], [];
    proc_nr = Some 50;
    protocol_limit_warning = true;
    tests = [
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command"];
         ["upload"; "test-command"; "/command/test-command"];
         ["chmod"; "0o755"; "/command/test-command"];
         ["command"; "/command/test-command 1"]], "Result1"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command2"];
         ["upload"; "test-command"; "/command2/test-command"];
         ["chmod"; "0o755"; "/command2/test-command"];
         ["command"; "/command2/test-command 2"]], "Result2\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command3"];
         ["upload"; "test-command"; "/command3/test-command"];
         ["chmod"; "0o755"; "/command3/test-command"];
         ["command"; "/command3/test-command 3"]], "\nResult3"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command4"];
         ["upload"; "test-command"; "/command4/test-command"];
         ["chmod"; "0o755"; "/command4/test-command"];
         ["command"; "/command4/test-command 4"]], "\nResult4\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command5"];
         ["upload"; "test-command"; "/command5/test-command"];
         ["chmod"; "0o755"; "/command5/test-command"];
         ["command"; "/command5/test-command 5"]], "\nResult5\n\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command6"];
         ["upload"; "test-command"; "/command6/test-command"];
         ["chmod"; "0o755"; "/command6/test-command"];
         ["command"; "/command6/test-command 6"]], "\n\nResult6\n\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command7"];
         ["upload"; "test-command"; "/command7/test-command"];
         ["chmod"; "0o755"; "/command7/test-command"];
         ["command"; "/command7/test-command 7"]], ""), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command8"];
         ["upload"; "test-command"; "/command8/test-command"];
         ["chmod"; "0o755"; "/command8/test-command"];
         ["command"; "/command8/test-command 8"]], "\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command9"];
         ["upload"; "test-command"; "/command9/test-command"];
         ["chmod"; "0o755"; "/command9/test-command"];
         ["command"; "/command9/test-command 9"]], "\n\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command10"];
         ["upload"; "test-command"; "/command10/test-command"];
         ["chmod"; "0o755"; "/command10/test-command"];
         ["command"; "/command10/test-command 10"]], "Result10-1\nResult10-2\n"), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/command11"];
         ["upload"; "test-command"; "/command11/test-command"];
         ["chmod"; "0o755"; "/command11/test-command"];
         ["command"; "/command11/test-command 11"]], "Result11-1\nResult11-2"), [];
      InitScratchFS, IfNotCrossAppliance, TestLastFail (
        [["mkdir"; "/command12"];
         ["upload"; "test-command"; "/command12/test-command"];
         ["chmod"; "0o755"; "/command12/test-command"];
         ["command"; "/command12/test-command"]]), [];
      InitScratchFS, IfNotCrossAppliance, TestResultString (
        [["mkdir"; "/pwd"];
         ["upload"; "test-pwd"; "/pwd/test-pwd"];
         ["chmod"; "0o755"; "/pwd/test-pwd"];
         ["command"; "/pwd/test-pwd"]], "/"), [];
    ];
    shortdesc = "run a command from the guest filesystem";
    longdesc = "\
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
F</usr/bin> and F</bin>.  If you require a program from
another location, you should provide the full path in the
first parameter.

Shared libraries and data files required by the program
must be available on filesystems which are mounted in the
correct places.  It is the caller's responsibility to ensure
all filesystems that are needed are mounted at the right
locations." };

  { defaults with
    name = "command_lines"; added = (1, 9, 1);
    style = RStringList "lines", [StringList "arguments"], [];
    proc_nr = Some 51;
    protocol_limit_warning = true;
    tests = [
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines"];
         ["upload"; "test-command"; "/command_lines/test-command"];
         ["chmod"; "0o755"; "/command_lines/test-command"];
         ["command_lines"; "/command_lines/test-command 1"]],
        "is_string_list (ret, 1, \"Result1\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines2"];
         ["upload"; "test-command"; "/command_lines2/test-command"];
         ["chmod"; "0o755"; "/command_lines2/test-command"];
         ["command_lines"; "/command_lines2/test-command 2"]],
        "is_string_list (ret, 1, \"Result2\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines3"];
         ["upload"; "test-command"; "/command_lines3/test-command"];
         ["chmod"; "0o755"; "/command_lines3/test-command"];
         ["command_lines"; "/command_lines3/test-command 3"]],
        "is_string_list (ret, 2, \"\", \"Result3\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines4"];
         ["upload"; "test-command"; "/command_lines4/test-command"];
         ["chmod"; "0o755"; "/command_lines4/test-command"];
         ["command_lines"; "/command_lines4/test-command 4"]],
        "is_string_list (ret, 2, \"\", \"Result4\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines5"];
         ["upload"; "test-command"; "/command_lines5/test-command"];
         ["chmod"; "0o755"; "/command_lines5/test-command"];
         ["command_lines"; "/command_lines5/test-command 5"]],
        "is_string_list (ret, 3, \"\", \"Result5\", \"\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines6"];
         ["upload"; "test-command"; "/command_lines6/test-command"];
         ["chmod"; "0o755"; "/command_lines6/test-command"];
         ["command_lines"; "/command_lines6/test-command 6"]],
        "is_string_list (ret, 4, \"\", \"\", \"Result6\", \"\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines7"];
         ["upload"; "test-command"; "/command_lines7/test-command"];
         ["chmod"; "0o755"; "/command_lines7/test-command"];
         ["command_lines"; "/command_lines7/test-command 7"]],
        "is_string_list (ret, 0)"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines8"];
         ["upload"; "test-command"; "/command_lines8/test-command"];
         ["chmod"; "0o755"; "/command_lines8/test-command"];
         ["command_lines"; "/command_lines8/test-command 8"]],
        "is_string_list (ret, 1, \"\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines9"];
         ["upload"; "test-command"; "/command_lines9/test-command"];
         ["chmod"; "0o755"; "/command_lines9/test-command"];
         ["command_lines"; "/command_lines9/test-command 9"]],
        "is_string_list (ret, 2, \"\", \"\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines10"];
         ["upload"; "test-command"; "/command_lines10/test-command"];
         ["chmod"; "0o755"; "/command_lines10/test-command"];
         ["command_lines"; "/command_lines10/test-command 10"]],
        "is_string_list (ret, 2, \"Result10-1\", \"Result10-2\")"), [];
      InitScratchFS, IfNotCrossAppliance, TestResult (
        [["mkdir"; "/command_lines11"];
         ["upload"; "test-command"; "/command_lines11/test-command"];
         ["chmod"; "0o755"; "/command_lines11/test-command"];
         ["command_lines"; "/command_lines11/test-command 11"]],
        "is_string_list (ret, 2, \"Result11-1\", \"Result11-2\")"), []
    ];
    shortdesc = "run a command, returning lines";
    longdesc = "\
This is the same as C<guestfs_command>, but splits the
result into a list of lines.

See also: C<guestfs_sh_lines>" };

  { defaults with
    name = "statvfs"; added = (1, 9, 2);
    style = RStruct ("statbuf", "statvfs"), [Pathname "path"], [];
    proc_nr = Some 54;
    tests = [
      InitISOFS, Always, TestResult (
        [["statvfs"; "/"]], "ret->namemax == 255"), []
    ];
    shortdesc = "get file system statistics";
    longdesc = "\
Returns file system statistics for any mounted file system.
C<path> should be a file or directory in the mounted file system
(typically it is the mount point itself, but it doesn't need to be).

This is the same as the L<statvfs(2)> system call." };

  { defaults with
    name = "tune2fs_l"; added = (1, 9, 2);
    style = RHashtable "superblock", [Device "device"], [];
    proc_nr = Some 55;
    tests = [
      InitScratchFS, Always, TestResult (
        [["tune2fs_l"; "/dev/sdb1"]],
        "check_hash (ret, \"Filesystem magic number\", \"0xEF53\") == 0 && "^
          "check_hash (ret, \"Filesystem OS type\", \"Linux\") == 0"), [];
    ];
    shortdesc = "get ext2/ext3/ext4 superblock details";
    longdesc = "\
This returns the contents of the ext2, ext3 or ext4 filesystem
superblock on C<device>.

It is the same as running C<tune2fs -l device>.  See L<tune2fs(8)>
manpage for more details.  The list of fields returned isn't
clearly defined, and depends on both the version of C<tune2fs>
that libguestfs was built against, and the filesystem itself." };

  { defaults with
    name = "blockdev_setro"; added = (1, 9, 3);
    style = RErr, [Device "device"], [];
    proc_nr = Some 56;
    tests = [
      InitEmpty, Always, TestResultTrue (
        [["blockdev_setro"; "/dev/sda"];
         ["blockdev_getro"; "/dev/sda"]]), []
    ];
    shortdesc = "set block device to read-only";
    longdesc = "\
Sets the block device named C<device> to read-only.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_setrw"; added = (1, 9, 3);
    style = RErr, [Device "device"], [];
    proc_nr = Some 57;
    tests = [
      InitEmpty, Always, TestResultFalse (
        [["blockdev_setrw"; "/dev/sda"];
         ["blockdev_getro"; "/dev/sda"]]), []
    ];
    shortdesc = "set block device to read-write";
    longdesc = "\
Sets the block device named C<device> to read-write.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_getro"; added = (1, 9, 3);
    style = RBool "ro", [Device "device"], [];
    proc_nr = Some 58;
    tests = [
      InitEmpty, Always, TestResultTrue (
        [["blockdev_setro"; "/dev/sda"];
         ["blockdev_getro"; "/dev/sda"]]), []
    ];
    shortdesc = "is block device set to read-only";
    longdesc = "\
Returns a boolean indicating if the block device is read-only
(true if read-only, false if not).

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_getss"; added = (1, 9, 3);
    style = RInt "sectorsize", [Device "device"], [];
    proc_nr = Some 59;
    tests = [
      InitEmpty, Always, TestResult (
        [["blockdev_getss"; "/dev/sda"]], "ret == 512"), []
    ];
    shortdesc = "get sectorsize of block device";
    longdesc = "\
This returns the size of sectors on a block device.
Usually 512, but can be larger for modern devices.

(Note, this is not the size in sectors, use C<guestfs_blockdev_getsz>
for that).

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_getbsz"; added = (1, 9, 3);
    style = RInt "blocksize", [Device "device"], [];
    proc_nr = Some 60;
    test_excuse = "cannot be tested because output differs depending on page size";
    shortdesc = "get blocksize of block device";
    longdesc = "\
This returns the block size of a device.

Note: this is different from both I<size in blocks> and
I<filesystem block size>.  Also this setting is not really
used by anything.  You should probably not use it for
anything.  Filesystems have their own idea about what
block size to choose.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_setbsz"; added = (1, 9, 3);
    style = RErr, [Device "device"; Int "blocksize"], [];
    proc_nr = Some 61;
    deprecated_by = Some "mkfs";
    shortdesc = "set blocksize of block device";
    longdesc = "\
This call does nothing and has never done anything
because of a bug in blockdev.  B<Do not use it.>

If you need to set the filesystem block size, use the
C<blocksize> option of C<guestfs_mkfs>." };

  { defaults with
    name = "blockdev_getsz"; added = (1, 9, 3);
    style = RInt64 "sizeinsectors", [Device "device"], [];
    proc_nr = Some 62;
    tests = [
      InitEmpty, Always, TestResult (
        [["blockdev_getsz"; "/dev/sda"]],
          "ret == INT64_C(2)*1024*1024*1024/512"), []
    ];
    shortdesc = "get total size of device in 512-byte sectors";
    longdesc = "\
This returns the size of the device in units of 512-byte sectors
(even if the sectorsize isn't 512 bytes ... weird).

See also C<guestfs_blockdev_getss> for the real sector size of
the device, and C<guestfs_blockdev_getsize64> for the more
useful I<size in bytes>.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_getsize64"; added = (1, 9, 3);
    style = RInt64 "sizeinbytes", [Device "device"], [];
    proc_nr = Some 63;
    tests = [
      InitEmpty, Always, TestResult (
        [["blockdev_getsize64"; "/dev/sda"]],
          "ret == INT64_C(2)*1024*1024*1024"), []
    ];
    shortdesc = "get total size of device in bytes";
    longdesc = "\
This returns the size of the device in bytes.

See also C<guestfs_blockdev_getsz>.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_flushbufs"; added = (1, 9, 3);
    style = RErr, [Device "device"], [];
    proc_nr = Some 64;
    tests = [
      InitEmpty, Always, TestRun
        [["blockdev_flushbufs"; "/dev/sda"]], []
    ];
    shortdesc = "flush device buffers";
    longdesc = "\
This tells the kernel to flush internal buffers associated
with C<device>.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "blockdev_rereadpt"; added = (1, 9, 3);
    style = RErr, [Device "device"], [];
    proc_nr = Some 65;
    tests = [
      InitEmpty, Always, TestRun
        [["blockdev_rereadpt"; "/dev/sda"]], []
    ];
    shortdesc = "reread partition table";
    longdesc = "\
Reread the partition table on C<device>.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "upload"; added = (1, 0, 2);
    style = RErr, [FileIn "filename"; Dev_or_Path "remotefilename"], [];
    proc_nr = Some 66;
    progress = true; cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        (* Pick a file from cwd which isn't likely to change. *)
        [["mkdir"; "/upload"];
         ["upload"; "$srcdir/../../COPYING.LIB"; "/upload/COPYING.LIB"];
         ["checksum"; "md5"; "/upload/COPYING.LIB"]],
        Digest.to_hex (Digest.file "COPYING.LIB")), []
    ];
    shortdesc = "upload a file from the local machine";
    longdesc = "\
Upload local file F<filename> to F<remotefilename> on the
filesystem.

F<filename> can also be a named pipe.

See also C<guestfs_download>." };

  { defaults with
    name = "download"; added = (1, 0, 2);
    style = RErr, [Dev_or_Path "remotefilename"; FileOut "filename"], [];
    proc_nr = Some 67;
    progress = true; cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        (* Pick a file from cwd which isn't likely to change. *)
        [["mkdir"; "/download"];
         ["upload"; "$srcdir/../../COPYING.LIB"; "/download/COPYING.LIB"];
         ["download"; "/download/COPYING.LIB"; "testdownload.tmp"];
         ["upload"; "testdownload.tmp"; "/download/upload"];
         ["checksum"; "md5"; "/download/upload"]],
        Digest.to_hex (Digest.file "COPYING.LIB")), []
    ];
    shortdesc = "download a file to the local machine";
    longdesc = "\
Download file F<remotefilename> and save it as F<filename>
on the local machine.

F<filename> can also be a named pipe.

See also C<guestfs_upload>, C<guestfs_cat>." };

  { defaults with
    name = "checksum"; added = (1, 0, 2);
    style = RString "checksum", [String "csumtype"; Pathname "path"], [];
    proc_nr = Some 68;
    tests = [
      InitISOFS, Always, TestResultString (
        [["checksum"; "crc"; "/known-3"]], "2891671662"), [];
      InitISOFS, Always, TestLastFail (
        [["checksum"; "crc"; "/notexists"]]), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "md5"; "/known-3"]], "46d6ca27ee07cdc6fa99c2e138cc522c"), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha1"; "/known-3"]], "b7ebccc3ee418311091c3eda0a45b83c0a770f15"), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha224"; "/known-3"]], "d2cd1774b28f3659c14116be0a6dc2bb5c4b350ce9cd5defac707741"), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha256"; "/known-3"]], "75bb71b90cd20cb13f86d2bea8dad63ac7194e7517c3b52b8d06ff52d3487d30"), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha384"; "/known-3"]], "5fa7883430f357b5d7b7271d3a1d2872b51d73cba72731de6863d3dea55f30646af2799bef44d5ea776a5ec7941ac640"), [];
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha512"; "/known-3"]], "2794062c328c6b216dca90443b7f7134c5f40e56bd0ed7853123275a09982a6f992e6ca682f9d2fba34a4c5e870d8fe077694ff831e3032a004ee077e00603f6"), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestResultString (
        [["checksum"; "sha512"; "/abssymlink"]], "5f57d0639bc95081c53afc63a449403883818edc64da48930ad6b1a4fb49be90404686877743fbcd7c99811f3def7df7bc22635c885c6a8cf79c806b43451c1a"), []
    ];
    shortdesc = "compute MD5, SHAx or CRC checksum of file";
    longdesc = "\
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

To get the checksums for many files, use C<guestfs_checksums_out>." };

  { defaults with
    name = "tar_in"; added = (1, 0, 3);
    style = RErr, [FileIn "tarfile"; Pathname "directory"], [OString "compress"; OBool "xattrs"; OBool "selinux"; OBool "acls"];
    proc_nr = Some 69;
    once_had_no_optargs = true;
    cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/tar_in"];
         ["tar_in"; "$srcdir/../../test-data/files/helloworld.tar"; "/tar_in"; "NOARG"; ""; ""; ""];
         ["cat"; "/tar_in/hello"]], "hello\n"), [];
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/tar_in_gz"];
         ["tar_in"; "$srcdir/../../test-data/files/helloworld.tar.gz"; "/tar_in_gz"; "gzip"; ""; ""; ""];
         ["cat"; "/tar_in_gz/hello"]], "hello\n"), [];
      InitScratchFS, IfAvailable "xz", TestResultString (
        [["mkdir"; "/tar_in_xz"];
         ["tar_in"; "$srcdir/../../test-data/files/helloworld.tar.xz"; "/tar_in_xz"; "xz"; ""; ""; ""];
         ["cat"; "/tar_in_xz/hello"]], "hello\n"), []
    ];
    shortdesc = "unpack tarfile to directory";
    longdesc = "\
This command uploads and unpacks local file C<tarfile> into F<directory>.

The optional C<compress> flag controls compression.  If not given,
then the input should be an uncompressed tar file.  Otherwise one
of the following strings may be given to select the compression
type of the input file: C<compress>, C<gzip>, C<bzip2>, C<xz>, C<lzop>.
(Note that not all builds of libguestfs will support all of these
compression types).

The other optional arguments are:

=over 4

=item C<xattrs>

If set to true, extended attributes are restored from the tar file.

=item C<selinux>

If set to true, SELinux contexts are restored from the tar file.

=item C<acls>

If set to true, POSIX ACLs are restored from the tar file.

=back" };

  { defaults with
    name = "tar_out"; added = (1, 0, 3);
    style = RErr, [String "directory"; FileOut "tarfile"], [OString "compress"; OBool "numericowner"; OStringList "excludes"; OBool "xattrs"; OBool "selinux"; OBool "acls"];
    proc_nr = Some 70;
    once_had_no_optargs = true;
    cancellable = true;
    shortdesc = "pack directory into tarfile";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<tarfile>.

The optional C<compress> flag controls compression.  If not given,
then the output will be an uncompressed tar file.  Otherwise one
of the following strings may be given to select the compression
type of the output file: C<compress>, C<gzip>, C<bzip2>, C<xz>, C<lzop>.
(Note that not all builds of libguestfs will support all of these
compression types).

The other optional arguments are:

=over 4

=item C<excludes>

A list of wildcards.  Files are excluded if they match any of the
wildcards.

=item C<numericowner>

If set to true, the output tar file will contain UID/GID numbers
instead of user/group names.

=item C<xattrs>

If set to true, extended attributes are saved in the output tar.

=item C<selinux>

If set to true, SELinux contexts are saved in the output tar.

=item C<acls>

If set to true, POSIX ACLs are saved in the output tar.

=back" };

  { defaults with
    name = "tgz_in"; added = (1, 0, 3);
    style = RErr, [FileIn "tarball"; Pathname "directory"], [];
    proc_nr = Some 71;
    deprecated_by = Some "tar_in";
    cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/tgz_in"];
         ["tgz_in"; "$srcdir/../../test-data/files/helloworld.tar.gz"; "/tgz_in"];
         ["cat"; "/tgz_in/hello"]], "hello\n"), []
    ];
    shortdesc = "unpack compressed tarball to directory";
    longdesc = "\
This command uploads and unpacks local file C<tarball> (a
I<gzip compressed> tar file) into F<directory>." };

  { defaults with
    name = "tgz_out"; added = (1, 0, 3);
    style = RErr, [Pathname "directory"; FileOut "tarball"], [];
    proc_nr = Some 72;
    deprecated_by = Some "tar_out";
    cancellable = true;
    shortdesc = "pack directory into compressed tarball";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<tarball>." };

  { defaults with
    name = "mount_ro"; added = (1, 0, 10);
    style = RErr, [Mountable "mountable"; String "mountpoint"], [];
    proc_nr = Some 73;
    tests = [
      InitBasicFS, Always, TestLastFail (
        [["umount"; "/"; "false"; "false"];
         ["mount_ro"; "/dev/sda1"; "/"];
         ["touch"; "/new"]]), [];
      InitBasicFS, Always, TestResultString (
        [["write"; "/new"; "data"];
         ["umount"; "/"; "false"; "false"];
         ["mount_ro"; "/dev/sda1"; "/"];
         ["cat"; "/new"]], "data"), []
    ];
    shortdesc = "mount a guest disk, read-only";
    longdesc = "\
This is the same as the C<guestfs_mount> command, but it
mounts the filesystem with the read-only (I<-o ro>) flag." };

  { defaults with
    name = "mount_options"; added = (1, 0, 10);
    style = RErr, [String "options"; Mountable "mountable"; String "mountpoint"], [];
    proc_nr = Some 74;
    shortdesc = "mount a guest disk with mount options";
    longdesc = "\
This is the same as the C<guestfs_mount> command, but it
allows you to set the mount options as for the
L<mount(8)> I<-o> flag.

If the C<options> parameter is an empty string, then
no options are passed (all options default to whatever
the filesystem uses)." };

  { defaults with
    name = "mount_vfs"; added = (1, 0, 10);
    style = RErr, [String "options"; String "vfstype"; Mountable "mountable"; String "mountpoint"], [];
    proc_nr = Some 75;
    shortdesc = "mount a guest disk with mount options and vfstype";
    longdesc = "\
This is the same as the C<guestfs_mount> command, but it
allows you to set both the mount options and the vfstype
as for the L<mount(8)> I<-o> and I<-t> flags." };

  { defaults with
    name = "debug"; added = (1, 0, 11);
    style = RString "result", [String "subcmd"; StringList "extraargs"], [];
    proc_nr = Some 76;
    visibility = VDebug;
    shortdesc = "debugging and internals";
    longdesc = "\
The C<guestfs_debug> command exposes some internals of
C<guestfsd> (the guestfs daemon) that runs inside the
hypervisor.

There is no comprehensive help for this command.  You have
to look at the file F<daemon/debug.c> in the libguestfs source
to find out what you can do." };

  { defaults with
    name = "lvremove"; added = (1, 0, 13);
    style = RErr, [Device "device"], [];
    proc_nr = Some 77;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["lvremove"; "/dev/VG/LV1"];
         ["lvs"]],
        "is_string_list (ret, 1, \"/dev/VG/LV2\")"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["lvremove"; "/dev/VG"];
         ["lvs"]],
        "is_string_list (ret, 0)"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["lvremove"; "/dev/VG"];
         ["vgs"]],
        "is_string_list (ret, 1, \"VG\")"), []
    ];
    shortdesc = "remove an LVM logical volume";
    longdesc = "\
Remove an LVM logical volume C<device>, where C<device> is
the path to the LV, such as F</dev/VG/LV>.

You can also remove all LVs in a volume group by specifying
the VG name, F</dev/VG>." };

  { defaults with
    name = "vgremove"; added = (1, 0, 13);
    style = RErr, [String "vgname"], [];
    proc_nr = Some 78;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["vgremove"; "VG"];
         ["lvs"]],
        "is_string_list (ret, 0)"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["vgremove"; "VG"];
         ["vgs"]],
        "is_string_list (ret, 0)"), []
    ];
    shortdesc = "remove an LVM volume group";
    longdesc = "\
Remove an LVM volume group C<vgname>, (for example C<VG>).

This also forcibly removes all logical volumes in the volume
group (if any)." };

  { defaults with
    name = "pvremove"; added = (1, 0, 13);
    style = RErr, [Device "device"], [];
    proc_nr = Some 79;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["vgremove"; "VG"];
         ["pvremove"; "/dev/sda1"];
         ["lvs"]],
        "is_string_list (ret, 0)"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["vgremove"; "VG"];
         ["pvremove"; "/dev/sda1"];
         ["vgs"]],
        "is_string_list (ret, 0)"), [];
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV1"; "VG"; "50"];
         ["lvcreate"; "LV2"; "VG"; "50"];
         ["vgremove"; "VG"];
         ["pvremove"; "/dev/sda1"];
         ["pvs"]],
        "is_string_list (ret, 0)"), []
    ];
    shortdesc = "remove an LVM physical volume";
    longdesc = "\
This wipes a physical volume C<device> so that LVM will no longer
recognise it.

The implementation uses the C<pvremove> command which refuses to
wipe physical volumes that contain any volume groups, so you have
to remove those first." };

  { defaults with
    name = "set_e2label"; added = (1, 0, 15);
    style = RErr, [Device "device"; String "label"], [];
    proc_nr = Some 80;
    deprecated_by = Some "set_label";
    tests = [
      InitBasicFS, Always, TestResultString (
        [["set_e2label"; "/dev/sda1"; "testlabel"];
         ["get_e2label"; "/dev/sda1"]], "testlabel"), []
    ];
    shortdesc = "set the ext2/3/4 filesystem label";
    longdesc = "\
This sets the ext2/3/4 filesystem label of the filesystem on
C<device> to C<label>.  Filesystem labels are limited to
16 characters.

You can use either C<guestfs_tune2fs_l> or C<guestfs_get_e2label>
to return the existing label on a filesystem." };

  { defaults with
    name = "get_e2label"; added = (1, 0, 15);
    style = RString "label", [Device "device"], [];
    proc_nr = Some 81;
    deprecated_by = Some "vfs_label";
    shortdesc = "get the ext2/3/4 filesystem label";
    longdesc = "\
This returns the ext2/3/4 filesystem label of the filesystem on
C<device>." };

  { defaults with
    name = "set_e2uuid"; added = (1, 0, 15);
    style = RErr, [Device "device"; String "uuid"], [];
    proc_nr = Some 82;
    deprecated_by = Some "set_uuid";
    tests =
      (let uuid = uuidgen () in [
        InitBasicFS, Always, TestResultString (
          [["set_e2uuid"; "/dev/sda1"; uuid];
           ["get_e2uuid"; "/dev/sda1"]], uuid), [];
        InitBasicFS, Always, TestResultString (
          [["set_e2uuid"; "/dev/sda1"; "clear"];
           ["get_e2uuid"; "/dev/sda1"]], ""), [];
        (* We can't predict what UUIDs will be, so just check
           the commands run. *)
        InitBasicFS, Always, TestRun (
          [["set_e2uuid"; "/dev/sda1"; "random"]]), [];
        InitBasicFS, Always, TestRun (
          [["set_e2uuid"; "/dev/sda1"; "time"]]), []
      ]);
    shortdesc = "set the ext2/3/4 filesystem UUID";
    longdesc = "\
This sets the ext2/3/4 filesystem UUID of the filesystem on
C<device> to C<uuid>.  The format of the UUID and alternatives
such as C<clear>, C<random> and C<time> are described in the
L<tune2fs(8)> manpage.

You can use C<guestfs_vfs_uuid> to return the existing UUID
of a filesystem." };

  { defaults with
    name = "get_e2uuid"; added = (1, 0, 15);
    style = RString "uuid", [Device "device"], [];
    proc_nr = Some 83;
    deprecated_by = Some "vfs_uuid";
    tests = [
      (* We can't predict what UUID will be, so just check
         the command run; regression test for RHBZ#597112. *)
      InitNone, Always, TestRun (
        [["mke2journal"; "1024"; "/dev/sdc"];
         ["get_e2uuid"; "/dev/sdc"]]), []
    ];
    shortdesc = "get the ext2/3/4 filesystem UUID";
    longdesc = "\
This returns the ext2/3/4 filesystem UUID of the filesystem on
C<device>." };

  { defaults with
    name = "fsck"; added = (1, 0, 16);
    style = RInt "status", [String "fstype"; Device "device"], [];
    proc_nr = Some 84;
    fish_output = Some FishOutputHexadecimal;
    tests = [
      InitBasicFS, Always, TestResult (
        [["umount"; "/dev/sda1"; "false"; "false"];
         ["fsck"; "ext2"; "/dev/sda1"]], "ret == 0"), [];
      InitBasicFS, Always, TestResult (
        [["umount"; "/dev/sda1"; "false"; "false"];
         ["zero"; "/dev/sda1"];
         ["fsck"; "ext2"; "/dev/sda1"]], "ret == 8"), []
    ];
    shortdesc = "run the filesystem checker";
    longdesc = "\
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

This command is entirely equivalent to running C<fsck -a -t fstype device>." };

  { defaults with
    name = "zero"; added = (1, 0, 16);
    style = RErr, [Device "device"], [];
    proc_nr = Some 85;
    progress = true;
    tests = [
      InitBasicFS, Always, TestRun (
        [["umount"; "/dev/sda1"; "false"; "false"];
         ["zero"; "/dev/sda1"]]), []
    ];
    shortdesc = "write zeroes to the device";
    longdesc = "\
This command writes zeroes over the first few blocks of C<device>.

How many blocks are zeroed isn't specified (but it's I<not> enough
to securely wipe the device).  It should be sufficient to remove
any partition tables, filesystem superblocks and so on.

If blocks are already zero, then this command avoids writing
zeroes.  This prevents the underlying device from becoming non-sparse
or growing unnecessarily.

See also: C<guestfs_zero_device>, C<guestfs_scrub_device>,
C<guestfs_is_zero_device>" };

  { defaults with
    name = "grub_install"; added = (1, 0, 17);
    style = RErr, [Pathname "root"; Device "device"], [];
    proc_nr = Some 86;
    optional = Some "grub";
    (* See:
     * https://bugzilla.redhat.com/show_bug.cgi?id=484986
     * https://bugzilla.redhat.com/show_bug.cgi?id=479760
     *)
    tests = [
      InitBasicFS, Always, TestResultTrue (
        [["mkdir_p"; "/boot/grub"];
         ["write"; "/boot/grub/device.map"; "(hd0) /dev/sda"];
         ["grub_install"; "/"; "/dev/sda"];
         ["is_dir"; "/boot"; ""]]), []
    ];
    shortdesc = "install GRUB 1";
    longdesc = "\
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
it may be that you need to create a F</boot/grub/device.map>
file first that contains the mapping between grub device names
and Linux device names.  It is usually sufficient to create
a file containing:

 (hd0) /dev/vda

replacing F</dev/vda> with the name of the installation device.

=back" };

  { defaults with
    name = "cp"; added = (1, 0, 18);
    style = RErr, [Pathname "src"; Pathname "dest"], [];
    proc_nr = Some 87;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/cp"];
         ["write"; "/cp/old"; "file content"];
         ["cp"; "/cp/old"; "/cp/new"];
         ["cat"; "/cp/new"]], "file content"), [];
      InitScratchFS, Always, TestResultTrue (
        [["mkdir"; "/cp2"];
         ["write"; "/cp2/old"; "file content"];
         ["cp"; "/cp2/old"; "/cp2/new"];
         ["is_file"; "/cp2/old"; ""]]), [];
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/cp3"];
         ["write"; "/cp3/old"; "file content"];
         ["mkdir"; "/cp3/dir"];
         ["cp"; "/cp3/old"; "/cp3/dir/new"];
         ["cat"; "/cp3/dir/new"]], "file content"), []
    ];
    shortdesc = "copy a file";
    longdesc = "\
This copies a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory." };

  { defaults with
    name = "cp_a"; added = (1, 0, 18);
    style = RErr, [Pathname "src"; Pathname "dest"], [];
    proc_nr = Some 88;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/cp_a1"];
         ["mkdir"; "/cp_a2"];
         ["write"; "/cp_a1/file"; "file content"];
         ["cp_a"; "/cp_a1"; "/cp_a2"];
         ["cat"; "/cp_a2/cp_a1/file"]], "file content"), []
    ];
    shortdesc = "copy a file or directory recursively";
    longdesc = "\
This copies a file or directory from C<src> to C<dest>
recursively using the C<cp -a> command." };

  { defaults with
    name = "mv"; added = (1, 0, 18);
    style = RErr, [Pathname "src"; Pathname "dest"], [];
    proc_nr = Some 89;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/mv"];
         ["write"; "/mv/old"; "file content"];
         ["mv"; "/mv/old"; "/mv/new"];
         ["cat"; "/mv/new"]], "file content"), [];
      InitScratchFS, Always, TestResultFalse (
        [["mkdir"; "/mv2"];
         ["write"; "/mv2/old"; "file content"];
         ["mv"; "/mv2/old"; "/mv2/new"];
         ["is_file"; "/mv2/old"; ""]]), []
    ];
    shortdesc = "move a file";
    longdesc = "\
This moves a file from C<src> to C<dest> where C<dest> is
either a destination filename or destination directory.

See also: C<guestfs_rename>." };

  { defaults with
    name = "drop_caches"; added = (1, 0, 18);
    style = RErr, [Int "whattodrop"], [];
    proc_nr = Some 90;
    tests = [
      InitEmpty, Always, TestRun (
        [["drop_caches"; "3"]]), []
    ];
    shortdesc = "drop kernel page cache, dentries and inodes";
    longdesc = "\
This instructs the guest kernel to drop its page cache,
and/or dentries and inode caches.  The parameter C<whattodrop>
tells the kernel what precisely to drop, see
L<http://linux-mm.org/Drop_Caches>

Setting C<whattodrop> to 3 should drop everything.

This automatically calls L<sync(2)> before the operation,
so that the maximum guest memory is freed." };

  { defaults with
    name = "dmesg"; added = (1, 0, 18);
    style = RString "kmsgs", [], [];
    proc_nr = Some 91;
    tests = [
      InitEmpty, Always, TestRun (
        [["dmesg"]]), []
    ];
    shortdesc = "return kernel messages";
    longdesc = "\
This returns the kernel messages (C<dmesg> output) from
the guest kernel.  This is sometimes useful for extended
debugging of problems.

Another way to get the same information is to enable
verbose messages with C<guestfs_set_verbose> or by setting
the environment variable C<LIBGUESTFS_DEBUG=1> before
running the program." };

  { defaults with
    name = "ping_daemon"; added = (1, 0, 18);
    style = RErr, [], [];
    proc_nr = Some 92;
    tests = [
      InitEmpty, Always, TestRun (
        [["ping_daemon"]]), []
    ];
    shortdesc = "ping the guest daemon";
    longdesc = "\
This is a test probe into the guestfs daemon running inside
the libguestfs appliance.  Calling this function checks that the
daemon responds to the ping message, without affecting the daemon
or attached block device(s) in any other way." };

  { defaults with
    name = "equal"; added = (1, 0, 18);
    style = RBool "equality", [Pathname "file1"; Pathname "file2"], [];
    proc_nr = Some 93;
    tests = [
      InitScratchFS, Always, TestResultTrue (
        [["mkdir"; "/equal"];
         ["write"; "/equal/file1"; "contents of a file"];
         ["cp"; "/equal/file1"; "/equal/file2"];
         ["equal"; "/equal/file1"; "/equal/file2"]]), [];
      InitScratchFS, Always, TestResultFalse (
        [["mkdir"; "/equal2"];
         ["write"; "/equal2/file1"; "contents of a file"];
         ["write"; "/equal2/file2"; "contents of another file"];
         ["equal"; "/equal2/file1"; "/equal2/file2"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["mkdir"; "/equal3"];
         ["equal"; "/equal3/file1"; "/equal3/file2"]]), []
    ];
    shortdesc = "test if two files have equal contents";
    longdesc = "\
This compares the two files F<file1> and F<file2> and returns
true if their content is exactly equal, or false otherwise.

The external L<cmp(1)> program is used for the comparison." };

  { defaults with
    name = "strings"; added = (1, 0, 22);
    style = RStringList "stringsout", [Pathname "path"], [];
    proc_nr = Some 94;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["strings"; "/known-5"]],
        "is_string_list (ret, 2, \"abcdefghi\", \"jklmnopqr\")"), [];
      InitISOFS, Always, TestResult (
        [["strings"; "/empty"]],
        "is_string_list (ret, 0)"), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestRun (
        [["strings"; "/abssymlink"]]), []
    ];
    shortdesc = "print the printable strings in a file";
    longdesc = "\
This runs the L<strings(1)> command on a file and returns
the list of printable strings found.

The C<strings> command has, in the past, had problems with
parsing untrusted files.  These are mitigated in the current
version of libguestfs, but see L<guestfs(3)/CVE-2014-8484>." };

  { defaults with
    name = "strings_e"; added = (1, 0, 22);
    style = RStringList "stringsout", [String "encoding"; Pathname "path"], [];
    proc_nr = Some 95;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["strings_e"; "b"; "/known-5"]],
        "is_string_list (ret, 0)"), [];
      InitScratchFS, Always, TestResult (
        [["write"; "/strings_e"; "\000h\000e\000l\000l\000o\000\n\000w\000o\000r\000l\000d\000\n"];
         ["strings_e"; "b"; "/strings_e"]],
        "is_string_list (ret, 2, \"hello\", \"world\")"), []
    ];
    shortdesc = "print the printable strings in a file";
    longdesc = "\
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

The returned strings are transcoded to UTF-8.

The C<strings> command has, in the past, had problems with
parsing untrusted files.  These are mitigated in the current
version of libguestfs, but see L<guestfs(3)/CVE-2014-8484>." };

  { defaults with
    name = "hexdump"; added = (1, 0, 22);
    style = RString "dump", [Pathname "path"], [];
    proc_nr = Some 96;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResultString (
        [["hexdump"; "/known-4"]], "00000000  61 62 63 0a 64 65 66 0a  67 68 69                 |abc.def.ghi|\n0000000b\n"), [];
      (* Test for RHBZ#501888c2 regression which caused large hexdump
       * commands to segfault.
       *)
      InitISOFS, Always, TestRun (
        [["hexdump"; "/100krandom"]]), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestRun (
        [["hexdump"; "/abssymlink"]]), []
    ];
    shortdesc = "dump a file in hexadecimal";
    longdesc = "\
This runs C<hexdump -C> on the given C<path>.  The result is
the human-readable, canonical hex dump of the file." };

  { defaults with
    name = "zerofree"; added = (1, 0, 26);
    style = RErr, [Device "device"], [];
    proc_nr = Some 97;
    optional = Some "zerofree";
    tests = [
      InitNone, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext3"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["write"; "/new"; "test file"];
         ["umount"; "/dev/sda1"; "false"; "false"];
         ["zerofree"; "/dev/sda1"];
         ["mount"; "/dev/sda1"; "/"];
         ["cat"; "/new"]], "test file"), []
    ];
    shortdesc = "zero unused inodes and disk blocks on ext2/3 filesystem";
    longdesc = "\
This runs the I<zerofree> program on C<device>.  This program
claims to zero unused inodes and disk blocks on an ext2/3
filesystem, thus making it possible to compress the filesystem
more effectively.

You should B<not> run this program if the filesystem is
mounted.

It is possible that using this program can damage the filesystem
or data on the filesystem." };

  { defaults with
    name = "pvresize"; added = (1, 0, 26);
    style = RErr, [Device "device"], [];
    proc_nr = Some 98;
    optional = Some "lvm2";
    shortdesc = "resize an LVM physical volume";
    longdesc = "\
This resizes (expands or shrinks) an existing LVM physical
volume to match the new size of the underlying device." };

  { defaults with
    name = "sfdisk_N"; added = (1, 0, 26);
    style = RErr, [Device "device"; Int "partnum";
                   Int "cyls"; Int "heads"; Int "sectors";
                   String "line"], [];
    proc_nr = Some 99;
    deprecated_by = Some "part_add";
    shortdesc = "modify a single partition on a block device";
    longdesc = "\
This runs L<sfdisk(8)> option to modify just the single
partition C<n> (note: C<n> counts from 1).

For other parameters, see C<guestfs_sfdisk>.  You should usually
pass C<0> for the cyls/heads/sectors parameters.

See also: C<guestfs_part_add>" };

  { defaults with
    name = "sfdisk_l"; added = (1, 0, 26);
    style = RString "partitions", [Device "device"], [];
    proc_nr = Some 100;
    deprecated_by = Some "part_list";
    shortdesc = "display the partition table";
    longdesc = "\
This displays the partition table on C<device>, in the
human-readable output of the L<sfdisk(8)> command.  It is
not intended to be parsed.

See also: C<guestfs_part_list>" };

  { defaults with
    name = "sfdisk_kernel_geometry"; added = (1, 0, 26);
    style = RString "partitions", [Device "device"], [];
    proc_nr = Some 101;
    shortdesc = "display the kernel geometry";
    longdesc = "\
This displays the kernel's idea of the geometry of C<device>.

The result is in human-readable format, and not designed to
be parsed." };

  { defaults with
    name = "sfdisk_disk_geometry"; added = (1, 0, 26);
    style = RString "partitions", [Device "device"], [];
    proc_nr = Some 102;
    shortdesc = "display the disk geometry from the partition table";
    longdesc = "\
This displays the disk geometry of C<device> read from the
partition table.  Especially in the case where the underlying
block device has been resized, this can be different from the
kernel's idea of the geometry (see C<guestfs_sfdisk_kernel_geometry>).

The result is in human-readable format, and not designed to
be parsed." };

  { defaults with
    name = "vg_activate_all"; added = (1, 0, 26);
    style = RErr, [Bool "activate"], [];
    proc_nr = Some 103;
    optional = Some "lvm2";
    shortdesc = "activate or deactivate all volume groups";
    longdesc = "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in all volume groups.

This command is the same as running C<vgchange -a y|n>" };

  { defaults with
    name = "vg_activate"; added = (1, 0, 26);
    style = RErr, [Bool "activate"; StringList "volgroups"], [];
    proc_nr = Some 104;
    optional = Some "lvm2";
    shortdesc = "activate or deactivate some volume groups";
    longdesc = "\
This command activates or (if C<activate> is false) deactivates
all logical volumes in the listed volume groups C<volgroups>.

This command is the same as running C<vgchange -a y|n volgroups...>

Note that if C<volgroups> is an empty list then B<all> volume groups
are activated or deactivated." };

  { defaults with
    name = "lvresize"; added = (1, 0, 27);
    style = RErr, [Device "device"; Int "mbytes"], [];
    proc_nr = Some 105;
    optional = Some "lvm2";
    tests = [
      InitNone, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV"; "VG"; "10"];
         ["mkfs"; "ext2"; "/dev/VG/LV"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/VG/LV"; "/"];
         ["write"; "/new"; "test content"];
         ["umount"; "/"; "false"; "false"];
         ["lvresize"; "/dev/VG/LV"; "20"];
         ["e2fsck_f"; "/dev/VG/LV"];
         ["e2fsck"; "/dev/VG/LV"; "true"; "false"];
         ["e2fsck"; "/dev/VG/LV"; "false"; "true"];
         ["resize2fs"; "/dev/VG/LV"];
         ["mount"; "/dev/VG/LV"; "/"];
         ["cat"; "/new"]], "test content"), [];
      InitNone, Always, TestRun (
        (* Make an LV smaller to test RHBZ#587484. *)
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV"; "VG"; "20"];
         ["lvresize"; "/dev/VG/LV"; "10"]]), []
    ];
    shortdesc = "resize an LVM logical volume";
    longdesc = "\
This resizes (expands or shrinks) an existing LVM logical
volume to C<mbytes>.  When reducing, data in the reduced part
is lost." };

  { defaults with
    name = "resize2fs"; added = (1, 0, 27);
    style = RErr, [Device "device"], [];
    proc_nr = Some 106;
    shortdesc = "resize an ext2, ext3 or ext4 filesystem";
    longdesc = "\
This resizes an ext2, ext3 or ext4 filesystem to match the size of
the underlying device.

See also L<guestfs(3)/RESIZE2FS ERRORS>." };

  { defaults with
    name = "e2fsck_f"; added = (1, 0, 29);
    style = RErr, [Device "device"], [];
    proc_nr = Some 108;
    deprecated_by = Some "e2fsck";
    shortdesc = "check an ext2/ext3 filesystem";
    longdesc = "\
This runs C<e2fsck -p -f device>, ie. runs the ext2/ext3
filesystem checker on C<device>, noninteractively (I<-p>),
even if the filesystem appears to be clean (I<-f>)." };

  { defaults with
    name = "sleep"; added = (1, 0, 41);
    style = RErr, [Int "secs"], [];
    proc_nr = Some 109;
    tests = [
      InitNone, Always, TestRun (
        [["sleep"; "1"]]), []
    ];
    shortdesc = "sleep for some seconds";
    longdesc = "\
Sleep for C<secs> seconds." };

  { defaults with
    name = "ntfs_3g_probe"; added = (1, 0, 43);
    style = RInt "status", [Bool "rw"; Device "device"], [];
    proc_nr = Some 110;
    optional = Some "ntfs3g";
    tests = [
      InitNone, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ntfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["ntfs_3g_probe"; "true"; "/dev/sda1"]], "ret == 0"), [];
      InitNone, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["ntfs_3g_probe"; "true"; "/dev/sda1"]], "ret == 12"), []
    ];
    shortdesc = "probe NTFS volume";
    longdesc = "\
This command runs the L<ntfs-3g.probe(8)> command which probes
an NTFS C<device> for mountability.  (Not all NTFS volumes can
be mounted read-write, and some cannot be mounted at all).

C<rw> is a boolean flag.  Set it to true if you want to test
if the volume can be mounted read-write.  Set it to false if
you want to test if the volume can be mounted read-only.

The return value is an integer which C<0> if the operation
would succeed, or some non-zero value documented in the
L<ntfs-3g.probe(8)> manual page." };

  { defaults with
    name = "sh"; added = (1, 0, 50);
    style = RString "output", [String "command"], [];
    proc_nr = Some 111;
    shortdesc = "run a command via the shell";
    longdesc = "\
This call runs a command from the guest filesystem via the
guest's F</bin/sh>.

This is like C<guestfs_command>, but passes the command to:

 /bin/sh -c \"command\"

Depending on the guest's shell, this usually results in
wildcards being expanded, shell expressions being interpolated
and so on.

All the provisos about C<guestfs_command> apply to this call." };

  { defaults with
    name = "sh_lines"; added = (1, 0, 50);
    style = RStringList "lines", [String "command"], [];
    proc_nr = Some 112;
    shortdesc = "run a command via the shell returning lines";
    longdesc = "\
This is the same as C<guestfs_sh>, but splits the result
into a list of lines.

See also: C<guestfs_command_lines>" };

  { defaults with
    name = "glob_expand"; added = (1, 0, 50);
    (* Use Pathname here, and hence ABS_PATH (pattern,...) in
     * generated code in stubs.c, since all valid glob patterns must
     * start with "/".  There is no concept of "cwd" in libguestfs,
     * hence no "."-relative names.
     *)
    style = RStringList "paths", [Pathname "pattern"], [];
    proc_nr = Some 113;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir_p"; "/glob_expand/b/c"];
         ["touch"; "/glob_expand/b/c/d"];
         ["touch"; "/glob_expand/b/c/e"];
         ["glob_expand"; "/glob_expand/b/c/*"]],
        "is_string_list (ret, 2, \"/glob_expand/b/c/d\", \"/glob_expand/b/c/e\")"), [];
      InitScratchFS, Always, TestResult (
        [["mkdir_p"; "/glob_expand2/b/c"];
         ["touch"; "/glob_expand2/b/c/d"];
         ["touch"; "/glob_expand2/b/c/e"];
         ["glob_expand"; "/glob_expand2/*/c/*"]],
        "is_string_list (ret, 2, \"/glob_expand2/b/c/d\", \"/glob_expand2/b/c/e\")"), [];
      InitScratchFS, Always, TestResult (
        [["mkdir_p"; "/glob_expand3/b/c"];
         ["touch"; "/glob_expand3/b/c/d"];
         ["touch"; "/glob_expand3/b/c/e"];
         ["glob_expand"; "/glob_expand3/*/x/*"]],
        "is_string_list (ret, 0)"), []
    ];
    shortdesc = "expand a wildcard path";
    longdesc = "\
This command searches for all the pathnames matching
C<pattern> according to the wildcard expansion rules
used by the shell.

If no paths match, then this returns an empty list
(note: not an error).

It is just a wrapper around the C L<glob(3)> function
with flags C<GLOB_MARK|GLOB_BRACE>.
See that manual page for more details.

Notice that there is no equivalent command for expanding a device
name (eg. F</dev/sd*>).  Use C<guestfs_list_devices>,
C<guestfs_list_partitions> etc functions instead." };

  { defaults with
    name = "scrub_device"; added = (1, 0, 52);
    style = RErr, [Device "device"], [];
    proc_nr = Some 114;
    optional = Some "scrub";
    tests = [
      InitNone, Always, TestRun (	(* use /dev/sdc because it's smaller *)
        [["scrub_device"; "/dev/sdc"]]), []
    ];
    shortdesc = "scrub (securely wipe) a device";
    longdesc = "\
This command writes patterns over C<device> to make data retrieval
more difficult.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details." };

  { defaults with
    name = "scrub_file"; added = (1, 0, 52);
    style = RErr, [Pathname "file"], [];
    proc_nr = Some 115;
    optional = Some "scrub";
    tests = [
      InitScratchFS, Always, TestRun (
        [["write"; "/scrub_file"; "content"];
         ["scrub_file"; "/scrub_file"]]), [];
      InitScratchFS, Always, TestRun (
        [["write"; "/scrub_file_2"; "content"];
         ["ln_s"; "/scrub_file_2"; "/scrub_file_2_link"];
         ["scrub_file"; "/scrub_file_2_link"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["ln_s"; "/scrub_file_3_notexisting"; "/scrub_file_3_link"];
         ["scrub_file"; "/scrub_file_3_link"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["write"; "/scrub_file_4"; "content"];
         ["ln_s"; "../sysroot/scrub_file_4"; "/scrub_file_4_link"];
         ["scrub_file"; "/scrub_file_4_link"]]), [];
    ];
    shortdesc = "scrub (securely wipe) a file";
    longdesc = "\
This command writes patterns over a file to make data retrieval
more difficult.

The file is I<removed> after scrubbing.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details." };

  { defaults with
    name = "scrub_freespace"; added = (1, 0, 52);
    style = RErr, [Pathname "dir"], [];
    proc_nr = Some 116;
    optional = Some "scrub";
    tests = [] (* XXX needs testing *);
    shortdesc = "scrub (securely wipe) free space";
    longdesc = "\
This command creates the directory C<dir> and then fills it
with files until the filesystem is full, and scrubs the files
as for C<guestfs_scrub_file>, and deletes them.
The intention is to scrub any free space on the partition
containing C<dir>.

It is an interface to the L<scrub(1)> program.  See that
manual page for more details." };

  { defaults with
    name = "mkdtemp"; added = (1, 0, 54);
    style = RString "dir", [Pathname "tmpl"], [];
    proc_nr = Some 117;
    tests = [
      InitScratchFS, Always, TestRun (
        [["mkdir"; "/mkdtemp"];
         ["mkdtemp"; "/mkdtemp/tmpXXXXXX"]]), []
    ];
    shortdesc = "create a temporary directory";
    longdesc = "\
This command creates a temporary directory.  The
C<tmpl> parameter should be a full pathname for the
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

See also: L<mkdtemp(3)>" };

  { defaults with
    name = "wc_l"; added = (1, 0, 54);
    style = RInt "lines", [Pathname "path"], [];
    proc_nr = Some 118;
    tests = [
      InitISOFS, Always, TestResult (
        [["wc_l"; "/10klines"]], "ret == 10000"), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestResult (
        [["wc_l"; "/abssymlink"]], "ret == 10000"), []
    ];
    shortdesc = "count lines in a file";
    longdesc = "\
This command counts the lines in a file, using the
C<wc -l> external command." };

  { defaults with
    name = "wc_w"; added = (1, 0, 54);
    style = RInt "words", [Pathname "path"], [];
    proc_nr = Some 119;
    tests = [
      InitISOFS, Always, TestResult (
        [["wc_w"; "/10klines"]], "ret == 10000"), []
    ];
    shortdesc = "count words in a file";
    longdesc = "\
This command counts the words in a file, using the
C<wc -w> external command." };

  { defaults with
    name = "wc_c"; added = (1, 0, 54);
    style = RInt "chars", [Pathname "path"], [];
    proc_nr = Some 120;
    tests = [
      InitISOFS, Always, TestResult (
        [["wc_c"; "/100kallspaces"]], "ret == 102400"), []
    ];
    shortdesc = "count characters in a file";
    longdesc = "\
This command counts the characters in a file, using the
C<wc -c> external command." };

  { defaults with
    name = "head"; added = (1, 0, 54);
    style = RStringList "lines", [Pathname "path"], [];
    proc_nr = Some 121;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["head"; "/10klines"]],
        "is_string_list (ret, 10, \"0abcdefghijklmnopqrstuvwxyz\", \"1abcdefghijklmnopqrstuvwxyz\", \"2abcdefghijklmnopqrstuvwxyz\", \"3abcdefghijklmnopqrstuvwxyz\", \"4abcdefghijklmnopqrstuvwxyz\", \"5abcdefghijklmnopqrstuvwxyz\", \"6abcdefghijklmnopqrstuvwxyz\", \"7abcdefghijklmnopqrstuvwxyz\", \"8abcdefghijklmnopqrstuvwxyz\", \"9abcdefghijklmnopqrstuvwxyz\")"), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestResult (
        [["head"; "/abssymlink"]],
        "is_string_list (ret, 10, \"0abcdefghijklmnopqrstuvwxyz\", \"1abcdefghijklmnopqrstuvwxyz\", \"2abcdefghijklmnopqrstuvwxyz\", \"3abcdefghijklmnopqrstuvwxyz\", \"4abcdefghijklmnopqrstuvwxyz\", \"5abcdefghijklmnopqrstuvwxyz\", \"6abcdefghijklmnopqrstuvwxyz\", \"7abcdefghijklmnopqrstuvwxyz\", \"8abcdefghijklmnopqrstuvwxyz\", \"9abcdefghijklmnopqrstuvwxyz\")"), []
    ];
    shortdesc = "return first 10 lines of a file";
    longdesc = "\
This command returns up to the first 10 lines of a file as
a list of strings." };

  { defaults with
    name = "head_n"; added = (1, 0, 54);
    style = RStringList "lines", [Int "nrlines"; Pathname "path"], [];
    proc_nr = Some 122;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["head_n"; "3"; "/10klines"]],
        "is_string_list (ret, 3, \"0abcdefghijklmnopqrstuvwxyz\", \"1abcdefghijklmnopqrstuvwxyz\", \"2abcdefghijklmnopqrstuvwxyz\")"), [];
      InitISOFS, Always, TestResult (
        [["head_n"; "-9997"; "/10klines"]],
        "is_string_list (ret, 3, \"0abcdefghijklmnopqrstuvwxyz\", \"1abcdefghijklmnopqrstuvwxyz\", \"2abcdefghijklmnopqrstuvwxyz\")"), [];
      InitISOFS, Always, TestResult (
        [["head_n"; "0"; "/10klines"]],
        "is_string_list (ret, 0)"), []
    ];
    shortdesc = "return first N lines of a file";
    longdesc = "\
If the parameter C<nrlines> is a positive number, this returns the first
C<nrlines> lines of the file C<path>.

If the parameter C<nrlines> is a negative number, this returns lines
from the file C<path>, excluding the last C<nrlines> lines.

If the parameter C<nrlines> is zero, this returns an empty list." };

  { defaults with
    name = "tail"; added = (1, 0, 54);
    style = RStringList "lines", [Pathname "path"], [];
    proc_nr = Some 123;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["tail"; "/10klines"]],
        "is_string_list (ret, 10, \"9990abcdefghijklmnopqrstuvwxyz\", \"9991abcdefghijklmnopqrstuvwxyz\", \"9992abcdefghijklmnopqrstuvwxyz\", \"9993abcdefghijklmnopqrstuvwxyz\", \"9994abcdefghijklmnopqrstuvwxyz\", \"9995abcdefghijklmnopqrstuvwxyz\", \"9996abcdefghijklmnopqrstuvwxyz\", \"9997abcdefghijklmnopqrstuvwxyz\", \"9998abcdefghijklmnopqrstuvwxyz\", \"9999abcdefghijklmnopqrstuvwxyz\")"), []
    ];
    shortdesc = "return last 10 lines of a file";
    longdesc = "\
This command returns up to the last 10 lines of a file as
a list of strings." };

  { defaults with
    name = "tail_n"; added = (1, 0, 54);
    style = RStringList "lines", [Int "nrlines"; Pathname "path"], [];
    proc_nr = Some 124;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["tail_n"; "3"; "/10klines"]],
        "is_string_list (ret, 3, \"9997abcdefghijklmnopqrstuvwxyz\", \"9998abcdefghijklmnopqrstuvwxyz\", \"9999abcdefghijklmnopqrstuvwxyz\")"), [];
      InitISOFS, Always, TestResult (
        [["tail_n"; "-9998"; "/10klines"]],
        "is_string_list (ret, 3, \"9997abcdefghijklmnopqrstuvwxyz\", \"9998abcdefghijklmnopqrstuvwxyz\", \"9999abcdefghijklmnopqrstuvwxyz\")"), [];
      InitISOFS, Always, TestResult (
        [["tail_n"; "0"; "/10klines"]],
        "is_string_list (ret, 0)"), []
    ];
    shortdesc = "return last N lines of a file";
    longdesc = "\
If the parameter C<nrlines> is a positive number, this returns the last
C<nrlines> lines of the file C<path>.

If the parameter C<nrlines> is a negative number, this returns lines
from the file C<path>, starting with the C<-nrlines>th line.

If the parameter C<nrlines> is zero, this returns an empty list." };

  { defaults with
    name = "df"; added = (1, 0, 54);
    style = RString "output", [], [];
    proc_nr = Some 125;
    test_excuse = "tricky to test because it depends on the exact format of the 'df' command and other imponderables";
    shortdesc = "report file system disk space usage";
    longdesc = "\
This command runs the C<df> command to report disk space used.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<guestfs_statvfs> from programs." };

  { defaults with
    name = "df_h"; added = (1, 0, 54);
    style = RString "output", [], [];
    proc_nr = Some 126;
    test_excuse = "tricky to test because it depends on the exact format of the 'df' command and other imponderables";
    shortdesc = "report file system disk space usage (human readable)";
    longdesc = "\
This command runs the C<df -h> command to report disk space used
in human-readable format.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.
Use C<guestfs_statvfs> from programs." };

  { defaults with
    name = "du"; added = (1, 0, 54);
    style = RInt64 "sizekb", [Pathname "path"], [];
    proc_nr = Some 127;
    progress = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["du"; "/directory"]], "ret == 2" (* ISO fs blocksize is 2K *)), []
    ];
    shortdesc = "estimate file space usage";
    longdesc = "\
This command runs the C<du -s> command to estimate file space
usage for C<path>.

C<path> can be a file or a directory.  If C<path> is a directory
then the estimate includes the contents of the directory and all
subdirectories (recursively).

The result is the estimated size in I<kilobytes>
(ie. units of 1024 bytes)." };

  { defaults with
    name = "initrd_list"; added = (1, 0, 54);
    style = RStringList "filenames", [Pathname "path"], [];
    proc_nr = Some 128;
    tests = [
      InitISOFS, Always, TestResult (
        [["initrd_list"; "/initrd"]],
        "is_string_list (ret, 6, \"empty\", \"known-1\", \"known-2\", \"known-3\", \"known-4\", \"known-5\")"), []
    ];
    shortdesc = "list files in an initrd";
    longdesc = "\
This command lists out files contained in an initrd.

The files are listed without any initial F</> character.  The
files are listed in the order they appear (not necessarily
alphabetical).  Directory names are listed as separate items.

Old Linux kernels (2.4 and earlier) used a compressed ext2
filesystem as initrd.  We I<only> support the newer initramfs
format (compressed cpio files)." };

  { defaults with
    name = "mount_loop"; added = (1, 0, 54);
    style = RErr, [Pathname "file"; Pathname "mountpoint"], [];
    proc_nr = Some 129;
    shortdesc = "mount a file using the loop device";
    longdesc = "\
This command lets you mount F<file> (a filesystem image
in a file) on a mount point.  It is entirely equivalent to
the command C<mount -o loop file mountpoint>." };

  { defaults with
    name = "mkswap"; added = (1, 0, 55);
    style = RErr, [Device "device"], [OString "label"; OString "uuid"];
    proc_nr = Some 130;
    once_had_no_optargs = true;
    tests = (let uuid = uuidgen () in [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap"; "/dev/sda1"; "NOARG"; "NOARG"]]), [];
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap"; "/dev/sda1"; "hello"; "NOARG"]]), [];
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap"; "/dev/sda1"; "NOARG"; uuid];
         ["vfs_uuid"; "/dev/sda1"]], uuid), [];
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap"; "/dev/sda1"; "hello"; uuid];
         ["vfs_label"; "/dev/sda1"]], "hello"), []
    ]);
    shortdesc = "create a swap partition";
    longdesc = "\
Create a Linux swap partition on C<device>.

The option arguments C<label> and C<uuid> allow you to set the
label and/or UUID of the new swap partition." };

  { defaults with
    name = "mkswap_L"; added = (1, 0, 55);
    style = RErr, [String "label"; Device "device"], [];
    proc_nr = Some 131;
    deprecated_by = Some "mkswap";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap_L"; "hello"; "/dev/sda1"]]), []
    ];
    shortdesc = "create a swap partition with a label";
    longdesc = "\
Create a swap partition on C<device> with label C<label>.

Note that you cannot attach a swap label to a block device
(eg. F</dev/sda>), just to a partition.  This appears to be
a limitation of the kernel or swap tools." };

  { defaults with
    name = "mkswap_U"; added = (1, 0, 55);
    style = RErr, [String "uuid"; Device "device"], [];
    proc_nr = Some 132;
    deprecated_by = Some "mkswap";
    optional = Some "linuxfsuuid";
    tests =
      (let uuid = uuidgen () in [
        InitEmpty, Always, TestRun (
          [["part_disk"; "/dev/sda"; "mbr"];
           ["mkswap_U"; uuid; "/dev/sda1"]]), []
      ]);
    shortdesc = "create a swap partition with an explicit UUID";
    longdesc = "\
Create a swap partition on C<device> with UUID C<uuid>." };

  { defaults with
    name = "mknod"; added = (1, 0, 55);
    style = RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], [];
    proc_nr = Some 133;
    optional = Some "mknod";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mknod"; "0o10777"; "0"; "0"; "/mknod"];
         (* NB: default umask 022 means 0777 -> 0755 in these tests *)
         ["stat"; "/mknod"]],
        "S_ISFIFO (ret->mode) && (ret->mode & 0777) == 0755"), [];
      InitScratchFS, Always, TestResult (
        [["mknod"; "0o60777"; "66"; "99"; "/mknod2"];
         ["stat"; "/mknod2"]],
        "S_ISBLK (ret->mode) && (ret->mode & 0777) == 0755"), []
    ];
    shortdesc = "make block, character or FIFO devices";
    longdesc = "\
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

The mode actually set is affected by the umask." };

  { defaults with
    name = "mkfifo"; added = (1, 0, 55);
    style = RErr, [Int "mode"; Pathname "path"], [];
    proc_nr = Some 134;
    optional = Some "mknod";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkfifo"; "0o777"; "/mkfifo"];
         ["stat"; "/mkfifo"]],
        "S_ISFIFO (ret->mode) && (ret->mode & 0777) == 0755"), [];
      InitScratchFS, Always, TestLastFail (
        [["mkfifo"; "0o20777"; "/mkfifo-2"]]), [];
    ];
    shortdesc = "make FIFO (named pipe)";
    longdesc = "\
This call creates a FIFO (named pipe) called C<path> with
mode C<mode>.  It is just a convenient wrapper around
C<guestfs_mknod>.

Unlike with C<guestfs_mknod>, C<mode> B<must> contain only permissions
bits.

The mode actually set is affected by the umask." };

  { defaults with
    name = "mknod_b"; added = (1, 0, 55);
    style = RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], [];
    proc_nr = Some 135;
    optional = Some "mknod";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mknod_b"; "0o777"; "99"; "66"; "/mknod_b"];
         ["stat"; "/mknod_b"]],
        "S_ISBLK (ret->mode) && (ret->mode & 0777) == 0755"), [];
      InitScratchFS, Always, TestLastFail (
        [["mknod_b"; "0o10777"; "99"; "66"; "/mknod_b-2"]]), [];
    ];
    shortdesc = "make block device node";
    longdesc = "\
This call creates a block device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.

Unlike with C<guestfs_mknod>, C<mode> B<must> contain only permissions
bits.

The mode actually set is affected by the umask." };

  { defaults with
    name = "mknod_c"; added = (1, 0, 55);
    style = RErr, [Int "mode"; Int "devmajor"; Int "devminor"; Pathname "path"], [];
    proc_nr = Some 136;
    optional = Some "mknod";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mknod_c"; "0o777"; "99"; "66"; "/mknod_c"];
         ["stat"; "/mknod_c"]],
        "S_ISCHR (ret->mode) && (ret->mode & 0777) == 0755"), [];
      InitScratchFS, Always, TestLastFail (
        [["mknod_c"; "0o20777"; "99"; "66"; "/mknod_c-2"]]), [];
    ];
    shortdesc = "make char device node";
    longdesc = "\
This call creates a char device node called C<path> with
mode C<mode> and device major/minor C<devmajor> and C<devminor>.
It is just a convenient wrapper around C<guestfs_mknod>.

Unlike with C<guestfs_mknod>, C<mode> B<must> contain only permissions
bits.

The mode actually set is affected by the umask." };

  { defaults with
    name = "umask"; added = (1, 0, 55);
    style = RInt "oldmask", [Int "mask"], [];
    proc_nr = Some 137;
    fish_output = Some FishOutputOctal;
    tests = [
      InitEmpty, Always, TestResult (
        [["umask"; "0o22"]], "ret == 022"), []
    ];
    shortdesc = "set file mode creation mask (umask)";
    longdesc = "\
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

This call returns the previous umask." };

  { defaults with
    name = "readdir"; added = (1, 0, 55);
    style = RStructList ("entries", "dirent"), [Pathname "dir"], [];
    proc_nr = Some 138;
    protocol_limit_warning = true;
    shortdesc = "read directories entries";
    longdesc = "\
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
directory for human consumption, use C<guestfs_ll>." };

  { defaults with
    name = "sfdiskM"; added = (1, 0, 55);
    style = RErr, [Device "device"; StringList "lines"], [];
    proc_nr = Some 139;
    deprecated_by = Some "part_add";
    shortdesc = "create partitions on a block device";
    longdesc = "\
This is a simplified interface to the C<guestfs_sfdisk>
command, where partition sizes are specified in megabytes
only (rounded to the nearest cylinder) and you don't need
to specify the cyls, heads and sectors parameters which
were rarely if ever used anyway.

See also: C<guestfs_sfdisk>, the L<sfdisk(8)> manpage
and C<guestfs_part_disk>" };

  { defaults with
    name = "zfile"; added = (1, 0, 59);
    style = RString "description", [String "meth"; Pathname "path"], [];
    proc_nr = Some 140;
    deprecated_by = Some "file";
    shortdesc = "determine file type inside a compressed file";
    longdesc = "\
This command runs F<file> after first decompressing C<path>
using C<method>.

C<method> must be one of C<gzip>, C<compress> or C<bzip2>.

Since 1.0.63, use C<guestfs_file> instead which can now
process compressed files." };

  { defaults with
    name = "getxattrs"; added = (1, 0, 59);
    style = RStructList ("xattrs", "xattr"), [Pathname "path"], [];
    proc_nr = Some 141;
    optional = Some "linuxxattrs";
    shortdesc = "list extended attributes of a file or directory";
    longdesc = "\
This call lists the extended attributes of the file or directory
C<path>.

At the system call level, this is a combination of the
L<listxattr(2)> and L<getxattr(2)> calls.

See also: C<guestfs_lgetxattrs>, L<attr(5)>." };

  { defaults with
    name = "lgetxattrs"; added = (1, 0, 59);
    style = RStructList ("xattrs", "xattr"), [Pathname "path"], [];
    proc_nr = Some 142;
    optional = Some "linuxxattrs";
    shortdesc = "list extended attributes of a file or directory";
    longdesc = "\
This is the same as C<guestfs_getxattrs>, but if C<path>
is a symbolic link, then it returns the extended attributes
of the link itself." };

  { defaults with
    name = "setxattr"; added = (1, 0, 59);
    style = RErr, [String "xattr";
                   String "val"; Int "vallen"; (* will be BufferIn *)
                   Pathname "path"], [];
    proc_nr = Some 143;
    optional = Some "linuxxattrs";
    shortdesc = "set extended attribute of a file or directory";
    longdesc = "\
This call sets the extended attribute named C<xattr>
of the file C<path> to the value C<val> (of length C<vallen>).
The value is arbitrary 8 bit data.

See also: C<guestfs_lsetxattr>, L<attr(5)>." };

  { defaults with
    name = "lsetxattr"; added = (1, 0, 59);
    style = RErr, [String "xattr";
                   String "val"; Int "vallen"; (* will be BufferIn *)
                   Pathname "path"], [];
    proc_nr = Some 144;
    optional = Some "linuxxattrs";
    shortdesc = "set extended attribute of a file or directory";
    longdesc = "\
This is the same as C<guestfs_setxattr>, but if C<path>
is a symbolic link, then it sets an extended attribute
of the link itself." };

  { defaults with
    name = "removexattr"; added = (1, 0, 59);
    style = RErr, [String "xattr"; Pathname "path"], [];
    proc_nr = Some 145;
    optional = Some "linuxxattrs";
    shortdesc = "remove extended attribute of a file or directory";
    longdesc = "\
This call removes the extended attribute named C<xattr>
of the file C<path>.

See also: C<guestfs_lremovexattr>, L<attr(5)>." };

  { defaults with
    name = "lremovexattr"; added = (1, 0, 59);
    style = RErr, [String "xattr"; Pathname "path"], [];
    proc_nr = Some 146;
    optional = Some "linuxxattrs";
    shortdesc = "remove extended attribute of a file or directory";
    longdesc = "\
This is the same as C<guestfs_removexattr>, but if C<path>
is a symbolic link, then it removes an extended attribute
of the link itself." };

  { defaults with
    name = "mountpoints"; added = (1, 0, 62);
    style = RHashtable "mps", [], [];
    proc_nr = Some 147;
    shortdesc = "show mountpoints";
    longdesc = "\
This call is similar to C<guestfs_mounts>.  That call returns
a list of devices.  This one returns a hash table (map) of
device name to directory where the device is mounted." };

  { defaults with
    name = "mkmountpoint"; added = (1, 0, 62);
    (* This is a special case: while you would expect a parameter
     * of type "Pathname", that doesn't work, because it implies
     * NEED_ROOT in the generated calling code in stubs.c, and
     * this function cannot use NEED_ROOT.
     *)
    style = RErr, [String "exemptpath"], [];
    proc_nr = Some 148;
    shortdesc = "create a mountpoint";
    longdesc = "\
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
is closed which can also trigger these issues." };

  { defaults with
    name = "rmmountpoint"; added = (1, 0, 62);
    style = RErr, [String "exemptpath"], [];
    proc_nr = Some 149;
    shortdesc = "remove a mountpoint";
    longdesc = "\
This calls removes a mountpoint that was previously created
with C<guestfs_mkmountpoint>.  See C<guestfs_mkmountpoint>
for full details." };

  { defaults with
    name = "grep"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [OBool "extended"; OBool "fixed"; OBool "insensitive"; OBool "compressed"];
    proc_nr = Some 151;
    protocol_limit_warning = true; once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; ""; ""; ""; ""]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "nomatch"; "/test-grep.txt"; ""; ""; ""; ""]],
        "is_string_list (ret, 0)"), [];
      (* Test for RHBZ#579608, absolute symbolic links. *)
      InitISOFS, Always, TestResult (
        [["grep"; "nomatch"; "/abssymlink"; ""; ""; ""; ""]],
        "is_string_list (ret, 0)"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; "true"; ""; ""; ""]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; ""; "true"; ""; ""]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; ""; ""; "true"; ""]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; "true"; ""; "true"; ""]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt"; ""; "true"; "true"; ""]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; ""; ""; ""; "true"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; "true"; ""; ""; "true"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; ""; "true"; ""; "true"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; ""; ""; "true"; "true"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; "true"; ""; "true"; "true"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), [];
      InitISOFS, Always, TestResult (
        [["grep"; "abc"; "/test-grep.txt.gz"; ""; "true"; "true"; "true"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<grep> program and returns the
matching lines.

The optional flags are:

=over 4

=item C<extended>

Use extended regular expressions.
This is the same as using the I<-E> flag.

=item C<fixed>

Match fixed (don't use regular expressions).
This is the same as using the I<-F> flag.

=item C<insensitive>

Match case-insensitive.  This is the same as using the I<-i> flag.

=item C<compressed>

Use C<zgrep> instead of C<grep>.  This allows the input to be
compress- or gzip-compressed.

=back" };

  { defaults with
    name = "egrep"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 152;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["egrep"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<egrep> program and returns the
matching lines." };

  { defaults with
    name = "fgrep"; added = (1, 0, 66);
    style = RStringList "lines", [String "pattern"; Pathname "path"], [];
    proc_nr = Some 153;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["fgrep"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<fgrep> program and returns the
matching lines." };

  { defaults with
    name = "grepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 154;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["grepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<grep -i> program and returns the
matching lines." };

  { defaults with
    name = "egrepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 155;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["egrepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<egrep -i> program and returns the
matching lines." };

  { defaults with
    name = "fgrepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "pattern"; Pathname "path"], [];
    proc_nr = Some 156;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["fgrepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<fgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zgrep"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 157;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zgrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zgrep> program and returns the
matching lines." };

  { defaults with
    name = "zegrep"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 158;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zegrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zegrep> program and returns the
matching lines." };

  { defaults with
    name = "zfgrep"; added = (1, 0, 66);
    style = RStringList "lines", [String "pattern"; Pathname "path"], [];
    proc_nr = Some 159;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zfgrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zfgrep> program and returns the
matching lines." };

  { defaults with
    name = "zgrepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 160;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zgrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zegrepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "regex"; Pathname "path"], [];
    proc_nr = Some 161;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zegrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zegrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zfgrepi"; added = (1, 0, 66);
    style = RStringList "lines", [String "pattern"; Pathname "path"], [];
    proc_nr = Some 162;
    protocol_limit_warning = true;
    deprecated_by = Some "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zfgrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zfgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "realpath"; added = (1, 0, 66);
    style = RString "rpath", [Pathname "path"], [];
    proc_nr = Some 163;
    tests = [
      InitISOFS, Always, TestResultString (
        [["realpath"; "/../directory"]], "/directory"), []
    ];
    shortdesc = "canonicalized absolute pathname";
    longdesc = "\
Return the canonicalized absolute pathname of C<path>.  The
returned path has no C<.>, C<..> or symbolic link path elements." };

  { defaults with
    name = "ln"; added = (1, 0, 66);
    style = RErr, [String "target"; Pathname "linkname"], [];
    proc_nr = Some 164;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/ln"];
         ["touch"; "/ln/a"];
         ["ln"; "/ln/a"; "/ln/b"];
         ["stat"; "/ln/b"]], "ret->nlink == 2"), []
    ];
    shortdesc = "create a hard link";
    longdesc = "\
This command creates a hard link using the C<ln> command." };

  { defaults with
    name = "ln_f"; added = (1, 0, 66);
    style = RErr, [String "target"; Pathname "linkname"], [];
    proc_nr = Some 165;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/ln_f"];
         ["touch"; "/ln_f/a"];
         ["touch"; "/ln_f/b"];
         ["ln_f"; "/ln_f/a"; "/ln_f/b"];
         ["stat"; "/ln_f/b"]], "ret->nlink == 2"), []
    ];
    shortdesc = "create a hard link";
    longdesc = "\
This command creates a hard link using the C<ln -f> command.
The I<-f> option removes the link (C<linkname>) if it exists already." };

  { defaults with
    name = "ln_s"; added = (1, 0, 66);
    style = RErr, [String "target"; Pathname "linkname"], [];
    proc_nr = Some 166;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/ln_s"];
         ["touch"; "/ln_s/a"];
         ["ln_s"; "a"; "/ln_s/b"];
         ["lstat"; "/ln_s/b"]],
        "S_ISLNK (ret->mode) && (ret->mode & 0777) == 0777"), []
    ];
    shortdesc = "create a symbolic link";
    longdesc = "\
This command creates a symbolic link using the C<ln -s> command." };

  { defaults with
    name = "ln_sf"; added = (1, 0, 66);
    style = RErr, [String "target"; Pathname "linkname"], [];
    proc_nr = Some 167;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir_p"; "/ln_sf/b"];
         ["touch"; "/ln_sf/b/c"];
         ["ln_sf"; "../d"; "/ln_sf/b/c"];
         ["readlink"; "/ln_sf/b/c"]], "../d"), []
    ];
    shortdesc = "create a symbolic link";
    longdesc = "\
This command creates a symbolic link using the C<ln -sf> command,
The I<-f> option removes the link (C<linkname>) if it exists already." };

  { defaults with
    name = "readlink"; added = (1, 0, 66);
    style = RString "link", [Pathname "path"], [];
    proc_nr = Some 168;
    shortdesc = "read the target of a symbolic link";
    longdesc = "\
This command reads the target of a symbolic link." };

  { defaults with
    name = "fallocate"; added = (1, 0, 66);
    style = RErr, [Pathname "path"; Int "len"], [];
    proc_nr = Some 169;
    deprecated_by = Some "fallocate64";
    tests = [
      InitScratchFS, Always, TestResult (
        [["fallocate"; "/fallocate"; "1000000"];
         ["stat"; "/fallocate"]], "ret->size == 1000000"), []
    ];
    shortdesc = "preallocate a file in the guest filesystem";
    longdesc = "\
This command preallocates a file (containing zero bytes) named
C<path> of size C<len> bytes.  If the file exists already, it
is overwritten.

Do not confuse this with the guestfish-specific
C<alloc> command which allocates a file in the host and
attaches it as a device." };

  { defaults with
    name = "swapon_device"; added = (1, 0, 66);
    style = RErr, [Device "device"], [];
    proc_nr = Some 170;
    tests = [
      InitPartition, Always, TestRun (
        [["mkswap"; "/dev/sda1"; "NOARG"; "NOARG"];
         ["swapon_device"; "/dev/sda1"];
         ["swapoff_device"; "/dev/sda1"]]), []
    ];
    shortdesc = "enable swap on device";
    longdesc = "\
This command enables the libguestfs appliance to use the
swap device or partition named C<device>.  The increased
memory is made available for all commands, for example
those run using C<guestfs_command> or C<guestfs_sh>.

Note that you should not swap to existing guest swap
partitions unless you know what you are doing.  They may
contain hibernation information, or other information that
the guest doesn't want you to trash.  You also risk leaking
information about the host to the guest this way.  Instead,
attach a new host device to the guest and swap on that." };

  { defaults with
    name = "swapoff_device"; added = (1, 0, 66);
    style = RErr, [Device "device"], [];
    proc_nr = Some 171;
    shortdesc = "disable swap on device";
    longdesc = "\
This command disables the libguestfs appliance swap
device or partition named C<device>.
See C<guestfs_swapon_device>." };

  { defaults with
    name = "swapon_file"; added = (1, 0, 66);
    style = RErr, [Pathname "file"], [];
    proc_nr = Some 172;
    tests = [
      InitScratchFS, Always, TestRun (
        [["fallocate"; "/swapon_file"; "8388608"];
         ["mkswap_file"; "/swapon_file"];
         ["swapon_file"; "/swapon_file"];
         ["swapoff_file"; "/swapon_file"];
         ["rm"; "/swapon_file"]]), []
    ];
    shortdesc = "enable swap on file";
    longdesc = "\
This command enables swap to a file.
See C<guestfs_swapon_device> for other notes." };

  { defaults with
    name = "swapoff_file"; added = (1, 0, 66);
    style = RErr, [Pathname "file"], [];
    proc_nr = Some 173;
    shortdesc = "disable swap on file";
    longdesc = "\
This command disables the libguestfs appliance swap on file." };

  { defaults with
    name = "swapon_label"; added = (1, 0, 66);
    style = RErr, [String "label"], [];
    proc_nr = Some 174;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap"; "/dev/sda1"; "swapit"; "NOARG"];
         ["swapon_label"; "swapit"];
         ["swapoff_label"; "swapit"];
         ["zero"; "/dev/sda"];
         ["blockdev_rereadpt"; "/dev/sda"]]), []
    ];
    shortdesc = "enable swap on labeled swap partition";
    longdesc = "\
This command enables swap to a labeled swap partition.
See C<guestfs_swapon_device> for other notes." };

  { defaults with
    name = "swapoff_label"; added = (1, 0, 66);
    style = RErr, [String "label"], [];
    proc_nr = Some 175;
    shortdesc = "disable swap on labeled swap partition";
    longdesc = "\
This command disables the libguestfs appliance swap on
labeled swap partition." };

  { defaults with
    name = "swapon_uuid"; added = (1, 0, 66);
    style = RErr, [String "uuid"], [];
    proc_nr = Some 176;
    optional = Some "linuxfsuuid";
    tests =
      (let uuid = uuidgen () in [
        InitEmpty, Always, TestRun (
          [["mkswap"; "/dev/sdc"; "NOARG"; uuid];
           ["swapon_uuid"; uuid];
           ["swapoff_uuid"; uuid]]), []
      ]);
    shortdesc = "enable swap on swap partition by UUID";
    longdesc = "\
This command enables swap to a swap partition with the given UUID.
See C<guestfs_swapon_device> for other notes." };

  { defaults with
    name = "swapoff_uuid"; added = (1, 0, 66);
    style = RErr, [String "uuid"], [];
    proc_nr = Some 177;
    optional = Some "linuxfsuuid";
    shortdesc = "disable swap on swap partition by UUID";
    longdesc = "\
This command disables the libguestfs appliance swap partition
with the given UUID." };

  { defaults with
    name = "mkswap_file"; added = (1, 0, 66);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 178;
    tests = [
      InitScratchFS, Always, TestRun (
        [["fallocate"; "/mkswap_file"; "8388608"];
         ["mkswap_file"; "/mkswap_file"];
         ["rm"; "/mkswap_file"]]), []
    ];
    shortdesc = "create a swap file";
    longdesc = "\
Create a swap file.

This command just writes a swap file signature to an existing
file.  To create the file itself, use something like C<guestfs_fallocate>." };

  { defaults with
    name = "inotify_init"; added = (1, 0, 66);
    style = RErr, [Int "maxevents"], [];
    proc_nr = Some 179;
    optional = Some "inotify";
    tests = [
      InitISOFS, Always, TestRun (
        [["inotify_init"; "0"]]), []
    ];
    shortdesc = "create an inotify handle";
    longdesc = "\
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
watches to the internal watch list.  See: C<guestfs_inotify_add_watch> and
C<guestfs_inotify_rm_watch>.

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
per libguestfs instance." };

  { defaults with
    name = "inotify_add_watch"; added = (1, 0, 66);
    style = RInt64 "wd", [Pathname "path"; Int "mask"], [];
    proc_nr = Some 180;
    optional = Some "inotify";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/inotify_add_watch"];
         ["inotify_init"; "0"];
         ["inotify_add_watch"; "/inotify_add_watch"; "4095"];
         ["touch"; "/inotify_add_watch/a"];
         ["touch"; "/inotify_add_watch/b"];
         ["inotify_files"]],
        "is_string_list (ret, 2, \"a\", \"b\")"), []
    ];
    shortdesc = "add an inotify watch";
    longdesc = "\
Watch C<path> for the events listed in C<mask>.

Note that if C<path> is a directory then events within that
directory are watched, but this does I<not> happen recursively
(in subdirectories).

Note for non-C or non-Linux callers: the inotify events are
defined by the Linux kernel ABI and are listed in
F</usr/include/sys/inotify.h>." };

  { defaults with
    name = "inotify_rm_watch"; added = (1, 0, 66);
    style = RErr, [Int(*XXX64*) "wd"], [];
    proc_nr = Some 181;
    optional = Some "inotify";
    shortdesc = "remove an inotify watch";
    longdesc = "\
Remove a previously defined inotify watch.
See C<guestfs_inotify_add_watch>." };

  { defaults with
    name = "inotify_read"; added = (1, 0, 66);
    style = RStructList ("events", "inotify_event"), [], [];
    proc_nr = Some 182;
    optional = Some "inotify";
    shortdesc = "return list of inotify events";
    longdesc = "\
Return the complete queue of events that have happened
since the previous read call.

If no events have happened, this returns an empty list.

I<Note>: In order to make sure that all events have been
read, you must call this function repeatedly until it
returns an empty list.  The reason is that the call will
read events up to the maximum appliance-to-host message
size and leave remaining events in the queue." };

  { defaults with
    name = "inotify_files"; added = (1, 0, 66);
    style = RStringList "paths", [], [];
    proc_nr = Some 183;
    optional = Some "inotify";
    shortdesc = "return list of watched files that had events";
    longdesc = "\
This function is a helpful wrapper around C<guestfs_inotify_read>
which just returns a list of pathnames of objects that were
touched.  The returned pathnames are sorted and deduplicated." };

  { defaults with
    name = "inotify_close"; added = (1, 0, 66);
    style = RErr, [], [];
    proc_nr = Some 184;
    optional = Some "inotify";
    shortdesc = "close the inotify handle";
    longdesc = "\
This closes the inotify handle which was previously
opened by inotify_init.  It removes all watches, throws
away any pending events, and deallocates all resources." };

  { defaults with
    name = "setcon"; added = (1, 0, 67);
    style = RErr, [String "context"], [];
    proc_nr = Some 185;
    optional = Some "selinux";
    shortdesc = "set SELinux security context";
    longdesc = "\
This sets the SELinux security context of the daemon
to the string C<context>.

See the documentation about SELINUX in L<guestfs(3)>." };

  { defaults with
    name = "getcon"; added = (1, 0, 67);
    style = RString "context", [], [];
    proc_nr = Some 186;
    optional = Some "selinux";
    shortdesc = "get SELinux security context";
    longdesc = "\
This gets the SELinux security context of the daemon.

See the documentation about SELINUX in L<guestfs(3)>,
and C<guestfs_setcon>" };

  { defaults with
    name = "mkfs_b"; added = (1, 0, 68);
    style = RErr, [String "fstype"; Int "blocksize"; Device "device"], [];
    proc_nr = Some 187;
    deprecated_by = Some "mkfs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs_b"; "ext2"; "4096"; "/dev/sda1"];
         ["mount"; "/dev/sda1"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), [];
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "32768"; "/dev/sda1"]]), [];
      InitEmpty, Always, TestLastFail (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "32769"; "/dev/sda1"]]), [];
      InitEmpty, Always, TestLastFail (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "33280"; "/dev/sda1"]]), [];
      InitEmpty, IfAvailable "ntfsprogs", TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs_b"; "ntfs"; "32768"; "/dev/sda1"]]), []
    ];
    shortdesc = "make a filesystem with block size";
    longdesc = "\
This call is similar to C<guestfs_mkfs>, but it allows you to
control the block size of the resulting filesystem.  Supported
block sizes depend on the filesystem type, but typically they
are C<1024>, C<2048> or C<4096> only.

For VFAT and NTFS the C<blocksize> parameter is treated as
the requested cluster size." };

  { defaults with
    name = "mke2journal"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; Device "device"], [];
    proc_nr = Some 188;
    deprecated_by = Some "mke2fs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
         ["mke2journal"; "4096"; "/dev/sda1"];
         ["mke2fs_J"; "ext2"; "4096"; "/dev/sda2"; "/dev/sda1"];
         ["mount"; "/dev/sda2"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "make ext2/3/4 external journal";
    longdesc = "\
This creates an ext2 external journal on C<device>.  It is equivalent
to the command:

 mke2fs -O journal_dev -b blocksize device" };

  { defaults with
    name = "mke2journal_L"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; String "label"; Device "device"], [];
    proc_nr = Some 189;
    deprecated_by = Some "mke2fs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
         ["mke2journal_L"; "4096"; "JOURNAL"; "/dev/sda1"];
         ["mke2fs_JL"; "ext2"; "4096"; "/dev/sda2"; "JOURNAL"];
         ["mount"; "/dev/sda2"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "make ext2/3/4 external journal with label";
    longdesc = "\
This creates an ext2 external journal on C<device> with label C<label>." };

  { defaults with
    name = "mke2journal_U"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; String "uuid"; Device "device"], [];
    proc_nr = Some 190;
    deprecated_by = Some "mke2fs";
    optional = Some "linuxfsuuid";
    tests =
      (let uuid = uuidgen () in [
        InitEmpty, Always, TestResultString (
          [["part_init"; "/dev/sda"; "mbr"];
           ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
           ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
           ["mke2journal_U"; "4096"; uuid; "/dev/sda1"];
           ["mke2fs_JU"; "ext2"; "4096"; "/dev/sda2"; uuid];
           ["mount"; "/dev/sda2"; "/"];
           ["write"; "/new"; "new file contents"];
           ["cat"; "/new"]], "new file contents"), []
      ]);
    shortdesc = "make ext2/3/4 external journal with UUID";
    longdesc = "\
This creates an ext2 external journal on C<device> with UUID C<uuid>." };

  { defaults with
    name = "mke2fs_J"; added = (1, 0, 68);
    style = RErr, [String "fstype"; Int "blocksize"; Device "device"; Device "journal"], [];
    proc_nr = Some 191;
    deprecated_by = Some "mke2fs";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on C<journal>.  It is equivalent
to the command:

 mke2fs -t fstype -b blocksize -J device=<journal> <device>

See also C<guestfs_mke2journal>." };

  { defaults with
    name = "mke2fs_JL"; added = (1, 0, 68);
    style = RErr, [String "fstype"; Int "blocksize"; Device "device"; String "label"], [];
    proc_nr = Some 192;
    deprecated_by = Some "mke2fs";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal labeled C<label>.

See also C<guestfs_mke2journal_L>." };

  { defaults with
    name = "mke2fs_JU"; added = (1, 0, 68);
    style = RErr, [String "fstype"; Int "blocksize"; Device "device"; String "uuid"], [];
    proc_nr = Some 193;
    deprecated_by = Some "mke2fs";
    optional = Some "linuxfsuuid";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal with UUID C<uuid>.

See also C<guestfs_mke2journal_U>." };

  { defaults with
    name = "modprobe"; added = (1, 0, 68);
    style = RErr, [String "modulename"], [];
    proc_nr = Some 194;
    optional = Some "linuxmodules";
    tests = [
      InitNone, Always, TestRun [["modprobe"; "fat"]], []
    ];
    shortdesc = "load a kernel module";
    longdesc = "\
This loads a kernel module in the appliance." };

  { defaults with
    name = "echo_daemon"; added = (1, 0, 69);
    style = RString "output", [StringList "words"], [];
    proc_nr = Some 195;
    tests = [
      InitNone, Always, TestResultString (
        [["echo_daemon"; "This is a test"]], "This is a test"), [];
      InitNone, Always, TestResultString (
        [["echo_daemon"; ""]], ""), [];
    ];
    shortdesc = "echo arguments back to the client";
    longdesc = "\
This command concatenates the list of C<words> passed with single spaces
between them and returns the resulting string.

You can use this command to test the connection through to the daemon.

See also C<guestfs_ping_daemon>." };

  { defaults with
    name = "find0"; added = (1, 0, 74);
    style = RErr, [Pathname "directory"; FileOut "files"], [];
    proc_nr = Some 196;
    cancellable = true;
    test_excuse = "there is a regression test for this";
    shortdesc = "find all files and directories, returning NUL-separated list";
    longdesc = "\
This command lists out all files and directories, recursively,
starting at F<directory>, placing the resulting list in the
external file called F<files>.

This command works the same way as C<guestfs_find> with the
following exceptions:

=over 4

=item *

The resulting list is written to an external file.

=item *

Items (filenames) in the result are separated
by C<\\0> characters.  See L<find(1)> option I<-print0>.

=item *

The result list is not sorted.

=back" };

  { defaults with
    name = "case_sensitive_path"; added = (1, 0, 75);
    style = RString "rpath", [Pathname "path"], [];
    proc_nr = Some 197;
    tests = [
      InitISOFS, Always, TestResultString (
        [["case_sensitive_path"; "/DIRECTORY"]], "/directory"), [];
      InitISOFS, Always, TestResultString (
        [["case_sensitive_path"; "/DIRECTORY/"]], "/directory"), [];
      InitISOFS, Always, TestResultString (
        [["case_sensitive_path"; "/Known-1"]], "/known-1"), [];
      InitISOFS, Always, TestLastFail (
        [["case_sensitive_path"; "/Known-1/"]]), [];
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/case_sensitive_path"];
         ["mkdir"; "/case_sensitive_path/bbb"];
         ["touch"; "/case_sensitive_path/bbb/c"];
         ["case_sensitive_path"; "/CASE_SENSITIVE_path/bbB/C"]], "/case_sensitive_path/bbb/c"), [];
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/case_sensitive_path2"];
         ["mkdir"; "/case_sensitive_path2/bbb"];
         ["touch"; "/case_sensitive_path2/bbb/c"];
         ["case_sensitive_path"; "/case_sensitive_PATH2////bbB/C"]], "/case_sensitive_path2/bbb/c"), [];
      InitScratchFS, Always, TestLastFail (
        [["mkdir"; "/case_sensitive_path3"];
         ["mkdir"; "/case_sensitive_path3/bbb"];
         ["touch"; "/case_sensitive_path3/bbb/c"];
         ["case_sensitive_path"; "/case_SENSITIVE_path3/bbb/../bbb/C"]]), [];
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/case_sensitive_path4"];
         ["case_sensitive_path"; "/case_SENSITIVE_path4/new_file"]], "/case_sensitive_path4/new_file"), []
    ];
    shortdesc = "return true path on case-insensitive filesystem";
    longdesc = "\
This can be used to resolve case insensitive paths on
a filesystem which is case sensitive.  The use case is
to resolve paths which you have read from Windows configuration
files or the Windows Registry, to the true path.

The command handles a peculiarity of the Linux ntfs-3g
filesystem driver (and probably others), which is that although
the underlying filesystem is case-insensitive, the driver
exports the filesystem to Linux as case-sensitive.

One consequence of this is that special directories such
as F<C:\\windows> may appear as F</WINDOWS> or F</windows>
(or other things) depending on the precise details of how
they were created.  In Windows itself this would not be
a problem.

Bug or feature?  You decide:
L<http://www.tuxera.com/community/ntfs-3g-faq/#posixfilenames1>

C<guestfs_case_sensitive_path> attempts to resolve the true case of
each element in the path. It will return a resolved path if either the
full path or its parent directory exists. If the parent directory
exists but the full path does not, the case of the parent directory
will be correctly resolved, and the remainder appended unmodified. For
example, if the file C<\"/Windows/System32/netkvm.sys\"> exists:

=over 4

=item C<guestfs_case_sensitive_path> (\"/windows/system32/netkvm.sys\")

\"Windows/System32/netkvm.sys\"

=item C<guestfs_case_sensitive_path> (\"/windows/system32/NoSuchFile\")

\"Windows/System32/NoSuchFile\"

=item C<guestfs_case_sensitive_path> (\"/windows/system33/netkvm.sys\")

I<ERROR>

=back

I<Note>:
Because of the above behaviour, C<guestfs_case_sensitive_path> cannot
be used to check for the existence of a file.

I<Note>:
This function does not handle drive names, backslashes etc.

See also C<guestfs_realpath>." };

  { defaults with
    name = "vfs_type"; added = (1, 0, 75);
    style = RString "fstype", [Mountable "mountable"], [];
    proc_nr = Some 198;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["vfs_type"; "/dev/sdb1"]], "ext2"), []
    ];
    shortdesc = "get the Linux VFS type corresponding to a mounted device";
    longdesc = "\
This command gets the filesystem type corresponding to
the filesystem on C<mountable>.

For most filesystems, the result is the name of the Linux
VFS module which would be used to mount this filesystem
if you mounted it without specifying the filesystem type.
For example a string such as C<ext3> or C<ntfs>." };

  { defaults with
    name = "truncate"; added = (1, 0, 77);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 199;
    tests = [
      InitScratchFS, Always, TestResult (
        [["write"; "/truncate"; "some stuff so size is not zero"];
         ["truncate"; "/truncate"];
         ["stat"; "/truncate"]], "ret->size == 0"), []
    ];
    shortdesc = "truncate a file to zero size";
    longdesc = "\
This command truncates C<path> to a zero-length file.  The
file must exist already." };

  { defaults with
    name = "truncate_size"; added = (1, 0, 77);
    style = RErr, [Pathname "path"; Int64 "size"], [];
    proc_nr = Some 200;
    tests = [
      InitScratchFS, Always, TestResult (
        [["touch"; "/truncate_size"];
         ["truncate_size"; "/truncate_size"; "1000"];
         ["stat"; "/truncate_size"]], "ret->size == 1000"), []
    ];
    shortdesc = "truncate a file to a particular size";
    longdesc = "\
This command truncates C<path> to size C<size> bytes.  The file
must exist already.

If the current file size is less than C<size> then
the file is extended to the required size with zero bytes.
This creates a sparse file (ie. disk blocks are not allocated
for the file until you write to it).  To create a non-sparse
file of zeroes, use C<guestfs_fallocate64> instead." };

  { defaults with
    name = "utimens"; added = (1, 0, 77);
    style = RErr, [Pathname "path"; Int64 "atsecs"; Int64 "atnsecs"; Int64 "mtsecs"; Int64 "mtnsecs"], [];
    proc_nr = Some 201;
    (* Test directories, named pipes etc (RHBZ#761451, RHBZ#761460) *)
    tests = [
      InitScratchFS, Always, TestResult (
        [["touch"; "/utimens-file"];
         ["utimens"; "/utimens-file"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-file"]], "ret->mtime == 9876"), [];
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/utimens-dir"];
         ["utimens"; "/utimens-dir"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-dir"]], "ret->mtime == 9876"), [];
      InitScratchFS, Always, TestResult (
        [["mkfifo"; "0o644"; "/utimens-fifo"];
         ["utimens"; "/utimens-fifo"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-fifo"]], "ret->mtime == 9876"), [];
      InitScratchFS, Always, TestResult (
        [["ln_sf"; "/utimens-file"; "/utimens-link"];
         ["utimens"; "/utimens-link"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-link"]], "ret->mtime == 9876"), [];
      InitScratchFS, Always, TestResult (
        [["mknod_b"; "0o644"; "8"; "0"; "/utimens-block"];
         ["utimens"; "/utimens-block"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-block"]], "ret->mtime == 9876"), [];
      InitScratchFS, Always, TestResult (
        [["mknod_c"; "0o644"; "1"; "3"; "/utimens-char"];
         ["utimens"; "/utimens-char"; "12345"; "67890"; "9876"; "5432"];
         ["stat"; "/utimens-char"]], "ret->mtime == 9876"), []
    ];
    shortdesc = "set timestamp of a file with nanosecond precision";
    longdesc = "\
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
C<*secs> field is ignored in this case)." };

  { defaults with
    name = "mkdir_mode"; added = (1, 0, 77);
    style = RErr, [Pathname "path"; Int "mode"], [];
    proc_nr = Some 202;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir_mode"; "/mkdir_mode"; "0o111"];
         ["stat"; "/mkdir_mode"]],
        "S_ISDIR (ret->mode) && (ret->mode & 0777) == 0111"), []
    ];
    shortdesc = "create a directory with a particular mode";
    longdesc = "\
This command creates a directory, setting the initial permissions
of the directory to C<mode>.

For common Linux filesystems, the actual mode which is set will
be C<mode & ~umask & 01777>.  Non-native-Linux filesystems may
interpret the mode in other ways.

See also C<guestfs_mkdir>, C<guestfs_umask>" };

  { defaults with
    name = "lchown"; added = (1, 0, 77);
    style = RErr, [Int "owner"; Int "group"; Pathname "path"], [];
    proc_nr = Some 203;
    shortdesc = "change file owner and group";
    longdesc = "\
Change the file owner to C<owner> and group to C<group>.
This is like C<guestfs_chown> but if C<path> is a symlink then
the link itself is changed, not the target.

Only numeric uid and gid are supported.  If you want to use
names, you will need to locate and parse the password file
yourself (Augeas support makes this relatively easy)." };

  { defaults with
    name = "internal_lxattrlist"; added = (1, 19, 32);
    style = RStructList ("xattrs", "xattr"), [Pathname "path"; FilenameList "names"], [];
    proc_nr = Some 205;
    visibility = VInternal;
    optional = Some "linuxxattrs";
    shortdesc = "lgetxattr on multiple files";
    longdesc = "\
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
into smaller groups of names." };

  { defaults with
    name = "internal_readlinklist"; added = (1, 19, 32);
    style = RStringList "links", [Pathname "path"; FilenameList "names"], [];
    proc_nr = Some 206;
    visibility = VInternal;
    shortdesc = "readlink on multiple files";
    longdesc = "\
This call allows you to do a C<readlink> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of strings, with a one-to-one
correspondence to the C<names> list.  Each string is the
value of the symbolic link.

If the L<readlink(2)> operation fails on any name, then
the corresponding result string is the empty string C<\"\">.
However the whole operation is completed even if there
were L<readlink(2)> errors, and so you can call this
function with names where you don't know if they are
symbolic links already (albeit slightly less efficient).

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
Very long directory listings might cause the protocol
message size to be exceeded, causing
this call to fail.  The caller must split up such requests
into smaller groups of names." };

  { defaults with
    name = "pread"; added = (1, 0, 77);
    style = RBufferOut "content", [Pathname "path"; Int "count"; Int64 "offset"], [];
    proc_nr = Some 207;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["pread"; "/known-4"; "1"; "3"]],
        "compare_buffers (ret, size, \"\\n\", 1) == 0"), [];
      InitISOFS, Always, TestResult (
        [["pread"; "/empty"; "0"; "100"]],
        "compare_buffers (ret, size, NULL, 0) == 0"), []
    ];
    shortdesc = "read part of a file";
    longdesc = "\
This command lets you read part of a file.  It reads C<count>
bytes of the file, starting at C<offset>, from file C<path>.

This may read fewer bytes than requested.  For further details
see the L<pread(2)> system call.

See also C<guestfs_pwrite>, C<guestfs_pread_device>." };

  { defaults with
    name = "part_init"; added = (1, 0, 78);
    style = RErr, [Device "device"; String "parttype"], [];
    proc_nr = Some 208;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "gpt"]]), []
    ];
    shortdesc = "create an empty partition table";
    longdesc = "\
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

=back" };

  { defaults with
    name = "part_add"; added = (1, 0, 78);
    style = RErr, [Device "device"; String "prlogex"; Int64 "startsect"; Int64 "endsect"], [];
    proc_nr = Some 209;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "primary"; "1"; "-1"]]), [];
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "gpt"];
         ["part_add"; "/dev/sda"; "primary"; "34"; "127"];
         ["part_add"; "/dev/sda"; "primary"; "128"; "-34"]]), [];
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "primary"; "32"; "127"];
         ["part_add"; "/dev/sda"; "primary"; "128"; "255"];
         ["part_add"; "/dev/sda"; "primary"; "256"; "511"];
         ["part_add"; "/dev/sda"; "primary"; "512"; "-1"]]), []
    ];
    shortdesc = "add a partition to the device";
    longdesc = "\
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
Use C<guestfs_part_disk> to do that." };

  { defaults with
    name = "part_disk"; added = (1, 0, 78);
    style = RErr, [Device "device"; String "parttype"], [];
    proc_nr = Some 210;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"]]), [];
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "gpt"]]), []
    ];
    shortdesc = "partition whole disk with a single primary partition";
    longdesc = "\
This command is simply a combination of C<guestfs_part_init>
followed by C<guestfs_part_add> to create a single primary partition
covering the whole disk.

C<parttype> is the partition table type, usually C<mbr> or C<gpt>,
but other possible values are described in C<guestfs_part_init>." };

  { defaults with
    name = "part_set_bootable"; added = (1, 0, 78);
    style = RErr, [Device "device"; Int "partnum"; Bool "bootable"], [];
    proc_nr = Some 211;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["part_set_bootable"; "/dev/sda"; "1"; "true"]]), []
    ];
    shortdesc = "make a partition bootable";
    longdesc = "\
This sets the bootable flag on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The bootable flag is used by some operating systems (notably
Windows) to determine which partition to boot from.  It is by
no means universally recognized." };

  { defaults with
    name = "part_set_name"; added = (1, 0, 78);
    style = RErr, [Device "device"; Int "partnum"; String "name"], [];
    proc_nr = Some 212;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "gpt"];
         ["part_set_name"; "/dev/sda"; "1"; "thepartname"]]), []
    ];
    shortdesc = "set partition name";
    longdesc = "\
This sets the partition name on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The partition name can only be set on certain types of partition
table.  This works on C<gpt> but not on C<mbr> partitions." };

  { defaults with
    name = "part_list"; added = (1, 0, 78);
    style = RStructList ("partitions", "partition"), [Device "device"], [];
    proc_nr = Some 213;
    tests = [] (* XXX Add a regression test for this. *);
    shortdesc = "list partitions on a device";
    longdesc = "\
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

=back" };

  { defaults with
    name = "part_get_parttype"; added = (1, 0, 78);
    style = RString "parttype", [Device "device"], [];
    proc_nr = Some 214;
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "gpt"];
         ["part_get_parttype"; "/dev/sda"]], "gpt"), []
    ];
    shortdesc = "get the partition table type";
    longdesc = "\
This command examines the partition table on C<device> and
returns the partition table type (format) being used.

Common return values include: C<msdos> (a DOS/Windows style MBR
partition table), C<gpt> (a GPT/EFI-style partition table).  Other
values are possible, although unusual.  See C<guestfs_part_init>
for a full list." };

  { defaults with
    name = "fill"; added = (1, 0, 79);
    style = RErr, [Int "c"; Int "len"; Pathname "path"], [];
    proc_nr = Some 215;
    progress = true;
    tests = [
      InitScratchFS, Always, TestResult (
        [["fill"; "0x63"; "10"; "/fill"];
         ["read_file"; "/fill"]],
        "compare_buffers (ret, size, \"cccccccccc\", 10) == 0"), []
    ];
    shortdesc = "fill a file with octets";
    longdesc = "\
This command creates a new file called C<path>.  The initial
content of the file is C<len> octets of C<c>, where C<c>
must be a number in the range C<[0..255]>.

To fill a file with zero bytes (sparsely), it is
much more efficient to use C<guestfs_truncate_size>.
To create a file with a pattern of repeating bytes
use C<guestfs_fill_pattern>." };

  { defaults with
    name = "dd"; added = (1, 0, 80);
    style = RErr, [Dev_or_Path "src"; Dev_or_Path "dest"], [];
    proc_nr = Some 217;
    deprecated_by = Some "copy_device_to_device";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/dd"];
         ["write"; "/dd/src"; "hello, world"];
         ["dd"; "/dd/src"; "/dd/dest"];
         ["read_file"; "/dd/dest"]],
        "compare_buffers (ret, size, \"hello, world\", 12) == 0"), []
    ];
    shortdesc = "copy from source to destination using dd";
    longdesc = "\
This command copies from one source device or file C<src>
to another destination device or file C<dest>.  Normally you
would use this to copy to or from a device or partition, for
example to duplicate a filesystem.

If the destination is a device, it must be as large or larger
than the source file or device, otherwise the copy will fail.
This command cannot do partial copies
(see C<guestfs_copy_device_to_device>)." };

  { defaults with
    name = "filesize"; added = (1, 0, 82);
    style = RInt64 "size", [Pathname "file"], [];
    proc_nr = Some 218;
    tests = [
      InitScratchFS, Always, TestResult (
        [["write"; "/filesize"; "hello, world"];
         ["filesize"; "/filesize"]], "ret == 12"), []
    ];
    shortdesc = "return the size of the file in bytes";
    longdesc = "\
This command returns the size of F<file> in bytes.

To get other stats about a file, use C<guestfs_stat>, C<guestfs_lstat>,
C<guestfs_is_dir>, C<guestfs_is_file> etc.
To get the size of block devices, use C<guestfs_blockdev_getsize64>." };

  { defaults with
    name = "lvrename"; added = (1, 0, 83);
    style = RErr, [String "logvol"; String "newlogvol"], [];
    proc_nr = Some 219;
    tests = [
      InitBasicFSonLVM, Always, TestResult (
        [["lvrename"; "/dev/VG/LV"; "/dev/VG/LV2"];
         ["lvs"]],
        "is_string_list (ret, 1, \"/dev/VG/LV2\")"), []
    ];
    shortdesc = "rename an LVM logical volume";
    longdesc = "\
Rename a logical volume C<logvol> with the new name C<newlogvol>." };

  { defaults with
    name = "vgrename"; added = (1, 0, 83);
    style = RErr, [String "volgroup"; String "newvolgroup"], [];
    proc_nr = Some 220;
    tests = [
      InitBasicFSonLVM, Always, TestResult (
        [["umount"; "/"; "false"; "false"];
         ["vg_activate"; "false"; "VG"];
         ["vgrename"; "VG"; "VG2"];
         ["vg_activate"; "true"; "VG2"];
         ["mount"; "/dev/VG2/LV"; "/"];
         ["vgs"]],
        "is_string_list (ret, 1, \"VG2\")"), []
    ];
    shortdesc = "rename an LVM volume group";
    longdesc = "\
Rename a volume group C<volgroup> with the new name C<newvolgroup>." };

  { defaults with
    name = "initrd_cat"; added = (1, 0, 84);
    style = RBufferOut "content", [Pathname "initrdpath"; String "filename"], [];
    proc_nr = Some 221;
    protocol_limit_warning = true;
    tests = [
      InitISOFS, Always, TestResult (
        [["initrd_cat"; "/initrd"; "known-4"]],
        "compare_buffers (ret, size, \"abc\\ndef\\nghi\", 11) == 0"), []
    ];
    shortdesc = "list the contents of a single file in an initrd";
    longdesc = "\
This command unpacks the file F<filename> from the initrd file
called F<initrdpath>.  The filename must be given I<without> the
initial F</> character.

For example, in guestfish you could use the following command
to examine the boot script (usually called F</init>)
contained in a Linux initrd or initramfs image:

 initrd-cat /boot/initrd-<version>.img init

See also C<guestfs_initrd_list>." };

  { defaults with
    name = "pvuuid"; added = (1, 0, 87);
    style = RString "uuid", [Device "device"], [];
    proc_nr = Some 222;
    shortdesc = "get the UUID of a physical volume";
    longdesc = "\
This command returns the UUID of the LVM PV C<device>." };

  { defaults with
    name = "vguuid"; added = (1, 0, 87);
    style = RString "uuid", [String "vgname"], [];
    proc_nr = Some 223;
    shortdesc = "get the UUID of a volume group";
    longdesc = "\
This command returns the UUID of the LVM VG named C<vgname>." };

  { defaults with
    name = "lvuuid"; added = (1, 0, 87);
    style = RString "uuid", [Device "device"], [];
    proc_nr = Some 224;
    shortdesc = "get the UUID of a logical volume";
    longdesc = "\
This command returns the UUID of the LVM LV C<device>." };

  { defaults with
    name = "vgpvuuids"; added = (1, 0, 87);
    style = RStringList "uuids", [String "vgname"], [];
    proc_nr = Some 225;
    shortdesc = "get the PV UUIDs containing the volume group";
    longdesc = "\
Given a VG called C<vgname>, this returns the UUIDs of all
the physical volumes that this volume group resides on.

You can use this along with C<guestfs_pvs> and C<guestfs_pvuuid>
calls to associate physical volumes and volume groups.

See also C<guestfs_vglvuuids>." };

  { defaults with
    name = "vglvuuids"; added = (1, 0, 87);
    style = RStringList "uuids", [String "vgname"], [];
    proc_nr = Some 226;
    shortdesc = "get the LV UUIDs of all LVs in the volume group";
    longdesc = "\
Given a VG called C<vgname>, this returns the UUIDs of all
the logical volumes created in this volume group.

You can use this along with C<guestfs_lvs> and C<guestfs_lvuuid>
calls to associate logical volumes and volume groups.

See also C<guestfs_vgpvuuids>." };

  { defaults with
    name = "copy_size"; added = (1, 0, 87);
    style = RErr, [Dev_or_Path "src"; Dev_or_Path "dest"; Int64 "size"], [];
    proc_nr = Some 227;
    progress = true; deprecated_by = Some "copy_device_to_device";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/copy_size"];
         ["write"; "/copy_size/src"; "hello, world"];
         ["copy_size"; "/copy_size/src"; "/copy_size/dest"; "5"];
         ["read_file"; "/copy_size/dest"]],
        "compare_buffers (ret, size, \"hello\", 5) == 0"), []
    ];
    shortdesc = "copy size bytes from source to destination using dd";
    longdesc = "\
This command copies exactly C<size> bytes from one source device
or file C<src> to another destination device or file C<dest>.

Note this will fail if the source is too short or if the destination
is not large enough." };

  { defaults with
    name = "zero_device"; added = (1, 3, 1);
    style = RErr, [Device "device"], [];
    proc_nr = Some 228;
    progress = true;
    tests = [
      InitBasicFSonLVM, Always, TestRun (
        [["zero_device"; "/dev/VG/LV"]]), []
    ];
    shortdesc = "write zeroes to an entire device";
    longdesc = "\
This command writes zeroes over the entire C<device>.  Compare
with C<guestfs_zero> which just zeroes the first few blocks of
a device.

If blocks are already zero, then this command avoids writing
zeroes.  This prevents the underlying device from becoming non-sparse
or growing unnecessarily." };

  { defaults with
    name = "txz_in"; added = (1, 3, 2);
    style = RErr, [FileIn "tarball"; Pathname "directory"], [];
    proc_nr = Some 229;
    deprecated_by = Some "tar_in";
    optional = Some "xz"; cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/txz_in"];
         ["txz_in"; "$srcdir/../../test-data/files/helloworld.tar.xz"; "/txz_in"];
         ["cat"; "/txz_in/hello"]], "hello\n"), []
    ];
    shortdesc = "unpack compressed tarball to directory";
    longdesc = "\
This command uploads and unpacks local file C<tarball> (an
I<xz compressed> tar file) into F<directory>." };

  { defaults with
    name = "txz_out"; added = (1, 3, 2);
    style = RErr, [Pathname "directory"; FileOut "tarball"], [];
    proc_nr = Some 230;
    deprecated_by = Some "tar_out";
    optional = Some "xz"; cancellable = true;
    shortdesc = "pack directory into compressed tarball";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<tarball> (as an xz compressed tar archive)." };

  { defaults with
    name = "vgscan"; added = (1, 3, 2);
    style = RErr, [], [];
    proc_nr = Some 232;
    tests = [
      InitEmpty, Always, TestRun (
        [["vgscan"]]), []
    ];
    shortdesc = "rescan for LVM physical volumes, volume groups and logical volumes";
    longdesc = "\
This rescans all block devices and rebuilds the list of LVM
physical volumes, volume groups and logical volumes." };

  { defaults with
    name = "part_del"; added = (1, 3, 2);
    style = RErr, [Device "device"; Int "partnum"], [];
    proc_nr = Some 233;
    tests = [
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
         ["part_del"; "/dev/sda"; "1"]]), []
    ];
    shortdesc = "delete a partition";
    longdesc = "\
This command deletes the partition numbered C<partnum> on C<device>.

Note that in the case of MBR partitioning, deleting an
extended partition also deletes any logical partitions
it contains." };

  { defaults with
    name = "part_get_bootable"; added = (1, 3, 2);
    style = RBool "bootable", [Device "device"; Int "partnum"], [];
    proc_nr = Some 234;
    tests = [
      InitEmpty, Always, TestResultTrue (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
         ["part_set_bootable"; "/dev/sda"; "1"; "true"];
         ["part_get_bootable"; "/dev/sda"; "1"]]), []
    ];
    shortdesc = "return true if a partition is bootable";
    longdesc = "\
This command returns true if the partition C<partnum> on
C<device> has the bootable flag set.

See also C<guestfs_part_set_bootable>." };

  { defaults with
    name = "part_get_mbr_id"; added = (1, 3, 2);
    style = RInt "idbyte", [Device "device"; Int "partnum"], [];
    proc_nr = Some 235;
    fish_output = Some FishOutputHexadecimal;
    tests = [
      InitEmpty, Always, TestResult (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "primary"; "1"; "-1"];
         ["part_set_mbr_id"; "/dev/sda"; "1"; "0x7f"];
         ["part_get_mbr_id"; "/dev/sda"; "1"]], "ret == 0x7f"), []
    ];
    shortdesc = "get the MBR type byte (ID byte) from a partition";
    longdesc = "\
Returns the MBR type byte (also known as the ID byte) from
the numbered partition C<partnum>.

Note that only MBR (old DOS-style) partitions have type bytes.
You will get undefined results for other partition table
types (see C<guestfs_part_get_parttype>)." };

  { defaults with
    name = "part_set_mbr_id"; added = (1, 3, 2);
    style = RErr, [Device "device"; Int "partnum"; Int "idbyte"], [];
    proc_nr = Some 236;
    shortdesc = "set the MBR type byte (ID byte) of a partition";
    longdesc = "\
Sets the MBR type byte (also known as the ID byte) of
the numbered partition C<partnum> to C<idbyte>.  Note
that the type bytes quoted in most documentation are
in fact hexadecimal numbers, but usually documented
without any leading \"0x\" which might be confusing.

Note that only MBR (old DOS-style) partitions have type bytes.
You will get undefined results for other partition table
types (see C<guestfs_part_get_parttype>)." };

  { defaults with
    name = "checksum_device"; added = (1, 3, 2);
    style = RString "checksum", [String "csumtype"; Device "device"], [];
    proc_nr = Some 237;
    tests = [
      InitISOFS, Always, TestResult (
        [["checksum_device"; "md5"; "/dev/sdd"]],
        "check_file_md5 (ret, \"../../test-data/test.iso\") == 0"), []
    ];
    shortdesc = "compute MD5, SHAx or CRC checksum of the contents of a device";
    longdesc = "\
This call computes the MD5, SHAx or CRC checksum of the
contents of the device named C<device>.  For the types of
checksums supported see the C<guestfs_checksum> command." };

  { defaults with
    name = "lvresize_free"; added = (1, 3, 3);
    style = RErr, [Device "lv"; Int "percent"], [];
    proc_nr = Some 238;
    optional = Some "lvm2";
    tests = [
      InitNone, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV"; "VG"; "10"];
         ["lvresize_free"; "/dev/VG/LV"; "100"]]), []
    ];
    shortdesc = "expand an LV to fill free space";
    longdesc = "\
This expands an existing logical volume C<lv> so that it fills
C<pc>% of the remaining free space in the volume group.  Commonly
you would call this with pc = 100 which expands the logical volume
as much as possible, using all remaining free space in the volume
group." };

  { defaults with
    name = "aug_clear"; added = (1, 3, 4);
    style = RErr, [String "augpath"], [];
    proc_nr = Some 239;
    shortdesc = "clear Augeas path";
    longdesc = "\
Set the value associated with C<path> to C<NULL>.  This
is the same as the L<augtool(1)> C<clear> command." };

  { defaults with
    name = "get_umask"; added = (1, 3, 4);
    style = RInt "mask", [], [];
    proc_nr = Some 240;
    fish_output = Some FishOutputOctal;
    tests = [
      InitEmpty, Always, TestResult (
        [["get_umask"]], "ret == 022"), []
    ];
    shortdesc = "get the current umask";
    longdesc = "\
Return the current umask.  By default the umask is C<022>
unless it has been set by calling C<guestfs_umask>." };

  { defaults with
    name = "debug_upload"; added = (1, 3, 5);
    style = RErr, [FileIn "filename"; String "tmpname"; Int "mode"], [];
    proc_nr = Some 241;
    visibility = VDebug;
    cancellable = true;
    shortdesc = "upload a file to the appliance (internal use only)";
    longdesc = "\
The C<guestfs_debug_upload> command uploads a file to
the libguestfs appliance.

There is no comprehensive help for this command.  You have
to look at the file F<daemon/debug.c> in the libguestfs source
to find out what it is for." };

  { defaults with
    name = "base64_in"; added = (1, 3, 5);
    style = RErr, [FileIn "base64file"; Pathname "filename"], [];
    proc_nr = Some 242;
    cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["base64_in"; "../../test-data/files/hello.b64"; "/base64_in"];
         ["cat"; "/base64_in"]], "hello\n"), []
    ];
    shortdesc = "upload base64-encoded data to file";
    longdesc = "\
This command uploads base64-encoded data from C<base64file>
to F<filename>." };

  { defaults with
    name = "base64_out"; added = (1, 3, 5);
    style = RErr, [Pathname "filename"; FileOut "base64file"], [];
    proc_nr = Some 243;
    cancellable = true;
    shortdesc = "download file and encode as base64";
    longdesc = "\
This command downloads the contents of F<filename>, writing
it out to local file C<base64file> encoded as base64." };

  { defaults with
    name = "checksums_out"; added = (1, 3, 7);
    style = RErr, [String "csumtype"; Pathname "directory"; FileOut "sumsfile"], [];
    proc_nr = Some 244;
    cancellable = true;
    shortdesc = "compute MD5, SHAx or CRC checksum of files in a directory";
    longdesc = "\
This command computes the checksums of all regular files in
F<directory> and then emits a list of those checksums to
the local output file C<sumsfile>.

This can be used for verifying the integrity of a virtual
machine.  However to be properly secure you should pay
attention to the output of the checksum command (it uses
the ones from GNU coreutils).  In particular when the
filename is not printable, coreutils uses a special
backslash syntax.  For more information, see the GNU
coreutils info file." };

  { defaults with
    name = "fill_pattern"; added = (1, 3, 12);
    style = RErr, [String "pattern"; Int "len"; Pathname "path"], [];
    proc_nr = Some 245;
    progress = true;
    tests = [
      InitScratchFS, Always, TestResult (
        [["fill_pattern"; "abcdefghijklmnopqrstuvwxyz"; "28"; "/fill_pattern"];
         ["read_file"; "/fill_pattern"]],
        "compare_buffers (ret, size, \"abcdefghijklmnopqrstuvwxyzab\", 28) == 0"), []
    ];
    shortdesc = "fill a file with a repeating pattern of bytes";
    longdesc = "\
This function is like C<guestfs_fill> except that it creates
a new file of length C<len> containing the repeating pattern
of bytes in C<pattern>.  The pattern is truncated if necessary
to ensure the length of the file is exactly C<len> bytes." };

  { defaults with
    name = "internal_write"; added = (1, 19, 32);
    style = RErr, [Pathname "path"; BufferIn "content"], [];
    proc_nr = Some 246;
    visibility = VInternal;
    protocol_limit_warning = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write"; "new file contents"];
         ["cat"; "/internal_write"]], "new file contents"), [];
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write2"; "\nnew file contents\n"];
         ["cat"; "/internal_write2"]], "\nnew file contents\n"), [];
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write3"; "\n\n"];
         ["cat"; "/internal_write3"]], "\n\n"), [];
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write4"; ""];
         ["cat"; "/internal_write4"]], ""), [];
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write5"; "\n\n\n"];
         ["cat"; "/internal_write5"]], "\n\n\n"), [];
      InitScratchFS, Always, TestResultString (
        [["internal_write"; "/internal_write6"; "\n"];
         ["cat"; "/internal_write6"]], "\n"), []
    ];
    shortdesc = "create a new file";
    longdesc = "\
This call creates a file called C<path>.  The content of the
file is the string C<content> (which can contain any 8 bit data).

See also C<guestfs_write_append>." };

  { defaults with
    name = "pwrite"; added = (1, 3, 14);
    style = RInt "nbytes", [Pathname "path"; BufferIn "content"; Int64 "offset"], [];
    proc_nr = Some 247;
    protocol_limit_warning = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["write"; "/pwrite"; "new file contents"];
         ["pwrite"; "/pwrite"; "data"; "4"];
         ["cat"; "/pwrite"]], "new data contents"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/pwrite2"; "new file contents"];
         ["pwrite"; "/pwrite2"; "is extended"; "9"];
         ["cat"; "/pwrite2"]], "new file is extended"), [];
      InitScratchFS, Always, TestResultString (
        [["write"; "/pwrite3"; "new file contents"];
         ["pwrite"; "/pwrite3"; ""; "4"];
         ["cat"; "/pwrite3"]], "new file contents"), []
    ];
    shortdesc = "write to part of a file";
    longdesc = "\
This command writes to part of a file.  It writes the data
buffer C<content> to the file C<path> starting at offset C<offset>.

This command implements the L<pwrite(2)> system call, and like
that system call it may not write the full data requested.  The
return value is the number of bytes that were actually written
to the file.  This could even be 0, although short writes are
unlikely for regular files in ordinary circumstances.

See also C<guestfs_pread>, C<guestfs_pwrite_device>." };

  { defaults with
    name = "resize2fs_size"; added = (1, 3, 14);
    style = RErr, [Device "device"; Int64 "size"], [];
    proc_nr = Some 248;
    shortdesc = "resize an ext2, ext3 or ext4 filesystem (with size)";
    longdesc = "\
This command is the same as C<guestfs_resize2fs> except that it
allows you to specify the new size (in bytes) explicitly.

See also L<guestfs(3)/RESIZE2FS ERRORS>." };

  { defaults with
    name = "pvresize_size"; added = (1, 3, 14);
    style = RErr, [Device "device"; Int64 "size"], [];
    proc_nr = Some 249;
    optional = Some "lvm2";
    shortdesc = "resize an LVM physical volume (with size)";
    longdesc = "\
This command is the same as C<guestfs_pvresize> except that it
allows you to specify the new size (in bytes) explicitly." };

  { defaults with
    name = "ntfsresize_size"; added = (1, 3, 14);
    style = RErr, [Device "device"; Int64 "size"], [];
    proc_nr = Some 250;
    optional = Some "ntfsprogs"; deprecated_by = Some "ntfsresize";
    shortdesc = "resize an NTFS filesystem (with size)";
    longdesc = "\
This command is the same as C<guestfs_ntfsresize> except that it
allows you to specify the new size (in bytes) explicitly." };

  { defaults with
    name = "available_all_groups"; added = (1, 3, 15);
    style = RStringList "groups", [], [];
    proc_nr = Some 251;
    tests = [
      InitNone, Always, TestRun [["available_all_groups"]], []
    ];
    shortdesc = "return a list of all optional groups";
    longdesc = "\
This command returns a list of all optional groups that this
daemon knows about.  Note this returns both supported and unsupported
groups.  To find out which ones the daemon can actually support
you have to call C<guestfs_available> / C<guestfs_feature_available>
on each member of the returned list.

See also C<guestfs_available>, C<guestfs_feature_available>
and L<guestfs(3)/AVAILABILITY>." };

  { defaults with
    name = "fallocate64"; added = (1, 3, 17);
    style = RErr, [Pathname "path"; Int64 "len"], [];
    proc_nr = Some 252;
    tests = [
      InitScratchFS, Always, TestResult (
        [["fallocate64"; "/fallocate64"; "1000000"];
         ["stat"; "/fallocate64"]], "ret->size == 1000000"), []
    ];
    shortdesc = "preallocate a file in the guest filesystem";
    longdesc = "\
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
a file in the host and attach it as a device." };

  { defaults with
    name = "vfs_label"; added = (1, 3, 18);
    style = RString "label", [Mountable "mountable"], [];
    proc_nr = Some 253;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["set_label"; "/dev/sda1"; "LTEST"];
         ["vfs_label"; "/dev/sda1"]], "LTEST"), [];
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "test-label"];
         ["vfs_label"; "/dev/sda1"]], "test-label"), [];
      InitEmpty, IfAvailable "btrfs", TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "btrfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; ""];
         ["set_label"; "/dev/sda1"; "test-label-btrfs"];
         ["vfs_label"; "/dev/sda1"]], "test-label-btrfs"), [];
    ];
    shortdesc = "get the filesystem label";
    longdesc = "\
This returns the label of the filesystem on C<mountable>.

If the filesystem is unlabeled, this returns the empty string.

To find a filesystem from the label, use C<guestfs_findfs_label>." };

  { defaults with
    name = "vfs_uuid"; added = (1, 3, 18);
    style = RString "uuid", [Mountable "mountable"], [];
    fish_alias = ["get-uuid"];
    proc_nr = Some 254;
    tests =
      (let uuid = uuidgen () in [
        InitBasicFS, Always, TestResultString (
          [["set_e2uuid"; "/dev/sda1"; uuid];
           ["vfs_uuid"; "/dev/sda1"]], uuid), []
      ]);
    shortdesc = "get the filesystem UUID";
    longdesc = "\
This returns the filesystem UUID of the filesystem on C<mountable>.

If the filesystem does not have a UUID, this returns the empty string.

To find a filesystem from the UUID, use C<guestfs_findfs_uuid>." };

  { defaults with
    name = "lvm_set_filter"; added = (1, 5, 1);
    style = RErr, [DeviceList "devices"], [];
    proc_nr = Some 255;
    optional = Some "lvm2";
    test_excuse = "cannot be tested with the current framework because the VG is being used by the mounted filesystem, so the 'vgchange -an' command we do first will fail";
    shortdesc = "set LVM device filter";
    longdesc = "\
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
filtering out that VG." };

  { defaults with
    name = "lvm_clear_filter"; added = (1, 5, 1);
    style = RErr, [], [];
    proc_nr = Some 256;
    test_excuse = "cannot be tested with the current framework because the VG is being used by the mounted filesystem, so the 'vgchange -an' command we do first will fail";
    shortdesc = "clear LVM device filter";
    longdesc = "\
This undoes the effect of C<guestfs_lvm_set_filter>.  LVM
will be able to see every block device.

This command also clears the LVM cache and performs a volume
group scan." };

  { defaults with
    name = "luks_open"; added = (1, 5, 1);
    style = RErr, [Device "device"; Key "key"; String "mapname"], [];
    proc_nr = Some 257;
    optional = Some "luks";
    shortdesc = "open a LUKS-encrypted block device";
    longdesc = "\
This command opens a block device which has been encrypted
according to the Linux Unified Key Setup (LUKS) standard.

C<device> is the encrypted block device or partition.

The caller must supply one of the keys associated with the
LUKS block device, in the C<key> parameter.

This creates a new block device called F</dev/mapper/mapname>.
Reads and writes to this block device are decrypted from and
encrypted to the underlying C<device> respectively.

If this block device contains LVM volume groups, then
calling C<guestfs_vgscan> followed by C<guestfs_vg_activate_all>
will make them visible.

Use C<guestfs_list_dm_devices> to list all device mapper
devices." };

  { defaults with
    name = "luks_open_ro"; added = (1, 5, 1);
    style = RErr, [Device "device"; Key "key"; String "mapname"], [];
    proc_nr = Some 258;
    optional = Some "luks";
    shortdesc = "open a LUKS-encrypted block device read-only";
    longdesc = "\
This is the same as C<guestfs_luks_open> except that a read-only
mapping is created." };

  { defaults with
    name = "luks_close"; added = (1, 5, 1);
    style = RErr, [Device "device"], [];
    proc_nr = Some 259;
    optional = Some "luks";
    shortdesc = "close a LUKS device";
    longdesc = "\
This closes a LUKS device that was created earlier by
C<guestfs_luks_open> or C<guestfs_luks_open_ro>.  The
C<device> parameter must be the name of the LUKS mapping
device (ie. F</dev/mapper/mapname>) and I<not> the name
of the underlying block device." };

  { defaults with
    name = "luks_format"; added = (1, 5, 2);
    style = RErr, [Device "device"; Key "key"; Int "keyslot"], [];
    proc_nr = Some 260;
    optional = Some "luks";
    shortdesc = "format a block device as a LUKS encrypted device";
    longdesc = "\
This command erases existing data on C<device> and formats
the device as a LUKS encrypted device.  C<key> is the
initial key, which is added to key slot C<slot>.  (LUKS
supports 8 key slots, numbered 0-7)." };

  { defaults with
    name = "luks_format_cipher"; added = (1, 5, 2);
    style = RErr, [Device "device"; Key "key"; Int "keyslot"; String "cipher"], [];
    proc_nr = Some 261;
    optional = Some "luks";
    shortdesc = "format a block device as a LUKS encrypted device";
    longdesc = "\
This command is the same as C<guestfs_luks_format> but
it also allows you to set the C<cipher> used." };

  { defaults with
    name = "luks_add_key"; added = (1, 5, 2);
    style = RErr, [Device "device"; Key "key"; Key "newkey"; Int "keyslot"], [];
    proc_nr = Some 262;
    optional = Some "luks";
    shortdesc = "add a key on a LUKS encrypted device";
    longdesc = "\
This command adds a new key on LUKS device C<device>.
C<key> is any existing key, and is used to access the device.
C<newkey> is the new key to add.  C<keyslot> is the key slot
that will be replaced.

Note that if C<keyslot> already contains a key, then this
command will fail.  You have to use C<guestfs_luks_kill_slot>
first to remove that key." };

  { defaults with
    name = "luks_kill_slot"; added = (1, 5, 2);
    style = RErr, [Device "device"; Key "key"; Int "keyslot"], [];
    proc_nr = Some 263;
    optional = Some "luks";
    shortdesc = "remove a key from a LUKS encrypted device";
    longdesc = "\
This command deletes the key in key slot C<keyslot> from the
encrypted LUKS device C<device>.  C<key> must be one of the
I<other> keys." };

  { defaults with
    name = "is_lv"; added = (1, 5, 3);
    style = RBool "lvflag", [Device "device"], [];
    proc_nr = Some 264;
    tests = [
      InitBasicFSonLVM, Always, TestResultTrue (
        [["is_lv"; "/dev/VG/LV"]]), [];
      InitBasicFSonLVM, Always, TestResultFalse (
        [["is_lv"; "/dev/sda1"]]), []
    ];
    shortdesc = "test if device is a logical volume";
    longdesc = "\
This command tests whether C<device> is a logical volume, and
returns true iff this is the case." };

  { defaults with
    name = "findfs_uuid"; added = (1, 5, 3);
    style = RString "device", [String "uuid"], [];
    proc_nr = Some 265;
    shortdesc = "find a filesystem by UUID";
    longdesc = "\
This command searches the filesystems and returns the one
which has the given UUID.  An error is returned if no such
filesystem can be found.

To find the UUID of a filesystem, use C<guestfs_vfs_uuid>." };

  { defaults with
    name = "findfs_label"; added = (1, 5, 3);
    style = RString "device", [String "label"], [];
    proc_nr = Some 266;
    shortdesc = "find a filesystem by label";
    longdesc = "\
This command searches the filesystems and returns the one
which has the given label.  An error is returned if no such
filesystem can be found.

To find the label of a filesystem, use C<guestfs_vfs_label>." };

  { defaults with
    name = "is_chardev"; added = (1, 5, 10);
    style = RBool "flag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 267;
    once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_chardev"; "/directory"; ""]]), [];
      InitScratchFS, Always, TestResultTrue (
        [["mknod_c"; "0o777"; "99"; "66"; "/is_chardev"];
         ["is_chardev"; "/is_chardev"; ""]]), []
    ];
    shortdesc = "test if character device";
    longdesc = "\
This returns C<true> if and only if there is a character device
with the given C<path> name.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a chardev also causes the
function to return true.

See also C<guestfs_stat>." };

  { defaults with
    name = "is_blockdev"; added = (1, 5, 10);
    style = RBool "flag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 268;
    once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_blockdev"; "/directory"; ""]]), [];
      InitScratchFS, Always, TestResultTrue (
        [["mknod_b"; "0o777"; "99"; "66"; "/is_blockdev"];
         ["is_blockdev"; "/is_blockdev"; ""]]), []
    ];
    shortdesc = "test if block device";
    longdesc = "\
This returns C<true> if and only if there is a block device
with the given C<path> name.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a block device also causes the
function to return true.

This call only looks at files within the guest filesystem.  Libguestfs
partitions and block devices (eg. F</dev/sda>) cannot be used as the
C<path> parameter of this call.

See also C<guestfs_stat>." };

  { defaults with
    name = "is_fifo"; added = (1, 5, 10);
    style = RBool "flag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 269;
    once_had_no_optargs = true;
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_fifo"; "/directory"; ""]]), [];
      InitScratchFS, Always, TestResultTrue (
        [["mkfifo"; "0o777"; "/is_fifo"];
         ["is_fifo"; "/is_fifo"; ""]]), []
    ];
    shortdesc = "test if FIFO (named pipe)";
    longdesc = "\
This returns C<true> if and only if there is a FIFO (named pipe)
with the given C<path> name.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a FIFO also causes the
function to return true.

See also C<guestfs_stat>." };

  { defaults with
    name = "is_symlink"; added = (1, 5, 10);
    style = RBool "flag", [Pathname "path"], [];
    proc_nr = Some 270;
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_symlink"; "/directory"]]), [];
      InitISOFS, Always, TestResultTrue (
        [["is_symlink"; "/abssymlink"]]), []
    ];
    shortdesc = "test if symbolic link";
    longdesc = "\
This returns C<true> if and only if there is a symbolic link
with the given C<path> name.

See also C<guestfs_stat>." };

  { defaults with
    name = "is_socket"; added = (1, 5, 10);
    style = RBool "flag", [Pathname "path"], [OBool "followsymlinks"];
    proc_nr = Some 271;
    once_had_no_optargs = true;
    (* XXX Need a positive test for sockets. *)
    tests = [
      InitISOFS, Always, TestResultFalse (
        [["is_socket"; "/directory"; ""]]), []
    ];
    shortdesc = "test if socket";
    longdesc = "\
This returns C<true> if and only if there is a Unix domain socket
with the given C<path> name.

If the optional flag C<followsymlinks> is true, then a symlink
(or chain of symlinks) that ends with a socket also causes the
function to return true.

See also C<guestfs_stat>." };

  { defaults with
    name = "part_to_dev"; added = (1, 5, 15);
    style = RString "device", [Device "partition"], [];
    proc_nr = Some 272;
    tests = [
      InitPartition, Always, TestResultDevice (
        [["part_to_dev"; "/dev/sda1"]], "/dev/sda"), [];
      InitEmpty, Always, TestLastFail (
        [["part_to_dev"; "/dev/sda"]]), []
    ];
    shortdesc = "convert partition name to device name";
    longdesc = "\
This function takes a partition name (eg. \"/dev/sdb1\") and
removes the partition number, returning the device name
(eg. \"/dev/sdb\").

The named partition must exist, for example as a string returned
from C<guestfs_list_partitions>.

See also C<guestfs_part_to_partnum>, C<guestfs_device_index>." };

  { defaults with
    name = "upload_offset"; added = (1, 5, 17);
    style = RErr, [FileIn "filename"; Dev_or_Path "remotefilename"; Int64 "offset"], [];
    proc_nr = Some 273;
    progress = true; cancellable = true;
    tests =
      (let md5 = Digest.to_hex (Digest.file "COPYING.LIB") in [
        InitScratchFS, Always, TestResultString (
          [["upload_offset"; "$srcdir/../../COPYING.LIB"; "/upload_offset"; "0"];
           ["checksum"; "md5"; "/upload_offset"]], md5), []
      ]);
    shortdesc = "upload a file from the local machine with offset";
    longdesc = "\
Upload local file F<filename> to F<remotefilename> on the
filesystem.

F<remotefilename> is overwritten starting at the byte C<offset>
specified.  The intention is to overwrite parts of existing
files or devices, although if a non-existent file is specified
then it is created with a \"hole\" before C<offset>.  The
size of the data written is implicit in the size of the
source F<filename>.

Note that there is no limit on the amount of data that
can be uploaded with this call, unlike with C<guestfs_pwrite>,
and this call always writes the full amount unless an
error occurs.

See also C<guestfs_upload>, C<guestfs_pwrite>." };

  { defaults with
    name = "download_offset"; added = (1, 5, 17);
    style = RErr, [Dev_or_Path "remotefilename"; FileOut "filename"; Int64 "offset"; Int64 "size"], [];
    proc_nr = Some 274;
    progress = true; cancellable = true;
    tests =
      (let md5 = Digest.to_hex (Digest.file "COPYING.LIB") in
       let offset = string_of_int 100 in
       let size = string_of_int ((Unix.stat "COPYING.LIB").Unix.st_size - 100) in
       [
         InitScratchFS, Always, TestResultString (
           (* Pick a file from cwd which isn't likely to change. *)
           [["mkdir"; "/download_offset"];
            ["upload"; "$srcdir/../../COPYING.LIB"; "/download_offset/COPYING.LIB"];
            ["download_offset"; "/download_offset/COPYING.LIB"; "testdownload.tmp"; offset; size];
            ["upload_offset"; "testdownload.tmp"; "/download_offset/COPYING.LIB"; offset];
            ["checksum"; "md5"; "/download_offset/COPYING.LIB"]], md5), []
       ]);
    shortdesc = "download a file to the local machine with offset and size";
    longdesc = "\
Download file F<remotefilename> and save it as F<filename>
on the local machine.

F<remotefilename> is read for C<size> bytes starting at C<offset>
(this region must be within the file or device).

Note that there is no limit on the amount of data that
can be downloaded with this call, unlike with C<guestfs_pread>,
and this call always reads the full amount unless an
error occurs.

See also C<guestfs_download>, C<guestfs_pread>." };

  { defaults with
    name = "pwrite_device"; added = (1, 5, 20);
    style = RInt "nbytes", [Device "device"; BufferIn "content"; Int64 "offset"], [];
    proc_nr = Some 275;
    protocol_limit_warning = true;
    tests = [
      InitPartition, Always, TestResult (
        [["pwrite_device"; "/dev/sda"; "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"; "446"];
         ["blockdev_rereadpt"; "/dev/sda"];
         ["list_partitions"]],
        "is_device_list (ret, 1, \"/dev/sdb1\")"), []
    ];
    shortdesc = "write to part of a device";
    longdesc = "\
This command writes to part of a device.  It writes the data
buffer C<content> to C<device> starting at offset C<offset>.

This command implements the L<pwrite(2)> system call, and like
that system call it may not write the full data requested
(although short writes to disk devices and partitions are
probably impossible with standard Linux kernels).

See also C<guestfs_pwrite>." };

  { defaults with
    name = "pread_device"; added = (1, 5, 21);
    style = RBufferOut "content", [Device "device"; Int "count"; Int64 "offset"], [];
    proc_nr = Some 276;
    protocol_limit_warning = true;
    tests = [
      InitEmpty, Always, TestResult (
        [["pread_device"; "/dev/sdd"; "8"; "32768"]],
        "compare_buffers (ret, size, \"\\1CD001\\1\\0\", 8) == 0"), []
    ];
    shortdesc = "read part of a device";
    longdesc = "\
This command lets you read part of a block device.  It reads C<count>
bytes of C<device>, starting at C<offset>.

This may read fewer bytes than requested.  For further details
see the L<pread(2)> system call.

See also C<guestfs_pread>." };

  { defaults with
    name = "lvm_canonical_lv_name"; added = (1, 5, 24);
    style = RString "lv", [Device "lvname"], [];
    proc_nr = Some 277;
    tests = [
      InitBasicFSonLVM, IfAvailable "lvm2", TestResultString (
        [["lvm_canonical_lv_name"; "/dev/mapper/VG-LV"]], "/dev/VG/LV"), [];
      InitBasicFSonLVM, IfAvailable "lvm2", TestResultString (
        [["lvm_canonical_lv_name"; "/dev/VG/LV"]], "/dev/VG/LV"), []
    ];
    shortdesc = "get canonical name of an LV";
    longdesc = "\
This converts alternative naming schemes for LVs that you
might find to the canonical name.  For example, F</dev/mapper/VG-LV>
is converted to F</dev/VG/LV>.

This command returns an error if the C<lvname> parameter does
not refer to a logical volume.

See also C<guestfs_is_lv>, C<guestfs_canonical_device_name>." };

  { defaults with
    name = "mkfs"; added = (0, 0, 8);
    style = RErr, [String "fstype"; Device "device"], [OInt "blocksize"; OString "features"; OInt "inode"; OInt "sectorsize"; OString "label"];
    proc_nr = Some 278;
    once_had_no_optargs = true;
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "make a filesystem";
    longdesc = "\
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

=back" };

  { defaults with
    name = "getxattr"; added = (1, 7, 24);
    style = RBufferOut "xattr", [Pathname "path"; String "name"], [];
    proc_nr = Some 279;
    optional = Some "linuxxattrs";
    shortdesc = "get a single extended attribute";
    longdesc = "\
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

See also: C<guestfs_getxattrs>, C<guestfs_lgetxattr>, L<attr(5)>." };

  { defaults with
    name = "lgetxattr"; added = (1, 7, 24);
    style = RBufferOut "xattr", [Pathname "path"; String "name"], [];
    proc_nr = Some 280;
    optional = Some "linuxxattrs";
    shortdesc = "get a single extended attribute";
    longdesc = "\
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

See also: C<guestfs_lgetxattrs>, C<guestfs_getxattr>, L<attr(5)>." };

  { defaults with
    name = "resize2fs_M"; added = (1, 9, 4);
    style = RErr, [Device "device"], [];
    proc_nr = Some 281;
    shortdesc = "resize an ext2, ext3 or ext4 filesystem to the minimum size";
    longdesc = "\
This command is the same as C<guestfs_resize2fs>, but the filesystem
is resized to its minimum size.  This works like the I<-M> option
to the C<resize2fs> command.

To get the resulting size of the filesystem you should call
C<guestfs_tune2fs_l> and read the C<Block size> and C<Block count>
values.  These two numbers, multiplied together, give the
resulting size of the minimal filesystem in bytes.

See also L<guestfs(3)/RESIZE2FS ERRORS>." };

  { defaults with
    name = "internal_autosync"; added = (1, 9, 7);
    style = RErr, [], [];
    proc_nr = Some 282;
    visibility = VInternal;
    shortdesc = "internal autosync operation";
    longdesc = "\
This command performs the autosync operation just before the
handle is closed.  You should not call this command directly.
Instead, use the autosync flag (C<guestfs_set_autosync>) to
control whether or not this operation is performed when the
handle is closed." };

  { defaults with
    name = "is_zero"; added = (1, 11, 8);
    style = RBool "zeroflag", [Pathname "path"], [];
    proc_nr = Some 283;
    tests = [
      InitISOFS, Always, TestResultTrue (
        [["is_zero"; "/100kallzeroes"]]), [];
      InitISOFS, Always, TestResultFalse (
        [["is_zero"; "/100kallspaces"]]), []
    ];
    shortdesc = "test if a file contains all zero bytes";
    longdesc = "\
This returns true iff the file exists and the file is empty or
it contains all zero bytes." };

  { defaults with
    name = "is_zero_device"; added = (1, 11, 8);
    style = RBool "zeroflag", [Device "device"], [];
    proc_nr = Some 284;
    tests = [
      InitBasicFS, Always, TestResultTrue (
        [["umount"; "/dev/sda1"; "false"; "false"];
         ["zero_device"; "/dev/sda1"];
         ["is_zero_device"; "/dev/sda1"]]), [];
      InitBasicFS, Always, TestResultFalse (
        [["is_zero_device"; "/dev/sda1"]]), []
    ];
    shortdesc = "test if a device contains all zero bytes";
    longdesc = "\
This returns true iff the device exists and contains all zero bytes.

Note that for large devices this can take a long time to run." };

  { defaults with
    name = "list_dm_devices"; added = (1, 11, 15);
    style = RStringList "devices", [], [];
    proc_nr = Some 287;
    shortdesc = "list device mapper devices";
    longdesc = "\
List all device mapper devices.

The returned list contains F</dev/mapper/*> devices, eg. ones created
by a previous call to C<guestfs_luks_open>.

Device mapper devices which correspond to logical volumes are I<not>
returned in this list.  Call C<guestfs_lvs> if you want to list logical
volumes." };

  { defaults with
    name = "ntfsresize"; added = (1, 3, 2);
    style = RErr, [Device "device"], [OInt64 "size"; OBool "force"];
    once_had_no_optargs = true;
    proc_nr = Some 288;
    optional = Some "ntfsprogs"; camel_name = "NTFSResizeOpts";
    shortdesc = "resize an NTFS filesystem";
    longdesc = "\
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
possible to call C<guestfs_ntfsresize> multiple times on a
single filesystem without booting into Windows between each resize.

=back

See also L<ntfsresize(8)>." };

  { defaults with
    name = "btrfs_filesystem_resize"; added = (1, 11, 17);
    style = RErr, [Pathname "mountpoint"], [OInt64 "size"];
    proc_nr = Some 289;
    optional = Some "btrfs"; camel_name = "BTRFSFilesystemResize";
    shortdesc = "resize a btrfs filesystem";
    longdesc = "\
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

See also L<btrfs(8)>." };

  { defaults with
    name = "internal_write_append"; added = (1, 19, 32);
    style = RErr, [Pathname "path"; BufferIn "content"], [];
    proc_nr = Some 290;
    visibility = VInternal;
    protocol_limit_warning = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["write"; "/internal_write_append"; "line1\n"];
         ["internal_write_append"; "/internal_write_append"; "line2\n"];
         ["internal_write_append"; "/internal_write_append"; "line3a"];
         ["internal_write_append"; "/internal_write_append"; "line3b\n"];
         ["cat"; "/internal_write_append"]], "line1\nline2\nline3aline3b\n"), []
    ];
    shortdesc = "append content to end of file";
    longdesc = "\
This call appends C<content> to the end of file C<path>.  If
C<path> does not exist, then a new file is created.

See also C<guestfs_write>." };

  { defaults with
    name = "compress_out"; added = (1, 13, 15);
    style = RErr, [String "ctype"; Pathname "file"; FileOut "zfile"], [OInt "level"];
    proc_nr = Some 291;
    cancellable = true;
    shortdesc = "output compressed file";
    longdesc = "\
This command compresses F<file> and writes it out to the local
file F<zfile>.

The compression program used is controlled by the C<ctype> parameter.
Currently this includes: C<compress>, C<gzip>, C<bzip2>, C<xz> or C<lzop>.
Some compression types may not be supported by particular builds of
libguestfs, in which case you will get an error containing the
substring \"not supported\".

The optional C<level> parameter controls compression level.  The
meaning and default for this parameter depends on the compression
program being used." };

  { defaults with
    name = "compress_device_out"; added = (1, 13, 15);
    style = RErr, [String "ctype"; Device "device"; FileOut "zdevice"], [OInt "level"];
    proc_nr = Some 292;
    cancellable = true;
    shortdesc = "output compressed device";
    longdesc = "\
This command compresses C<device> and writes it out to the local
file C<zdevice>.

The C<ctype> and optional C<level> parameters have the same meaning
as in C<guestfs_compress_out>." };

  { defaults with
    name = "part_to_partnum"; added = (1, 13, 25);
    style = RInt "partnum", [Device "partition"], [];
    proc_nr = Some 293;
    tests = [
      InitPartition, Always, TestResult (
        [["part_to_partnum"; "/dev/sda1"]], "ret == 1"), [];
      InitEmpty, Always, TestLastFail (
        [["part_to_partnum"; "/dev/sda"]]), []
    ];
    shortdesc = "convert partition name to partition number";
    longdesc = "\
This function takes a partition name (eg. \"/dev/sdb1\") and
returns the partition number (eg. C<1>).

The named partition must exist, for example as a string returned
from C<guestfs_list_partitions>.

See also C<guestfs_part_to_dev>." };

  { defaults with
    name = "copy_device_to_device"; added = (1, 13, 25);
    style = RErr, [Device "src"; Device "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"; OBool "sparse"; OBool "append"];
    proc_nr = Some 294;
    progress = true;
    shortdesc = "copy from source device to destination device";
    longdesc = "\
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
the destination file is not large enough, it is extended.

If the destination is a file and the C<append> flag is not set,
then the destination file is truncated.  If the C<append> flag is
set, then the copy appends to the destination file.  The C<append>
flag currently cannot be set for devices.

If the C<sparse> flag is true then the call avoids writing
blocks that contain only zeroes, which can help in some situations
where the backing disk is thin-provisioned.  Note that unless
the target is already zeroed, using this option will result
in incorrect copying." };

  { defaults with
    name = "copy_device_to_file"; added = (1, 13, 25);
    style = RErr, [Device "src"; Pathname "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"; OBool "sparse"; OBool "append"];
    proc_nr = Some 295;
    progress = true;
    shortdesc = "copy from source device to destination file";
    longdesc = "\
See C<guestfs_copy_device_to_device> for a general overview
of this call." };

  { defaults with
    name = "copy_file_to_device"; added = (1, 13, 25);
    style = RErr, [Pathname "src"; Device "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"; OBool "sparse"; OBool "append"];
    proc_nr = Some 296;
    progress = true;
    shortdesc = "copy from source file to destination device";
    longdesc = "\
See C<guestfs_copy_device_to_device> for a general overview
of this call." };

  { defaults with
    name = "copy_file_to_file"; added = (1, 13, 25);
    style = RErr, [Pathname "src"; Pathname "dest"], [OInt64 "srcoffset"; OInt64 "destoffset"; OInt64 "size"; OBool "sparse"; OBool "append"];
    proc_nr = Some 297;
    progress = true;
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/copyff"];
         ["write"; "/copyff/src"; "hello, world"];
         ["copy_file_to_file"; "/copyff/src"; "/copyff/dest"; ""; ""; ""; ""; "false"];
         ["read_file"; "/copyff/dest"]],
        "compare_buffers (ret, size, \"hello, world\", 12) == 0"), [];
      InitScratchFS, Always, TestResultTrue (
        let size = 1024 * 1024 in
        [["mkdir"; "/copyff2"];
         ["fill"; "0"; string_of_int size; "/copyff2/src"];
         ["touch"; "/copyff2/dest"];
         ["truncate_size"; "/copyff2/dest"; string_of_int size];
         ["copy_file_to_file"; "/copyff2/src"; "/copyff2/dest"; ""; ""; ""; "true"; "false"];
         ["is_zero"; "/copyff2/dest"]]), [];
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/copyff3"];
         ["write"; "/copyff3/src"; "hello, world"];
         ["copy_file_to_file"; "/copyff3/src"; "/copyff3/dest"; ""; ""; ""; ""; "true"];
         ["copy_file_to_file"; "/copyff3/src"; "/copyff3/dest"; ""; ""; ""; ""; "true"];
         ["copy_file_to_file"; "/copyff3/src"; "/copyff3/dest"; ""; ""; ""; ""; "true"];
         ["read_file"; "/copyff3/dest"]],
        "compare_buffers (ret, size, \"hello, worldhello, worldhello, world\", 12*3) == 0"), [];
    ];
    shortdesc = "copy from source file to destination file";
    longdesc = "\
See C<guestfs_copy_device_to_device> for a general overview
of this call.

This is B<not> the function you want for copying files.  This
is for copying blocks within existing files.  See C<guestfs_cp>,
C<guestfs_cp_a> and C<guestfs_mv> for general file copying and
moving functions." };

  { defaults with
    name = "tune2fs"; added = (1, 15, 4);
    style = RErr, [Device "device"], [OBool "force"; OInt "maxmountcount"; OInt "mountcount"; OString "errorbehavior"; OInt64 "group"; OInt "intervalbetweenchecks"; OInt "reservedblockspercentage"; OString "lastmounteddirectory"; OInt64 "reservedblockscount"; OInt64 "user"];
    proc_nr = Some 298;
    camel_name = "Tune2FS";
    tests = [
      InitScratchFS, Always, TestResult (
        [["tune2fs"; "/dev/sdb1"; "false"; "0"; ""; "NOARG"; ""; "0"; ""; "NOARG"; ""; ""];
         ["tune2fs_l"; "/dev/sdb1"]],
        "check_hash (ret, \"Check interval\", \"0 (<none>)\") == 0 && "^
          "check_hash (ret, \"Maximum mount count\", \"-1\") == 0"), [];
      InitScratchFS, Always, TestResult (
        [["tune2fs"; "/dev/sdb1"; "false"; "0"; ""; "NOARG"; ""; "86400"; ""; "NOARG"; ""; ""];
         ["tune2fs_l"; "/dev/sdb1"]],
        "check_hash (ret, \"Check interval\", \"86400 (1 day)\") == 0 && "^
          "check_hash (ret, \"Maximum mount count\", \"-1\") == 0"), [];
      InitScratchFS, Always, TestResult (
        [["tune2fs"; "/dev/sdb1"; "false"; ""; ""; "NOARG"; "1"; ""; ""; "NOARG"; ""; "1"];
         ["tune2fs_l"; "/dev/sdb1"]],
        "match_re (get_key (ret, \"Reserved blocks uid\"), \"\\\\d+ \\\\(user \\\\S+\\\\)\") && "^
          "match_re (get_key (ret, \"Reserved blocks gid\"), \"\\\\d+ \\\\(group \\\\S+\\\\)\")"), [];
      InitScratchFS, Always, TestResult (
        [["tune2fs"; "/dev/sdb1"; "false"; ""; ""; "NOARG"; "0"; ""; ""; "NOARG"; ""; "0"];
         ["tune2fs_l"; "/dev/sdb1"]],
        "match_re (get_key (ret, \"Reserved blocks uid\"), \"\\\\d+ \\\\(user \\\\S+\\\\)\") && "^
          "match_re (get_key (ret, \"Reserved blocks gid\"), \"\\\\d+ \\\\(group \\\\S+\\\\)\")"), [];
    ];
    shortdesc = "adjust ext2/ext3/ext4 filesystem parameters";
    longdesc = "\
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
works, see the L<tune2fs(8)> man page." };

  { defaults with
    name = "md_create"; added = (1, 15, 6);
    style = RErr, [String "name"; DeviceList "devices"], [OInt64 "missingbitmap"; OInt "nrdevices"; OInt "spare"; OInt64 "chunk"; OString "level"];
    proc_nr = Some 299;
    optional = Some "mdadm"; camel_name = "MDCreate";
    shortdesc = "create a Linux md (RAID) device";
    longdesc = "\
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

=back" };

  { defaults with
    name = "list_md_devices"; added = (1, 15, 4);
    style = RStringList "devices", [], [];
    proc_nr = Some 300;
    shortdesc = "list Linux md (RAID) devices";
    longdesc = "\
List all Linux md devices." };

  { defaults with
    name = "md_detail"; added = (1, 15, 6);
    style = RHashtable "info", [Device "md"], [];
    proc_nr = Some 301;
    optional = Some "mdadm";
    shortdesc = "obtain metadata for an MD device";
    longdesc = "\
This command exposes the output of 'mdadm -DY E<lt>mdE<gt>'.
The following fields are usually present in the returned hash.
Other fields may also be present.

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

=back" };

  { defaults with
    name = "md_stop"; added = (1, 15, 6);
    style = RErr, [Device "md"], [];
    proc_nr = Some 302;
    optional = Some "mdadm";
    shortdesc = "stop a Linux md (RAID) device";
    longdesc = "\
This command deactivates the MD array named C<md>.  The
device is stopped, but it is not destroyed or zeroed." };

  { defaults with
    name = "blkid"; added = (1, 15, 9);
    style = RHashtable "info", [Device "device"], [];
    proc_nr = Some 303;
    tests = [
      InitScratchFS, Always, TestResult (
        [["blkid"; "/dev/sdb1"]],
        "check_hash (ret, \"TYPE\", \"ext2\") == 0 && "^
          "check_hash (ret, \"USAGE\", \"filesystem\") == 0 && "^
          "check_hash (ret, \"PART_ENTRY_NUMBER\", \"1\") == 0 && "^
          "check_hash (ret, \"PART_ENTRY_TYPE\", \"0x83\") == 0 && "^
          "check_hash (ret, \"PART_ENTRY_OFFSET\", \"128\") == 0 && "^
          "check_hash (ret, \"PART_ENTRY_SIZE\", \"4194049\") == 0"), [];
    ];
    shortdesc = "print block device attributes";
    longdesc = "\
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

=back" };

  { defaults with
    name = "e2fsck"; added = (1, 15, 17);
    style = RErr, [Device "device"], [OBool "correct"; OBool "forceall"];
    proc_nr = Some 304;
    shortdesc = "check an ext2/ext3 filesystem";
    longdesc = "\
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

=back" };

  { defaults with
    name = "llz"; added = (1, 17, 6);
    style = RString "listing", [Pathname "directory"], [];
    proc_nr = Some 305;
    shortdesc = "list the files in a directory (long format with SELinux contexts)";
    longdesc = "\
List the files in F<directory> in the format of 'ls -laZ'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string." };

  { defaults with
    name = "wipefs"; added = (1, 17, 6);
    style = RErr, [Device "device"], [];
    proc_nr = Some 306;
    optional = Some "wipefs";
    tests = [
      InitBasicFSonLVM, Always, TestRun (
        [["umount"; "/dev/VG/LV"; ""; ""];
         ["wipefs"; "/dev/VG/LV"]]), []
    ];
    shortdesc = "wipe a filesystem signature from a device";
    longdesc = "\
This command erases filesystem or RAID signatures from
the specified C<device> to make the filesystem invisible to libblkid.

This does not erase the filesystem itself nor any other data from the
C<device>.

Compare with C<guestfs_zero> which zeroes the first few blocks of a
device." };

  { defaults with
    name = "ntfsfix"; added = (1, 17, 9);
    style = RErr, [Device "device"], [OBool "clearbadsectors"];
    proc_nr = Some 307;
    optional = Some "ntfs3g";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs"; "ntfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["ntfsfix"; "/dev/sda1"; "false"]]), []
    ];
    shortdesc = "fix common errors and force Windows to check NTFS";
    longdesc = "\
This command repairs some fundamental NTFS inconsistencies,
resets the NTFS journal file, and schedules an NTFS consistency
check for the first boot into Windows.

This is I<not> an equivalent of Windows C<chkdsk>.  It does I<not>
scan the filesystem for inconsistencies.

The optional C<clearbadsectors> flag clears the list of bad sectors.
This is useful after cloning a disk with bad sectors to a new disk." };

  { defaults with
    name = "ntfsclone_out"; added = (1, 17, 9);
    style = RErr, [Device "device"; FileOut "backupfile"], [OBool "metadataonly"; OBool "rescue"; OBool "ignorefscheck"; OBool "preservetimestamps"; OBool "force"];
    proc_nr = Some 308;
    optional = Some "ntfs3g"; cancellable = true;
    test_excuse = "tested in tests/ntfsclone";
    shortdesc = "save NTFS to backup file";
    longdesc = "\
Stream the NTFS filesystem C<device> to the local file
C<backupfile>.  The format used for the backup file is a
special format used by the L<ntfsclone(8)> tool.

If the optional C<metadataonly> flag is true, then I<only> the
metadata is saved, losing all the user data (this is useful
for diagnosing some filesystem problems).

The optional C<rescue>, C<ignorefscheck>, C<preservetimestamps>
and C<force> flags have precise meanings detailed in the
L<ntfsclone(8)> man page.

Use C<guestfs_ntfsclone_in> to restore the file back to a
libguestfs device." };

  { defaults with
    name = "ntfsclone_in"; added = (1, 17, 9);
    style = RErr, [FileIn "backupfile"; Device "device"], [];
    proc_nr = Some 309;
    optional = Some "ntfs3g"; cancellable = true;
    test_excuse = "tested in tests/ntfsclone";
    shortdesc = "restore NTFS from backup file";
    longdesc = "\
Restore the C<backupfile> (from a previous call to
C<guestfs_ntfsclone_out>) to C<device>, overwriting
any existing contents of this device." };

  { defaults with
    name = "set_label"; added = (1, 17, 9);
    style = RErr, [Mountable "mountable"; String "label"], [];
    proc_nr = Some 310;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["set_label"; "/dev/sda1"; "testlabel"];
         ["vfs_label"; "/dev/sda1"]], "testlabel"), [];
      InitPartition, IfAvailable "ntfs3g", TestResultString (
        [["mkfs"; "ntfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["set_label"; "/dev/sda1"; "testlabel2"];
         ["vfs_label"; "/dev/sda1"]], "testlabel2"), [];
      InitPartition, Always, TestLastFail (
        [["zero"; "/dev/sda1"];
         ["set_label"; "/dev/sda1"; "testlabel2"]]), []
    ];
    shortdesc = "set filesystem label";
    longdesc = "\
Set the filesystem label on C<mountable> to C<label>.

Only some filesystem types support labels, and libguestfs supports
setting labels on only a subset of these.

=over 4

=item ext2, ext3, ext4

Labels are limited to 16 bytes.

=item NTFS

Labels are limited to 128 unicode characters.

=item XFS

The label is limited to 12 bytes.  The filesystem must not
be mounted when trying to set the label.

=item btrfs

The label is limited to 255 bytes and some characters are
not allowed.  Setting the label on a btrfs subvolume will set the
label on its parent filesystem.  The filesystem must not be mounted
when trying to set the label.

=item fat

The label is limited to 11 bytes.

=back

If there is no support for changing the label
for the type of the specified filesystem,
set_label will fail and set errno as ENOTSUP.

To read the label on a filesystem, call C<guestfs_vfs_label>." };

  { defaults with
    name = "zero_free_space"; added = (1, 17, 18);
    style = RErr, [Pathname "directory"], [];
    proc_nr = Some 311;
    progress = true;
    tests = [
      InitScratchFS, Always, TestRun (
        [["zero_free_space"; "/"]]), []
    ];
    shortdesc = "zero free space in a filesystem";
    longdesc = "\
Zero the free space in the filesystem mounted on F<directory>.
The filesystem must be mounted read-write.

The filesystem contents are not affected, but any free space
in the filesystem is freed.

Free space is not \"trimmed\".  You may want to call
C<guestfs_fstrim> either as an alternative to this,
or after calling this, depending on your requirements." };

  { defaults with
    name = "lvcreate_free"; added = (1, 17, 18);
    style = RErr, [String "logvol"; String "volgroup"; Int "percent"], [];
    proc_nr = Some 312;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate_free"; "LV1"; "VG"; "50"];
         ["lvcreate_free"; "LV2"; "VG"; "50"];
         ["lvcreate_free"; "LV3"; "VG"; "50"];
         ["lvcreate_free"; "LV4"; "VG"; "100"];
         ["lvs"]],
        "is_string_list (ret, 4, \"/dev/VG/LV1\", \"/dev/VG/LV2\", \"/dev/VG/LV3\", \"/dev/VG/LV4\")"), []
    ];
    shortdesc = "create an LVM logical volume in % remaining free space";
    longdesc = "\
Create an LVM logical volume called F</dev/volgroup/logvol>,
using approximately C<percent> % of the free space remaining
in the volume group.  Most usefully, when C<percent> is C<100>
this will create the largest possible LV." };

  { defaults with
    name = "isoinfo_device"; added = (1, 17, 19);
    style = RStruct ("isodata", "isoinfo"), [Device "device"], [];
    proc_nr = Some 313;
    tests = [
      InitNone, Always, TestResult (
        [["isoinfo_device"; "/dev/sdd"]],
        "STREQ (ret->iso_system_id, GUESTFS_ISO_SYSTEM_ID) && "^
          "STREQ (ret->iso_volume_id, \"CDROM\") && "^
          "STREQ (ret->iso_volume_set_id, \"\") && "^
          "ret->iso_volume_set_size == 1 && "^
          "ret->iso_volume_sequence_number == 1 && "^
          "ret->iso_logical_block_size == 2048"), []
    ];
    shortdesc = "get ISO information from primary volume descriptor of device";
    longdesc = "\
C<device> is an ISO device.  This returns a struct of information
read from the primary volume descriptor (the ISO equivalent of the
superblock) of the device.

Usually it is more efficient to use the L<isoinfo(1)> command
with the I<-d> option on the host to analyze ISO files,
instead of going through libguestfs.

For information on the primary volume descriptor fields, see
L<http://wiki.osdev.org/ISO_9660#The_Primary_Volume_Descriptor>" };

  { defaults with
    name = "isoinfo"; added = (1, 17, 19);
    style = RStruct ("isodata", "isoinfo"), [Pathname "isofile"], [];
    proc_nr = Some 314;
    shortdesc = "get ISO information from primary volume descriptor of ISO file";
    longdesc = "\
This is the same as C<guestfs_isoinfo_device> except that it
works for an ISO file located inside some other mounted filesystem.
Note that in the common case where you have added an ISO file
as a libguestfs device, you would I<not> call this.  Instead
you would call C<guestfs_isoinfo_device>." };

  { defaults with
    name = "vgmeta"; added = (1, 17, 20);
    style = RBufferOut "metadata", [String "vgname"], [];
    proc_nr = Some 315;
    optional = Some "lvm2";
    shortdesc = "get volume group metadata";
    longdesc = "\
C<vgname> is an LVM volume group.  This command examines the
volume group and returns its metadata.

Note that the metadata is an internal structure used by LVM,
subject to change at any time, and is provided for information only." };

  { defaults with
    name = "md_stat"; added = (1, 17, 21);
    style = RStructList ("devices", "mdstat"), [Device "md"], [];
    proc_nr = Some 316;
    optional = Some "mdadm";
    shortdesc = "get underlying devices from an MD device";
    longdesc = "\
This call returns a list of the underlying devices which make
up the single software RAID array device C<md>.

To get a list of software RAID devices, call C<guestfs_list_md_devices>.

Each structure returned corresponds to one device along with
additional status information:

=over 4

=item C<mdstat_device>

The name of the underlying device.

=item C<mdstat_index>

The index of this device within the array.

=item C<mdstat_flags>

Flags associated with this device.  This is a string containing
(in no specific order) zero or more of the following flags:

=over 4

=item C<W>

write-mostly

=item C<F>

device is faulty

=item C<S>

device is a RAID spare

=item C<R>

replacement

=back

=back" };

  { defaults with
    name = "mkfs_btrfs"; added = (1, 17, 25);
    style = RErr, [DeviceList "devices"], [OInt64 "allocstart"; OInt64 "bytecount"; OString "datatype"; OInt "leafsize"; OString "label"; OString "metadata"; OInt "nodesize"; OInt "sectorsize"];
    proc_nr = Some 317;
    optional = Some "btrfs";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs_btrfs"; "/dev/sda1"; "0"; "268435456"; "single"; ""; "test"; "single"; "65536"; "512"]]), []
    ];
    shortdesc = "create a btrfs filesystem";
    longdesc = "\
Create a btrfs filesystem, allowing all configurables to be set.
For more information on the optional arguments, see L<mkfs.btrfs(8)>.

Since btrfs filesystems can span multiple devices, this takes a
non-empty list of devices.

To create general filesystems, use C<guestfs_mkfs>." };

  { defaults with
    name = "get_e2attrs"; added = (1, 17, 31);
    style = RString "attrs", [Pathname "file"], [];
    proc_nr = Some 318;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["touch"; "/e2attrs1"];
         ["get_e2attrs"; "/e2attrs1"]], ""), [];
      InitScratchFS, Always, TestResultString (
        [["touch"; "/e2attrs2"];
         ["set_e2attrs"; "/e2attrs2"; "is"; "false"];
         ["get_e2attrs"; "/e2attrs2"]], "is"), [];
      InitScratchFS, Always, TestResultString (
        [["touch"; "/e2attrs3"];
         ["set_e2attrs"; "/e2attrs3"; "is"; "false"];
         ["set_e2attrs"; "/e2attrs3"; "i"; "true"];
         ["get_e2attrs"; "/e2attrs3"]], "s"), [];
      InitScratchFS, Always, TestResultString (
        [["touch"; "/e2attrs4"];
         ["set_e2attrs"; "/e2attrs4"; "adst"; "false"];
         ["set_e2attrs"; "/e2attrs4"; "iS"; "false"];
         ["set_e2attrs"; "/e2attrs4"; "i"; "true"];
         ["set_e2attrs"; "/e2attrs4"; "ad"; "true"];
         ["set_e2attrs"; "/e2attrs4"; ""; "false"];
         ["set_e2attrs"; "/e2attrs4"; ""; "true"];
         ["get_e2attrs"; "/e2attrs4"]], "Sst"), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/e2attrs5"];
         ["set_e2attrs"; "/e2attrs5"; "R"; "false"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/e2attrs6"];
         ["set_e2attrs"; "/e2attrs6"; "v"; "false"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/e2attrs7"];
         ["set_e2attrs"; "/e2attrs7"; "aa"; "false"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/e2attrs8"];
         ["set_e2attrs"; "/e2attrs8"; "BabcdB"; "false"]]), []
    ];
    shortdesc = "get ext2 file attributes of a file";
    longdesc = "\
This returns the file attributes associated with F<file>.

The attributes are a set of bits associated with each
inode which affect the behaviour of the file.  The attributes
are returned as a string of letters (described below).  The
string may be empty, indicating that no file attributes are
set for this file.

These attributes are only present when the file is located on
an ext2/3/4 filesystem.  Using this call on other filesystem
types will result in an error.

The characters (file attributes) in the returned string are
currently:

=over 4

=item 'A'

When the file is accessed, its atime is not modified.

=item 'a'

The file is append-only.

=item 'c'

The file is compressed on-disk.

=item 'D'

(Directories only.)  Changes to this directory are written
synchronously to disk.

=item 'd'

The file is not a candidate for backup (see L<dump(8)>).

=item 'E'

The file has compression errors.

=item 'e'

The file is using extents.

=item 'h'

The file is storing its blocks in units of the filesystem blocksize
instead of sectors.

=item 'I'

(Directories only.)  The directory is using hashed trees.

=item 'i'

The file is immutable.  It cannot be modified, deleted or renamed.
No link can be created to this file.

=item 'j'

The file is data-journaled.

=item 's'

When the file is deleted, all its blocks will be zeroed.

=item 'S'

Changes to this file are written synchronously to disk.

=item 'T'

(Directories only.)  This is a hint to the block allocator
that subdirectories contained in this directory should be
spread across blocks.  If not present, the block allocator
will try to group subdirectories together.

=item 't'

For a file, this disables tail-merging.
(Not used by upstream implementations of ext2.)

=item 'u'

When the file is deleted, its blocks will be saved, allowing
the file to be undeleted.

=item 'X'

The raw contents of the compressed file may be accessed.

=item 'Z'

The compressed file is dirty.

=back

More file attributes may be added to this list later.  Not all
file attributes may be set for all kinds of files.  For
detailed information, consult the L<chattr(1)> man page.

See also C<guestfs_set_e2attrs>.

Don't confuse these attributes with extended attributes
(see C<guestfs_getxattr>)." };

  { defaults with
    name = "set_e2attrs"; added = (1, 17, 31);
    style = RErr, [Pathname "file"; String "attrs"], [OBool "clear"];
    proc_nr = Some 319;
    shortdesc = "set ext2 file attributes of a file";
    longdesc = "\
This sets or clears the file attributes C<attrs>
associated with the inode F<file>.

C<attrs> is a string of characters representing
file attributes.  See C<guestfs_get_e2attrs> for a list of
possible attributes.  Not all attributes can be changed.

If optional boolean C<clear> is not present or false, then
the C<attrs> listed are set in the inode.

If C<clear> is true, then the C<attrs> listed are cleared
in the inode.

In both cases, other attributes not present in the C<attrs>
string are left unchanged.

These attributes are only present when the file is located on
an ext2/3/4 filesystem.  Using this call on other filesystem
types will result in an error." };

  { defaults with
    name = "get_e2generation"; added = (1, 17, 31);
    style = RInt64 "generation", [Pathname "file"], [];
    proc_nr = Some 320;
    tests = [
      InitScratchFS, Always, TestResult (
        [["touch"; "/e2generation"];
         ["set_e2generation"; "/e2generation"; "123456"];
         ["get_e2generation"; "/e2generation"]], "ret == 123456"), []
    ];
    shortdesc = "get ext2 file generation of a file";
    longdesc = "\
This returns the ext2 file generation of a file.  The generation
(which used to be called the \"version\") is a number associated
with an inode.  This is most commonly used by NFS servers.

The generation is only present when the file is located on
an ext2/3/4 filesystem.  Using this call on other filesystem
types will result in an error.

See C<guestfs_set_e2generation>." };

  { defaults with
    name = "set_e2generation"; added = (1, 17, 31);
    style = RErr, [Pathname "file"; Int64 "generation"], [];
    proc_nr = Some 321;
    shortdesc = "set ext2 file generation of a file";
    longdesc = "\
This sets the ext2 file generation of a file.

See C<guestfs_get_e2generation>." };

  { defaults with
    name = "btrfs_subvolume_snapshot"; added = (1, 17, 35);
    style = RErr, [Pathname "source"; Pathname "dest"], [OBool "ro"; OString "qgroupid"];
    proc_nr = Some 322;
    once_had_no_optargs = true;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeSnapshot";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["mkdir"; "/dir"];
         ["btrfs_subvolume_create"; "/test1"; "NOARG"];
         ["btrfs_subvolume_create"; "/test2"; "NOARG"];
         ["btrfs_subvolume_create"; "/dir/test3"; "NOARG"];
         ["btrfs_subvolume_snapshot"; "/dir/test3"; "/dir/test5"; "true"; "NOARG"];
         ["btrfs_subvolume_snapshot"; "/dir/test3"; "/dir/test6"; ""; "0/1000"]]), []
    ];
    shortdesc = "create a btrfs snapshot";
    longdesc = "\
Create a snapshot of the btrfs subvolume C<source>.
The C<dest> argument is the destination directory and the name
of the snapshot, in the form F</path/to/dest/name>. By default
the newly created snapshot is writable, if the value of optional
parameter C<ro> is true, then a readonly snapshot is created. The
optional parameter C<qgroupid> represents the qgroup which the
newly created snapshot will be added to." };

  { defaults with
    name = "btrfs_subvolume_delete"; added = (1, 17, 35);
    style = RErr, [Pathname "subvolume"], [];
    proc_nr = Some 323;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeDelete";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_subvolume_create"; "/test1"; "NOARG"];
         ["btrfs_subvolume_delete"; "/test1"]]), []
    ];
    shortdesc = "delete a btrfs subvolume or snapshot";
    longdesc = "\
Delete the named btrfs subvolume or snapshot." };

  { defaults with
    name = "btrfs_subvolume_create"; added = (1, 17, 35);
    style = RErr, [Pathname "dest"], [OString "qgroupid"];
    proc_nr = Some 324;
    once_had_no_optargs = true;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeCreate";
    shortdesc = "create a btrfs subvolume";
    longdesc = "\
Create a btrfs subvolume.  The C<dest> argument is the destination
directory and the name of the subvolume, in the form F</path/to/dest/name>.
The optional parameter C<qgroupid> represents the qgroup which the newly
created subvolume will be added to." };

  { defaults with
    name = "btrfs_subvolume_list"; added = (1, 17, 35);
    style = RStructList ("subvolumes", "btrfssubvolume"), [Mountable_or_Path "fs"], [];
    proc_nr = Some 325;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeList";
    test_excuse = "tested in tests/btrfs";
    shortdesc = "list btrfs snapshots and subvolumes";
    longdesc = "\
List the btrfs snapshots and subvolumes of the btrfs filesystem
which is mounted at C<fs>." };

  { defaults with
    name = "btrfs_subvolume_set_default"; added = (1, 17, 35);
    style = RErr, [Int64 "id"; Pathname "fs"], [];
    proc_nr = Some 326;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeSetDefault";
    test_excuse = "tested in tests/btrfs";
    shortdesc = "set default btrfs subvolume";
    longdesc = "\
Set the subvolume of the btrfs filesystem C<fs> which will
be mounted by default.  See C<guestfs_btrfs_subvolume_list> to
get a list of subvolumes." };

  { defaults with
    name = "btrfs_filesystem_sync"; added = (1, 17, 35);
    style = RErr, [Pathname "fs"], [];
    proc_nr = Some 327;
    optional = Some "btrfs"; camel_name = "BTRFSFilesystemSync";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_subvolume_create"; "/test1"; "NOARG"];
         ["btrfs_filesystem_sync"; "/test1"];
         ["btrfs_filesystem_balance"; "/test1"]]), []
    ];
    shortdesc = "sync a btrfs filesystem";
    longdesc = "\
Force sync on the btrfs filesystem mounted at C<fs>." };

  { defaults with
    name = "btrfs_filesystem_balance"; added = (1, 17, 35);
    style = RErr, [Pathname "fs"], [];
    fish_alias = ["btrfs-balance"];
    proc_nr = Some 328;
    optional = Some "btrfs"; camel_name = "BTRFSFilesystemBalance";
    shortdesc = "balance a btrfs filesystem";
    longdesc = "\
Balance the chunks in the btrfs filesystem mounted at C<fs>
across the underlying devices." };

  { defaults with
    name = "btrfs_device_add"; added = (1, 17, 35);
    style = RErr, [DeviceList "devices"; Pathname "fs"], [];
    proc_nr = Some 329;
    optional = Some "btrfs"; camel_name = "BTRFSDeviceAdd";
    test_excuse = "test disk isn't large enough to test this thoroughly, so there is an external test in 'tests/btrfs' directory";
    shortdesc = "add devices to a btrfs filesystem";
    longdesc = "\
Add the list of device(s) in C<devices> to the btrfs filesystem
mounted at C<fs>.  If C<devices> is an empty list, this does nothing." };

  { defaults with
    name = "btrfs_device_delete"; added = (1, 17, 35);
    style = RErr, [DeviceList "devices"; Pathname "fs"], [];
    proc_nr = Some 330;
    optional = Some "btrfs"; camel_name = "BTRFSDeviceDelete";
    test_excuse = "test disk isn't large enough to test this thoroughly, so there is an external test in 'tests/btrfs' directory.";
    shortdesc = "remove devices from a btrfs filesystem";
    longdesc = "\
Remove the C<devices> from the btrfs filesystem mounted at C<fs>.
If C<devices> is an empty list, this does nothing." };

  { defaults with
    name = "btrfs_set_seeding"; added = (1, 17, 43);
    style = RErr, [Device "device"; Bool "seeding"], [];
    proc_nr = Some 331;
    optional = Some "btrfs";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_set_seeding"; "/dev/sda1"; "true"];
         ["btrfs_set_seeding"; "/dev/sda1"; "false"]]), []
    ];
    shortdesc = "enable or disable the seeding feature of device";
    longdesc = "\
Enable or disable the seeding feature of a device that contains
a btrfs filesystem." };

  { defaults with
    name = "btrfs_fsck"; added = (1, 17, 43);
    style = RErr, [Device "device"], [OInt64 "superblock"; OBool "repair"];
    proc_nr = Some 332;
    optional = Some "btrfs";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_fsck"; "/dev/sda1"; ""; ""]]), []
    ];
    shortdesc = "check a btrfs filesystem";
    longdesc = "\
Used to check a btrfs filesystem, C<device> is the device file where the
filesystem is stored." };

  { defaults with
    name = "filesystem_available"; added = (1, 19, 5);
    style = RBool "fsavail", [String "filesystem"], [];
    proc_nr = Some 333;
    shortdesc = "check if filesystem is available";
    longdesc = "\
Check whether libguestfs supports the named filesystem.
The argument C<filesystem> is a filesystem name, such as
C<ext3>.

You must call C<guestfs_launch> before using this command.

This is mainly useful as a negative test.  If this returns true,
it doesn't mean that a particular filesystem can be created
or mounted, since filesystems can fail for other reasons
such as it being a later version of the filesystem,
or having incompatible features, or lacking the right
mkfs.E<lt>I<fs>E<gt> tool.

See also C<guestfs_available>, C<guestfs_feature_available>,
L<guestfs(3)/AVAILABILITY>." };

  { defaults with
    name = "fstrim"; added = (1, 19, 6);
    style = RErr, [Pathname "mountpoint"], [OInt64 "offset"; OInt64 "length"; OInt64 "minimumfreeextent"];
    proc_nr = Some 334;
    optional = Some "fstrim";
    shortdesc = "trim free space in a filesystem";
    longdesc = "\
Trim the free space in the filesystem mounted on C<mountpoint>.
The filesystem must be mounted read-write.

The filesystem contents are not affected, but any free space
in the filesystem is \"trimmed\", that is, given back to the host
device, thus making disk images more sparse, allowing unused space
in qcow2 files to be reused, etc.

This operation requires support in libguestfs, the mounted
filesystem, the host filesystem, qemu and the host kernel.
If this support isn't present it may give an error or even
appear to run but do nothing.

See also C<guestfs_zero_free_space>.  That is a slightly
different operation that turns free space in the filesystem
into zeroes.  It is valid to call C<guestfs_fstrim> either
instead of, or after calling C<guestfs_zero_free_space>." };

  { defaults with
    name = "device_index"; added = (1, 19, 7);
    style = RInt "index", [Device "device"], [];
    proc_nr = Some 335;
    tests = [
      InitEmpty, Always, TestResult (
        [["device_index"; "/dev/sda"]], "ret == 0"), []
    ];
    shortdesc = "convert device to index";
    longdesc = "\
This function takes a device name (eg. \"/dev/sdb\") and
returns the index of the device in the list of devices.

Index numbers start from 0.  The named device must exist,
for example as a string returned from C<guestfs_list_devices>.

See also C<guestfs_list_devices>, C<guestfs_part_to_dev>." };

  { defaults with
    name = "nr_devices"; added = (1, 19, 15);
    style = RInt "nrdisks", [], [];
    proc_nr = Some 336;
    tests = [
      InitEmpty, Always, TestResult (
        [["nr_devices"]], "ret == 4"), []
    ];
    shortdesc = "return number of whole block devices (disks) added";
    longdesc = "\
This returns the number of whole block devices that were
added.  This is the same as the number of devices that would
be returned if you called C<guestfs_list_devices>.

To find out the maximum number of devices that could be added,
call C<guestfs_max_disks>." };

  { defaults with
    name = "xfs_info"; added = (1, 19, 21);
    style = RStruct ("info", "xfsinfo"), [Dev_or_Path "pathordevice"], [];
    proc_nr = Some 337;
    optional = Some "xfs";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["xfs_info"; "/"]], "ret->xfs_blocksize == 4096"), []
    ];
    shortdesc = "get geometry of XFS filesystem";
    longdesc = "\
C<pathordevice> is a mounted XFS filesystem or a device containing
an XFS filesystem.  This command returns the geometry of the filesystem.

The returned struct contains geometry information.  Missing
fields are returned as C<-1> (for numeric fields) or empty
string." };

  { defaults with
    name = "pvchange_uuid"; added = (1, 19, 26);
    style = RErr, [Device "device"], [];
    proc_nr = Some 338;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["pvchange_uuid"; "/dev/sda1"]]), []
    ];
    shortdesc = "generate a new random UUID for a physical volume";
    longdesc = "\
Generate a new random UUID for the physical volume C<device>." };

  { defaults with
    name = "pvchange_uuid_all"; added = (1, 19, 26);
    style = RErr, [], [];
    proc_nr = Some 339;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["pvchange_uuid_all"]]), []
    ];
    shortdesc = "generate new random UUIDs for all physical volumes";
    longdesc = "\
Generate new random UUIDs for all physical volumes." };

  { defaults with
    name = "vgchange_uuid"; added = (1, 19, 26);
    style = RErr, [String "vg"], [];
    proc_nr = Some 340;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["vgchange_uuid"; "/dev/VG"]]), []
    ];
    shortdesc = "generate a new random UUID for a volume group";
    longdesc = "\
Generate a new random UUID for the volume group C<vg>." };

  { defaults with
    name = "vgchange_uuid_all"; added = (1, 19, 26);
    style = RErr, [], [];
    proc_nr = Some 341;
    optional = Some "lvm2";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["vgchange_uuid_all"]]), []
    ];
    shortdesc = "generate new random UUIDs for all volume groups";
    longdesc = "\
Generate new random UUIDs for all volume groups." };

  { defaults with
    name = "utsname"; added = (1, 19, 27);
    style = RStruct ("uts", "utsname"), [], [];
    proc_nr = Some 342;
    tests = [
      InitEmpty, Always, TestRun (
        [["utsname"]]), []
    ];
    shortdesc = "appliance kernel version";
    longdesc = "\
This returns the kernel version of the appliance, where this is
available.  This information is only useful for debugging.  Nothing
in the returned structure is defined by the API." };

  { defaults with
    name = "xfs_growfs"; added = (1, 19, 28);
    style = RErr, [Pathname "path"], [OBool "datasec"; OBool "logsec"; OBool "rtsec"; OInt64 "datasize"; OInt64 "logsize"; OInt64 "rtsize"; OInt64 "rtextsize"; OInt "maxpct"];
    proc_nr = Some 343;
    optional = Some "xfs";
    tests = [
      InitEmpty, Always, TestResult (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["pvcreate"; "/dev/sda1"];
         ["vgcreate"; "VG"; "/dev/sda1"];
         ["lvcreate"; "LV"; "VG"; "40"];
         ["mkfs"; "xfs"; "/dev/VG/LV"; ""; "NOARG"; ""; ""; "NOARG"];
         ["lvresize"; "/dev/VG/LV"; "80"];
         ["mount"; "/dev/VG/LV"; "/"];
         ["xfs_growfs"; "/"; "true"; "false"; "false"; ""; ""; ""; ""; ""];
         ["xfs_info"; "/"]], "ret->xfs_blocksize == 4096"), [];
    ];
    shortdesc = "expand an existing XFS filesystem";
    longdesc = "\
Grow the XFS filesystem mounted at C<path>.

The returned struct contains geometry information.  Missing
fields are returned as C<-1> (for numeric fields) or empty
string." };

  { defaults with
    name = "rsync"; added = (1, 19, 29);
    style = RErr, [Pathname "src"; Pathname "dest"], [OBool "archive"; OBool "deletedest"];
    proc_nr = Some 344;
    optional = Some "rsync";
    test_excuse = "tests are in tests/rsync";
    shortdesc = "synchronize the contents of two directories";
    longdesc = "\
This call may be used to copy or synchronize two directories
under the same libguestfs handle.  This uses the L<rsync(1)>
program which uses a fast algorithm that avoids copying files
unnecessarily.

C<src> and C<dest> are the source and destination directories.
Files are copied from C<src> to C<dest>.

The optional arguments are:

=over 4

=item C<archive>

Turns on archive mode.  This is the same as passing the
I<--archive> flag to C<rsync>.

=item C<deletedest>

Delete files at the destination that do not exist at the source.

=back" };

  { defaults with
    name = "rsync_in"; added = (1, 19, 29);
    style = RErr, [String "remote"; Pathname "dest"], [OBool "archive"; OBool "deletedest"];
    proc_nr = Some 345;
    optional = Some "rsync";
    test_excuse = "tests are in tests/rsync";
    shortdesc = "synchronize host or remote filesystem with filesystem";
    longdesc = "\
This call may be used to copy or synchronize the filesystem
on the host or on a remote computer with the filesystem
within libguestfs.  This uses the L<rsync(1)> program
which uses a fast algorithm that avoids copying files unnecessarily.

This call only works if the network is enabled.  See
C<guestfs_set_network> or the I<--network> option to
various tools like L<guestfish(1)>.

Files are copied from the remote server and directory
specified by C<remote> to the destination directory C<dest>.

The format of the remote server string is defined by L<rsync(1)>.
Note that there is no way to supply a password or passphrase
so the target must be set up not to require one.

The optional arguments are the same as those of C<guestfs_rsync>." };

  { defaults with
    name = "rsync_out"; added = (1, 19, 29);
    style = RErr, [Pathname "src"; String "remote"], [OBool "archive"; OBool "deletedest"];
    proc_nr = Some 346;
    optional = Some "rsync";
    test_excuse = "tests are in tests/rsync";
    shortdesc = "synchronize filesystem with host or remote filesystem";
    longdesc = "\
This call may be used to copy or synchronize the filesystem within
libguestfs with a filesystem on the host or on a remote computer.
This uses the L<rsync(1)> program which uses a fast algorithm that
avoids copying files unnecessarily.

This call only works if the network is enabled.  See
C<guestfs_set_network> or the I<--network> option to
various tools like L<guestfish(1)>.

Files are copied from the source directory C<src> to the
remote server and directory specified by C<remote>.

The format of the remote server string is defined by L<rsync(1)>.
Note that there is no way to supply a password or passphrase
so the target must be set up not to require one.

The optional arguments are the same as those of C<guestfs_rsync>.

Globbing does not happen on the C<src> parameter.  In programs
which use the API directly you have to expand wildcards yourself
(see C<guestfs_glob_expand>).  In guestfish you can use the C<glob>
command (see L<guestfish(1)/glob>), for example:

 ><fs> glob rsync-out /* rsync://remote/" };

  { defaults with
    name = "ls0"; added = (1, 19, 32);
    style = RErr, [Pathname "dir"; FileOut "filenames"], [];
    proc_nr = Some 347;
    shortdesc = "get list of files in a directory";
    longdesc = "\
This specialized command is used to get a listing of
the filenames in the directory C<dir>.  The list of filenames
is written to the local file F<filenames> (on the host).

In the output file, the filenames are separated by C<\\0> characters.

C<.> and C<..> are not returned.  The filenames are not sorted." };

  { defaults with
    name = "fill_dir"; added = (1, 19, 32);
    style = RErr, [Pathname "dir"; Int "nr"], [];
    proc_nr = Some 348;
    shortdesc = "fill a directory with empty files";
    longdesc = "\
This function, useful for testing filesystems, creates C<nr>
empty files in the directory C<dir> with names C<00000000>
through C<nr-1> (ie. each file name is 8 digits long padded
with zeroes)." };

  { defaults with
    name = "xfs_admin"; added = (1, 19, 33);
    style = RErr, [Device "device"], [OBool "extunwritten"; OBool "imgfile"; OBool "v2log"; OBool "projid32bit"; OBool "lazycounter"; OString "label"; OString "uuid"];
    proc_nr = Some 349;
    optional = Some "xfs";
    tests =
      (let uuid = uuidgen () in [
        InitEmpty, Always, TestResult (
          [["part_disk"; "/dev/sda"; "mbr"];
           ["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
           ["xfs_admin"; "/dev/sda1"; ""; ""; ""; ""; "false"; "NOARG"; "NOARG"];
           ["mount"; "/dev/sda1"; "/"];
           ["xfs_info"; "/"]], "ret->xfs_lazycount == 0"), [];
        InitEmpty, Always, TestResultString (
          [["part_disk"; "/dev/sda"; "mbr"];
           ["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
           ["xfs_admin"; "/dev/sda1"; ""; ""; ""; ""; ""; "NOARG"; uuid];
           ["vfs_uuid"; "/dev/sda1"]], uuid), [];
        InitEmpty, Always, TestResultString (
          [["part_disk"; "/dev/sda"; "mbr"];
           ["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
           ["xfs_admin"; "/dev/sda1"; ""; ""; ""; ""; ""; "LBL-TEST"; "NOARG"];
           ["vfs_label"; "/dev/sda1"]], "LBL-TEST"), [];
      ]);
    shortdesc = "change parameters of an XFS filesystem";
    longdesc = "\
Change the parameters of the XFS filesystem on C<device>.

Devices that are mounted cannot be modified.
Administrators must unmount filesystems before this call
can modify parameters.

Some of the parameters of a mounted filesystem can be examined
and modified using the C<guestfs_xfs_info> and
C<guestfs_xfs_growfs> calls." };

  { defaults with
    name = "hivex_open"; added = (1, 19, 35);
    style = RErr, [Pathname "filename"], [OBool "verbose"; OBool "debug"; OBool "write"];
    proc_nr = Some 350;
    optional = Some "hivex";
    tests = [
      InitScratchFS, Always, TestRun (
        [["upload"; "$srcdir/../../test-data/files/minimal"; "/hivex_open"];
         ["hivex_open"; "/hivex_open"; ""; ""; "false"];
         ["hivex_root"]; (* in this hive, it returns 0x1020 *)
         ["hivex_node_name"; "0x1020"];
         ["hivex_node_children"; "0x1020"];
         ["hivex_node_values"; "0x1020"]]), [["hivex_close"]]
    ];
    shortdesc = "open a Windows Registry hive file";
    longdesc = "\
Open the Windows Registry hive file named F<filename>.
If there was any previous hivex handle associated with this
guestfs session, then it is closed.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_close"; added = (1, 19, 35);
    style = RErr, [], [];
    proc_nr = Some 351;
    optional = Some "hivex";
    shortdesc = "close the current hivex handle";
    longdesc = "\
Close the current hivex handle.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_root"; added = (1, 19, 35);
    style = RInt64 "nodeh", [], [];
    proc_nr = Some 352;
    optional = Some "hivex";
    shortdesc = "return the root node of the hive";
    longdesc = "\
Return the root node of the hive.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_name"; added = (1, 19, 35);
    style = RString "name", [Int64 "nodeh"], [];
    proc_nr = Some 353;
    optional = Some "hivex";
    shortdesc = "return the name of the node";
    longdesc = "\
Return the name of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_children"; added = (1, 19, 35);
    style = RStructList ("nodehs", "hivex_node"), [Int64 "nodeh"], [];
    proc_nr = Some 354;
    optional = Some "hivex";
    shortdesc = "return list of nodes which are subkeys of node";
    longdesc = "\
Return the list of nodes which are subkeys of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_get_child"; added = (1, 19, 35);
    style = RInt64 "child", [Int64 "nodeh"; String "name"], [];
    proc_nr = Some 355;
    optional = Some "hivex";
    shortdesc = "return the named child of node";
    longdesc = "\
Return the child of C<nodeh> with the name C<name>, if it exists.
This can return C<0> meaning the name was not found.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_parent"; added = (1, 19, 35);
    style = RInt64 "parent", [Int64 "nodeh"], [];
    proc_nr = Some 356;
    optional = Some "hivex";
    shortdesc = "return the parent of node";
    longdesc = "\
Return the parent node of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_values"; added = (1, 19, 35);
    style = RStructList ("valuehs", "hivex_value"), [Int64 "nodeh"], [];
    proc_nr = Some 357;
    optional = Some "hivex";
    shortdesc = "return list of values attached to node";
    longdesc = "\
Return the array of (key, datatype, data) tuples attached to C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_get_value"; added = (1, 19, 35);
    style = RInt64 "valueh", [Int64 "nodeh"; String "key"], [];
    proc_nr = Some 358;
    optional = Some "hivex";
    shortdesc = "return the named value";
    longdesc = "\
Return the value attached to C<nodeh> which has the
name C<key>, if it exists.  This can return C<0> meaning
the key was not found.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_key"; added = (1, 19, 35);
    style = RString "key", [Int64 "valueh"], [];
    proc_nr = Some 359;
    optional = Some "hivex";
    shortdesc = "return the key field from the (key, datatype, data) tuple";
    longdesc = "\
Return the key (name) field of a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_type"; added = (1, 19, 35);
    style = RInt64 "datatype", [Int64 "valueh"], [];
    proc_nr = Some 360;
    optional = Some "hivex";
    shortdesc = "return the data type from the (key, datatype, data) tuple";
    longdesc = "\
Return the data type field from a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_value"; added = (1, 19, 35);
    style = RBufferOut "databuf", [Int64 "valueh"], [];
    proc_nr = Some 361;
    optional = Some "hivex";
    shortdesc = "return the data field from the (key, datatype, data) tuple";
    longdesc = "\
Return the data field of a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name.

See also: C<guestfs_hivex_value_utf8>." };

  { defaults with
    name = "hivex_commit"; added = (1, 19, 35);
    style = RErr, [OptString "filename"], [];
    proc_nr = Some 362;
    optional = Some "hivex";
    tests = [
      InitScratchFS, Always, TestRun (
        [["upload"; "$srcdir/../../test-data/files/minimal"; "/hivex_commit1"];
         ["hivex_open"; "/hivex_commit1"; ""; ""; "true"];
         ["hivex_commit"; "NULL"]]), [["hivex_close"]];
      InitScratchFS, Always, TestResultTrue (
        [["upload"; "$srcdir/../../test-data/files/minimal"; "/hivex_commit2"];
         ["hivex_open"; "/hivex_commit2"; ""; ""; "true"];
         ["hivex_commit"; "/hivex_commit2_copy"];
         ["is_file"; "/hivex_commit2_copy"; "false"]]), [["hivex_close"]]
    ];
    shortdesc = "commit (write) changes back to the hive";
    longdesc = "\
Commit (write) changes to the hive.

If the optional F<filename> parameter is null, then the changes
are written back to the same hive that was opened.  If this is
not null then they are written to the alternate filename given
and the original hive is left untouched.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_add_child"; added = (1, 19, 35);
    style = RInt64 "nodeh", [Int64 "parent"; String "name"], [];
    proc_nr = Some 363;
    optional = Some "hivex";
    shortdesc = "add a child node";
    longdesc = "\
Add a child node to C<parent> named C<name>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_delete_child"; added = (1, 19, 35);
    style = RErr, [Int64 "nodeh"], [];
    proc_nr = Some 364;
    optional = Some "hivex";
    shortdesc = "delete a node (recursively)";
    longdesc = "\
Delete C<nodeh>, recursively if necessary.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_set_value"; added = (1, 19, 35);
    style = RErr, [Int64 "nodeh"; String "key"; Int64 "t"; BufferIn "val"], [];
    proc_nr = Some 365;
    optional = Some "hivex";
    shortdesc = "set or replace a single value in a node";
    longdesc = "\
Set or replace a single value under the node C<nodeh>.  The
C<key> is the name, C<t> is the type, and C<val> is the data.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "xfs_repair"; added = (1, 19, 36);
    style = RInt "status", [Dev_or_Path "device"], [OBool "forcelogzero"; OBool "nomodify"; OBool "noprefetch"; OBool "forcegeometry"; OInt64 "maxmem"; OInt64 "ihashsize"; OInt64 "bhashsize"; OInt64 "agstride"; OString "logdev"; OString "rtdev"];
    proc_nr = Some 366;
    optional = Some "xfs";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["xfs_repair"; "/dev/sda1"; ""; "true"; ""; ""; ""; ""; ""; ""; "NOARG"; "NOARG"]
        ]), []
    ];
    shortdesc = "repair an XFS filesystem";
    longdesc = "\
Repair corrupt or damaged XFS filesystem on C<device>.

The filesystem is specified using the C<device> argument which should be
the device name of the disk partition or volume containing the filesystem.
If given the name of a block device, C<xfs_repair> will attempt to find
the raw device associated with the specified block device and will use
the raw device instead.

Regardless, the filesystem to be repaired must be unmounted, otherwise,
the resulting filesystem may be inconsistent or corrupt.

The returned status indicates whether filesystem corruption was
detected (returns C<1>) or was not detected (returns C<0>)." };

  { defaults with
    name = "rm_f"; added = (1, 19, 42);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 367;
    tests = [
      InitScratchFS, Always, TestResultFalse
        [["mkdir"; "/rm_f"];
         ["touch"; "/rm_f/foo"];
         ["rm_f"; "/rm_f/foo"];
         ["rm_f"; "/rm_f/not_exists"];
         ["exists"; "/rm_f/foo"]], [];
      InitScratchFS, Always, TestLastFail
        [["mkdir"; "/rm_f2"];
         ["mkdir"; "/rm_f2/foo"];
         ["rm_f"; "/rm_f2/foo"]], []
    ];
    shortdesc = "remove a file ignoring errors";
    longdesc = "\
Remove the file C<path>.

If the file doesn't exist, that error is ignored.  (Other errors,
eg. I/O errors or bad paths, are not ignored)

This call cannot remove directories.
Use C<guestfs_rmdir> to remove an empty directory,
or C<guestfs_rm_rf> to remove directories recursively." };

  { defaults with
    name = "mke2fs"; added = (1, 19, 44);
    style = RErr, [Device "device"], [OInt64 "blockscount"; OInt64 "blocksize"; OInt64 "fragsize"; OInt64 "blockspergroup"; OInt64 "numberofgroups"; OInt64 "bytesperinode"; OInt64 "inodesize"; OInt64 "journalsize"; OInt64 "numberofinodes"; OInt64 "stridesize"; OInt64 "stripewidth"; OInt64 "maxonlineresize"; OInt "reservedblockspercentage"; OInt "mmpupdateinterval"; OString "journaldevice"; OString "label"; OString "lastmounteddir"; OString "creatoros"; OString "fstype"; OString "usagetype"; OString "uuid"; OBool "forcecreate"; OBool "writesbandgrouponly"; OBool "lazyitableinit"; OBool "lazyjournalinit"; OBool "testfs"; OBool "discard"; OBool "quotatype";  OBool "extent"; OBool "filetype"; OBool "flexbg"; OBool "hasjournal"; OBool "journaldev"; OBool "largefile"; OBool "quota"; OBool "resizeinode"; OBool "sparsesuper"; OBool "uninitbg"];
    proc_nr = Some 368;
    tests =
      (let uuid = uuidgen () in
       let uuid_s = "UUID=" ^ uuid in [
         InitEmpty, Always, TestResultString (
           [["part_init"; "/dev/sda"; "mbr"];
            ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
            ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
            ["mke2fs"; "/dev/sda1"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "NOARG";
             "NOARG"; "NOARG"; "NOARG"; "NOARG"; "NOARG";
             "NOARG"; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; "true"; ""; "";
             ""; ""; ""];
            ["mke2fs"; "/dev/sda2"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "/dev/sda1";
             "NOARG"; "NOARG"; "NOARG"; "ext2"; "NOARG";
             "NOARG"; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""];
            ["mount"; "/dev/sda2"; "/"];
            ["write"; "/new"; "new file contents"];
            ["cat"; "/new"]], "new file contents"), [];
         InitEmpty, Always, TestResultString (
           [["part_init"; "/dev/sda"; "mbr"];
            ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
            ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
            ["mke2fs"; "/dev/sda1"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "/dev/sda1";
             "JOURNAL"; "NOARG"; "NOARG"; "ext2"; "NOARG";
             "NOARG"; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; "true"; ""; "";
             ""; ""; ""];
            ["mke2fs"; "/dev/sda2"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "LABEL=JOURNAL";
             "JOURNAL"; "NOARG"; "NOARG"; "ext2"; "NOARG";
             "NOARG"; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""];
            ["mount"; "/dev/sda2"; "/"];
            ["write"; "/new"; "new file contents"];
            ["cat"; "/new"]], "new file contents"), [];
         InitEmpty, Always, TestResultString (
           [["part_init"; "/dev/sda"; "mbr"];
            ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
            ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
            ["mke2fs"; "/dev/sda1"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "NOARG";
             "NOARG"; "NOARG"; "NOARG"; "NOARG"; "NOARG";
             uuid; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; "true"; ""; "";
             ""; ""; ""];
            ["mke2fs"; "/dev/sda2"; ""; "4096"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; uuid_s;
             "JOURNAL"; "NOARG"; "NOARG"; "ext2"; "NOARG";
             "NOARG"; "true"; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""; ""; "";
             ""; ""; ""];
            ["mount"; "/dev/sda2"; "/"];
            ["write"; "/new"; "new file contents"];
            ["cat"; "/new"]], "new file contents"), []
       ]);
    shortdesc = "create an ext2/ext3/ext4 filesystem on device";
    (* XXX document optional args properly *)
    longdesc = "\
C<mke2fs> is used to create an ext2, ext3, or ext4 filesystem
on C<device>.

The optional C<blockscount> is the size of the filesystem in blocks.
If omitted it defaults to the size of C<device>.  Note if the
filesystem is too small to contain a journal, C<mke2fs> will
silently create an ext2 filesystem instead." };

  { defaults with
    name = "list_disk_labels"; added = (1, 19, 49);
    style = RHashtable "labels", [], [];
    proc_nr = Some 369;
    tests = [
      (* The test disks have no labels, so we can be sure there are
       * no labels.  See in tests/disk-labels/ for tests checking
       * for actual disk labels.
       *
       * Also, we make use of the assumption that RHashtable is a
       * char*[] in C, so an empty hash has just a NULL element.
       *)
      InitScratchFS, Always, TestResult (
        [["list_disk_labels"]],
        "is_string_list (ret, 0)"), [];
    ];
    shortdesc = "mapping of disk labels to devices";
    longdesc = "\
If you add drives using the optional C<label> parameter
of C<guestfs_add_drive_opts>, you can use this call to
map between disk labels, and raw block device and partition
names (like F</dev/sda> and F</dev/sda1>).

This returns a hashtable, where keys are the disk labels
(I<without> the F</dev/disk/guestfs> prefix), and the values
are the full raw block device and partition names
(eg. F</dev/sda> and F</dev/sda1>)." };

  { defaults with
    name = "internal_hot_add_drive"; added = (1, 19, 49);
    style = RErr, [String "label"], [];
    proc_nr = Some 370;
    visibility = VInternal;
    shortdesc = "internal hotplugging operation";
    longdesc = "\
This function is used internally when hotplugging drives." };

  { defaults with
    name = "internal_hot_remove_drive_precheck"; added = (1, 19, 49);
    style = RErr, [String "label"], [];
    proc_nr = Some 371;
    visibility = VInternal;
    shortdesc = "internal hotplugging operation";
    longdesc = "\
This function is used internally when hotplugging drives." };

  { defaults with
    name = "internal_hot_remove_drive"; added = (1, 19, 49);
    style = RErr, [String "label"], [];
    proc_nr = Some 372;
    visibility = VInternal;
    shortdesc = "internal hotplugging operation";
    longdesc = "\
This function is used internally when hotplugging drives." };

  { defaults with
    name = "mktemp"; added = (1, 19, 53);
    style = RString "path", [Pathname "tmpl"], [OString "suffix"];
    proc_nr = Some 373;
    tests = [
      InitScratchFS, Always, TestRun (
        [["mkdir"; "/mktemp"];
         ["mktemp"; "/mktemp/tmpXXXXXX"; "NOARG"];
         ["mktemp"; "/mktemp/tmpXXXXXX"; "suff"]]), []
    ];
    shortdesc = "create a temporary file";
    longdesc = "\
This command creates a temporary file.  The
C<tmpl> parameter should be a full pathname for the
temporary directory name with the final six characters being
\"XXXXXX\".

For example: \"/tmp/myprogXXXXXX\" or \"/Temp/myprogXXXXXX\",
the second one being suitable for Windows filesystems.

The name of the temporary file that was created
is returned.

The temporary file is created with mode 0600
and is owned by root.

The caller is responsible for deleting the temporary
file after use.

If the optional C<suffix> parameter is given, then the suffix
(eg. C<.txt>) is appended to the temporary name.

See also: C<guestfs_mkdtemp>." };

  { defaults with
    name = "mklost_and_found"; added = (1, 19, 56);
    style = RErr, [Pathname "mountpoint"], [];
    proc_nr = Some 374;
    tests = [
      InitBasicFS, Always, TestRun (
        [["rm_rf"; "/lost+found"];
         ["mklost_and_found"; "/"]]), []
    ];
    shortdesc = "make lost+found directory on an ext2/3/4 filesystem";
    longdesc = "\
Make the C<lost+found> directory, normally in the root directory
of an ext2/3/4 filesystem.  C<mountpoint> is the directory under
which we try to create the C<lost+found> directory." };

  { defaults with
    name = "acl_get_file"; added = (1, 19, 63);
    style = RString "acl", [Pathname "path"; String "acltype"], [];
    proc_nr = Some 375;
    optional = Some "acl";
    shortdesc = "get the POSIX ACL attached to a file";
    longdesc = "\
This function returns the POSIX Access Control List (ACL) attached
to C<path>.  The ACL is returned in \"long text form\" (see L<acl(5)>).

The C<acltype> parameter may be:

=over 4

=item C<access>

Return the ordinary (access) ACL for any file, directory or
other filesystem object.

=item C<default>

Return the default ACL.  Normally this only makes sense if
C<path> is a directory.

=back" };

  { defaults with
    name = "acl_set_file"; added = (1, 19, 63);
    style = RErr, [Pathname "path"; String "acltype"; String "acl"], [];
    proc_nr = Some 376;
    optional = Some "acl";
    tests = [
      InitScratchFS, Always, TestRun (
        [["touch"; "/acl_set_file_0"];
         ["acl_set_file"; "/acl_set_file_0"; "access"; "u::r-x,g::r-x,o::r-x"];
         ["acl_get_file"; "/acl_set_file_0"; "access"]]), [];
      InitScratchFS, Always, TestRun (
        [["touch"; "/acl_set_file_1"];
         ["acl_set_file"; "/acl_set_file_1"; "access"; "u::r-x,g::r-x,o::r-x,m::rwx,u:500:rw,g:600:x"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/acl_set_file_2"];
         (* m (mask) entry is required when setting user or group ACLs *)
         ["acl_set_file"; "/acl_set_file_2"; "access"; "u::r-x,g::r-x,o::r-x,u:500:rw,g:600:x"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/acl_set_file_3"];
         (* user does not exist *)
         ["acl_set_file"; "/acl_set_file_3"; "access"; "u::r-x,g::r-x,o::r-x,m::rwx,u:notauser:rw"]]), [];
      InitScratchFS, Always, TestLastFail (
        [["touch"; "/acl_set_file_4"];
         (* cannot set default on a non-directory *)
         ["acl_set_file"; "/acl_set_file_4"; "default"; "u::r-x,g::r-x,o::r-x"]]), [];
      InitScratchFS, Always, TestRun (
        [["mkdir"; "/acl_set_file_5"];
         ["acl_set_file"; "/acl_set_file_5"; "default"; "u::r-x,g::r-x,o::r-x"]]), [];
    ];
    shortdesc = "set the POSIX ACL attached to a file";
    longdesc = "\
This function sets the POSIX Access Control List (ACL) attached
to C<path>.

The C<acltype> parameter may be:

=over 4

=item C<access>

Set the ordinary (access) ACL for any file, directory or
other filesystem object.

=item C<default>

Set the default ACL.  Normally this only makes sense if
C<path> is a directory.

=back

The C<acl> parameter is the new ACL in either \"long text form\"
or \"short text form\" (see L<acl(5)>).  The new ACL completely
replaces any previous ACL on the file.  The ACL must contain the
full Unix permissions (eg. C<u::rwx,g::rx,o::rx>).

If you are specifying individual users or groups, then the
mask field is also required (eg. C<m::rwx>), followed by the
C<u:I<ID>:...> and/or C<g:I<ID>:...> field(s).  A full ACL
string might therefore look like this:

 u::rwx,g::rwx,o::rwx,m::rwx,u:500:rwx,g:500:rwx
 \\ Unix permissions / \\mask/ \\      ACL        /

You should use numeric UIDs and GIDs.  To map usernames and
groupnames to the correct numeric ID in the context of the
guest, use the Augeas functions (see C<guestfs_aug_init>)." };

  { defaults with
    name = "acl_delete_def_file"; added = (1, 19, 63);
    style = RErr, [Pathname "dir"], [];
    proc_nr = Some 377;
    optional = Some "acl";
    tests = [
      (* Documentation for libacl says this should fail, but it doesn't.
       * Therefore disable this test.
       *)
      InitScratchFS, Disabled, TestLastFail (
        [["touch"; "/acl_delete_def_file_0"];
         ["acl_delete_def_file"; "/acl_delete_def_file_0"]]), [];
      InitScratchFS, Always, TestRun (
        [["mkdir"; "/acl_delete_def_file_1"];
         ["acl_set_file"; "/acl_delete_def_file_1"; "default"; "user::r-x,group::r-x,other::r-x"];
         ["acl_delete_def_file"; "/acl_delete_def_file_1"]]), [];
    ];
    shortdesc = "delete the default POSIX ACL of a directory";
    longdesc = "\
This function deletes the default POSIX Access Control List (ACL)
attached to directory C<dir>." };

  { defaults with
    name = "cap_get_file"; added = (1, 19, 63);
    style = RString "cap", [Pathname "path"], [];
    proc_nr = Some 378;
    optional = Some "linuxcaps";
    shortdesc = "get the Linux capabilities attached to a file";
    longdesc = "\
This function returns the Linux capabilities attached to C<path>.
The capabilities set is returned in text form (see L<cap_to_text(3)>).

If no capabilities are attached to a file, an empty string is returned." };

  { defaults with
    name = "cap_set_file"; added = (1, 19, 63);
    style = RErr, [Pathname "path"; String "cap"], [];
    proc_nr = Some 379;
    optional = Some "linuxcaps";
    tests = [
      InitScratchFS, Always, TestResultString (
        [["touch"; "/cap_set_file_0"];
         ["cap_set_file"; "/cap_set_file_0"; "cap_chown=p cap_chown+e"];
         ["cap_get_file"; "/cap_set_file_0"]], "= cap_chown+ep"), [];
    ];
    shortdesc = "set the Linux capabilities attached to a file";
    longdesc = "\
This function sets the Linux capabilities attached to C<path>.
The capabilities set C<cap> should be passed in text form
(see L<cap_from_text(3)>)." };

  { defaults with
    name = "list_ldm_volumes"; added = (1, 20, 0);
    style = RStringList "devices", [], [];
    proc_nr = Some 380;
    optional = Some "ldm";
    shortdesc = "list all Windows dynamic disk volumes";
    longdesc = "\
This function returns all Windows dynamic disk volumes
that were found at launch time.  It returns a list of
device names." };

  { defaults with
    name = "list_ldm_partitions"; added = (1, 20, 0);
    style = RStringList "devices", [], [];
    proc_nr = Some 381;
    optional = Some "ldm";
    shortdesc = "list all Windows dynamic disk partitions";
    longdesc = "\
This function returns all Windows dynamic disk partitions
that were found at launch time.  It returns a list of
device names." };

  { defaults with
    name = "ldmtool_create_all"; added = (1, 20, 0);
    style = RErr, [], [];
    proc_nr = Some 382;
    optional = Some "ldm";
    shortdesc = "scan and create Windows dynamic disk volumes";
    longdesc = "\
This function scans all block devices looking for Windows
dynamic disk volumes and partitions, and creates devices
for any that were found.

Call C<guestfs_list_ldm_volumes> and C<guestfs_list_ldm_partitions>
to return all devices.

Note that you B<don't> normally need to call this explicitly,
since it is done automatically at C<guestfs_launch> time.
However you might want to call this function if you have
hotplugged disks or have just created a Windows dynamic disk." };

  { defaults with
    name = "ldmtool_remove_all"; added = (1, 20, 0);
    style = RErr, [], [];
    proc_nr = Some 383;
    optional = Some "ldm";
    shortdesc = "remove all Windows dynamic disk volumes";
    longdesc = "\
This is essentially the opposite of C<guestfs_ldmtool_create_all>.
It removes the device mapper mappings for all Windows dynamic disk
volumes" };

  { defaults with
    name = "ldmtool_scan"; added = (1, 20, 0);
    style = RStringList "guids", [], [];
    proc_nr = Some 384;
    optional = Some "ldm";
    shortdesc = "scan for Windows dynamic disks";
    longdesc = "\
This function scans for Windows dynamic disks.  It returns a list
of identifiers (GUIDs) for all disk groups that were found.  These
identifiers can be passed to other C<guestfs_ldmtool_*> functions.

This function scans all block devices.  To scan a subset of
block devices, call C<guestfs_ldmtool_scan_devices> instead." };

  { defaults with
    name = "ldmtool_scan_devices"; added = (1, 20, 0);
    style = RStringList "guids", [DeviceList "devices"], [];
    proc_nr = Some 385;
    optional = Some "ldm";
    shortdesc = "scan for Windows dynamic disks";
    longdesc = "\
This function scans for Windows dynamic disks.  It returns a list
of identifiers (GUIDs) for all disk groups that were found.  These
identifiers can be passed to other C<guestfs_ldmtool_*> functions.

The parameter C<devices> is a list of block devices which are
scanned.  If this list is empty, all block devices are scanned." };

  { defaults with
    name = "ldmtool_diskgroup_name"; added = (1, 20, 0);
    style = RString "name", [String "diskgroup"], [];
    proc_nr = Some 386;
    optional = Some "ldm";
    shortdesc = "return the name of a Windows dynamic disk group";
    longdesc = "\
Return the name of a Windows dynamic disk group.  The C<diskgroup>
parameter should be the GUID of a disk group, one element from
the list returned by C<guestfs_ldmtool_scan>." };

  { defaults with
    name = "ldmtool_diskgroup_volumes"; added = (1, 20, 0);
    style = RStringList "volumes", [String "diskgroup"], [];
    proc_nr = Some 387;
    optional = Some "ldm";
    shortdesc = "return the volumes in a Windows dynamic disk group";
    longdesc = "\
Return the volumes in a Windows dynamic disk group.  The C<diskgroup>
parameter should be the GUID of a disk group, one element from
the list returned by C<guestfs_ldmtool_scan>." };

  { defaults with
    name = "ldmtool_diskgroup_disks"; added = (1, 20, 0);
    style = RStringList "disks", [String "diskgroup"], [];
    proc_nr = Some 388;
    optional = Some "ldm";
    shortdesc = "return the disks in a Windows dynamic disk group";
    longdesc = "\
Return the disks in a Windows dynamic disk group.  The C<diskgroup>
parameter should be the GUID of a disk group, one element from
the list returned by C<guestfs_ldmtool_scan>." };

  { defaults with
    name = "ldmtool_volume_type"; added = (1, 20, 0);
    style = RString "voltype", [String "diskgroup"; String "volume"], [];
    proc_nr = Some 389;
    optional = Some "ldm";
    shortdesc = "return the type of a Windows dynamic disk volume";
    longdesc = "\
Return the type of the volume named C<volume> in the disk
group with GUID C<diskgroup>.

Possible volume types that can be returned here include:
C<simple>, C<spanned>, C<striped>, C<mirrored>, C<raid5>.
Other types may also be returned." };

  { defaults with
    name = "ldmtool_volume_hint"; added = (1, 20, 0);
    style = RString "hint", [String "diskgroup"; String "volume"], [];
    proc_nr = Some 390;
    optional = Some "ldm";
    shortdesc = "return the hint field of a Windows dynamic disk volume";
    longdesc = "\
Return the hint field of the volume named C<volume> in the disk
group with GUID C<diskgroup>.  This may not be defined, in which
case the empty string is returned.  The hint field is often, though
not always, the name of a Windows drive, eg. C<E:>." };

  { defaults with
    name = "ldmtool_volume_partitions"; added = (1, 20, 0);
    style = RStringList "partitions", [String "diskgroup"; String "volume"], [];
    proc_nr = Some 391;
    optional = Some "ldm";
    shortdesc = "return the partitions in a Windows dynamic disk volume";
    longdesc = "\
Return the list of partitions in the volume named C<volume> in the disk
group with GUID C<diskgroup>." };

  { defaults with
    name = "part_set_gpt_type"; added = (1, 21, 1);
    style = RErr, [Device "device"; Int "partnum"; GUID "guid"], [];
    proc_nr = Some 392;
    optional = Some "gdisk";
    tests = [
      InitGPT, Always, TestLastFail (
        [["part_set_gpt_type"; "/dev/sda"; "1"; "f"]]), [];
      InitGPT, Always, TestResultString (
        [["part_set_gpt_type"; "/dev/sda"; "1";
          "01234567-89AB-CDEF-0123-456789ABCDEF"];
         ["part_get_gpt_type"; "/dev/sda"; "1"]],
        "01234567-89AB-CDEF-0123-456789ABCDEF"), [];
    ];
    shortdesc = "set the type GUID of a GPT partition";
    longdesc = "\
Set the type GUID of numbered GPT partition C<partnum> to C<guid>. Return an
error if the partition table of C<device> isn't GPT, or if C<guid> is not a
valid GUID.

See L<http://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs>
for a useful list of type GUIDs." };

  { defaults with
    name = "part_get_gpt_type"; added = (1, 21, 1);
    style = RString "guid", [Device "device"; Int "partnum"], [];
    proc_nr = Some 393;
    optional = Some "gdisk";
    tests = [
      InitGPT, Always, TestResultString (
        [["part_set_gpt_type"; "/dev/sda"; "1";
          "01234567-89AB-CDEF-0123-456789ABCDEF"];
         ["part_get_gpt_type"; "/dev/sda"; "1"]],
        "01234567-89AB-CDEF-0123-456789ABCDEF"), [];
    ];
    shortdesc = "get the type GUID of a GPT partition";
    longdesc = "\
Return the type GUID of numbered GPT partition C<partnum>. For MBR partitions,
return an appropriate GUID corresponding to the MBR type. Behaviour is undefined
for other partition types." };

  { defaults with
    name = "rename"; added = (1, 21, 5);
    style = RErr, [Pathname "oldpath"; Pathname "newpath"], [];
    proc_nr = Some 394;
    tests = [
      InitScratchFS, Always, TestResultFalse (
        [["mkdir"; "/rename"];
         ["write"; "/rename/old"; "file content"];
         ["rename"; "/rename/old"; "/rename/new"];
         ["is_file"; "/rename/old"; ""]]), []
    ];
    shortdesc = "rename a file on the same filesystem";
    longdesc = "\
Rename a file to a new place on the same filesystem.  This is
the same as the Linux L<rename(2)> system call.  In most cases
you are better to use C<guestfs_mv> instead." };

  { defaults with
    name = "is_whole_device"; added = (1, 21, 9);
    style = RBool "flag", [Device "device"], [];
    proc_nr = Some 395;
    tests = [
      InitEmpty, Always, TestResultTrue (
        [["is_whole_device"; "/dev/sda"]]), [];
      InitPartition, Always, TestResultFalse (
        [["is_whole_device"; "/dev/sda1"]]), [];
      InitBasicFSonLVM, Always, TestResultFalse (
        [["is_whole_device"; "/dev/VG/LV"]]), [];
    ];
    shortdesc = "test if a device is a whole device";
    longdesc = "\
This returns C<true> if and only if C<device> refers to a whole block
device. That is, not a partition or a logical device." };

  { defaults with
    name = "internal_parse_mountable"; added = (1, 21, 11);
    style = RStruct ("mountable", "internal_mountable"), [Mountable "mountable"], [];
    visibility = VInternal;
    proc_nr = Some 396;
    shortdesc = "parse a mountable string";
    longdesc = "\
Parse a mountable string." };

  { defaults with
    name = "internal_rhbz914931"; added = (1, 21, 14);
    style = RErr, [FileIn "filename"; Int "count"], [];
    proc_nr = Some 397;
    visibility = VInternal;
    cancellable = true;
    shortdesc = "used only to test rhbz914931 (internal use only)";
    longdesc = "\
This is only used to debug RHBZ#914931.  Note that this
deliberately crashes guestfsd." };

  { defaults with
    name = "syslinux"; added = (1, 21, 27);
    style = RErr, [Device "device"], [OString "directory"];
    proc_nr = Some 399;
    optional = Some "syslinux";
    shortdesc = "install the SYSLINUX bootloader";
    longdesc = "\
Install the SYSLINUX bootloader on C<device>.

The device parameter must be either a whole disk formatted
as a FAT filesystem, or a partition formatted as a FAT filesystem.
In the latter case, the partition should be marked as \"active\"
(C<guestfs_part_set_bootable>) and a Master Boot Record must be
installed (eg. using C<guestfs_pwrite_device>) on the first
sector of the whole disk.
The SYSLINUX package comes with some suitable Master Boot Records.
See the L<syslinux(1)> man page for further information.

The optional arguments are:

=over 4

=item F<directory>

Install SYSLINUX in the named subdirectory, instead of in the
root directory of the FAT filesystem.

=back

Additional configuration can be supplied to SYSLINUX by
placing a file called F<syslinux.cfg> on the FAT filesystem,
either in the root directory, or under F<directory> if that
optional argument is being used.  For further information
about the contents of this file, see L<syslinux(1)>.

See also C<guestfs_extlinux>." };

  { defaults with
    name = "extlinux"; added = (1, 21, 27);
    style = RErr, [Pathname "directory"], [];
    proc_nr = Some 400;
    optional = Some "extlinux";
    shortdesc = "install the SYSLINUX bootloader on an ext2/3/4 or btrfs filesystem";
    longdesc = "\
Install the SYSLINUX bootloader on the device mounted at F<directory>.
Unlike C<guestfs_syslinux> which requires a FAT filesystem, this can
be used on an ext2/3/4 or btrfs filesystem.

The F<directory> parameter can be either a mountpoint, or a
directory within the mountpoint.

You also have to mark the partition as \"active\"
(C<guestfs_part_set_bootable>) and a Master Boot Record must
be installed (eg. using C<guestfs_pwrite_device>) on the first
sector of the whole disk.
The SYSLINUX package comes with some suitable Master Boot Records.
See the L<extlinux(1)> man page for further information.

Additional configuration can be supplied to SYSLINUX by
placing a file called F<extlinux.conf> on the filesystem
under F<directory>.  For further information
about the contents of this file, see L<extlinux(1)>.

See also C<guestfs_syslinux>." };

  { defaults with
    name = "cp_r"; added = (1, 21, 38);
    style = RErr, [Pathname "src"; Pathname "dest"], [];
    proc_nr = Some 401;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/cp_r1"];
         ["mkdir"; "/cp_r2"];
         ["write"; "/cp_r1/file"; "file content"];
         ["cp_r"; "/cp_r1"; "/cp_r2"];
         ["cat"; "/cp_r2/cp_r1/file"]], "file content"), []
    ];
    shortdesc = "copy a file or directory recursively";
    longdesc = "\
This copies a file or directory from C<src> to C<dest>
recursively using the C<cp -rP> command.

Most users should use C<guestfs_cp_a> instead.  This command
is useful when you don't want to preserve permissions, because
the target filesystem does not support it (primarily when
writing to DOS FAT filesystems)." };

  { defaults with
    name = "remount"; added = (1, 23, 2);
    style = RErr, [Pathname "mountpoint"], [OBool "rw"];
    proc_nr = Some 402;
    tests = [
      InitScratchFS, Always, TestLastFail (
        [["remount"; "/"; "false"];
         ["write"; "/remount1"; "data"]]), [];
      InitScratchFS, Always, TestRun (
        [["remount"; "/"; "false"];
         ["remount"; "/"; "true"];
         ["write"; "/remount2"; "data"]]), []
    ];
    shortdesc = "remount a filesystem with different options";
    longdesc = "\
This call allows you to change the C<rw> (readonly/read-write)
flag on an already mounted filesystem at C<mountpoint>,
converting a readonly filesystem to be read-write, or vice-versa.

Note that at the moment you must supply the \"optional\" C<rw>
parameter.  In future we may allow other flags to be adjusted." };

  { defaults with
    name = "set_uuid"; added = (1, 23, 10);
    style = RErr, [Device "device"; String "uuid"], [];
    proc_nr = Some 403;
    tests =
      (let uuid = uuidgen () in [
        InitBasicFS, Always, TestResultString (
          [["set_uuid"; "/dev/sda1"; uuid];
           ["vfs_uuid"; "/dev/sda1"]], uuid), [];
      ]);
    shortdesc = "set the filesystem UUID";
    longdesc = "\
Set the filesystem UUID on C<device> to C<uuid>.
If this fails and the errno is ENOTSUP,
means that there is no support for changing the UUID
for the type of the specified filesystem.

Only some filesystem types support setting UUIDs.

To read the UUID on a filesystem, call C<guestfs_vfs_uuid>." };

  { defaults with
    name = "journal_open"; added = (1, 23, 11);
    style = RErr, [Pathname "directory"], [];
    proc_nr = Some 404;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "open the systemd journal";
    longdesc = "\
Open the systemd journal located in F<directory>.  Any previously
opened journal handle is closed.

The contents of the journal can be read using C<guestfs_journal_next>
and C<guestfs_journal_get>.

After you have finished using the journal, you should close the
handle by calling C<guestfs_journal_close>." };

  { defaults with
    name = "journal_close"; added = (1, 23, 11);
    style = RErr, [], [];
    proc_nr = Some 405;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "close the systemd journal";
    longdesc = "\
Close the journal handle." };

  { defaults with
    name = "journal_next"; added = (1, 23, 11);
    style = RBool "more", [], [];
    proc_nr = Some 406;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "move to the next journal entry";
    longdesc = "\
Move to the next journal entry.  You have to call this
at least once after opening the handle before you are able
to read data.

The returned boolean tells you if there are any more journal
records to read.  C<true> means you can read the next record
(eg. using C<guestfs_journal_get>), and C<false> means you
have reached the end of the journal." };

  { defaults with
    name = "journal_skip"; added = (1, 23, 11);
    style = RInt64 "rskip", [Int64 "skip"], [];
    proc_nr = Some 407;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "skip forwards or backwards in the journal";
    longdesc = "\
Skip forwards (C<skip E<ge> 0>) or backwards (C<skip E<lt> 0>) in the
journal.

The number of entries actually skipped is returned (note S<C<rskip E<ge> 0>>).
If this is not the same as the absolute value of the skip parameter
(C<|skip|>) you passed in then it means you have reached the end or
the start of the journal." };

  { defaults with
    name = "internal_journal_get"; added = (1, 23, 11);
    style = RErr, [FileOut "filename"], [];
    proc_nr = Some 408;
    visibility = VInternal;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "internal journal reading operation";
    longdesc = "\
This function is used internally when reading the journal." };

  { defaults with
    name = "journal_get_data_threshold"; added = (1, 23, 11);
    style = RInt64 "threshold", [], [];
    proc_nr = Some 409;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "get the data threshold for reading journal entries";
    longdesc = "\
Get the current data threshold for reading journal entries.
This is a hint to the journal that it may truncate data fields to
this size when reading them (note also that it may not truncate them).
If this returns C<0>, then the threshold is unlimited.

See also C<guestfs_journal_set_data_threshold>." };

  { defaults with
    name = "journal_set_data_threshold"; added = (1, 23, 11);
    style = RErr, [Int64 "threshold"], [];
    proc_nr = Some 410;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "set the data threshold for reading journal entries";
    longdesc = "\
Set the data threshold for reading journal entries.
This is a hint to the journal that it may truncate data fields to
this size when reading them (note also that it may not truncate them).
If you set this to C<0>, then the threshold is unlimited.

See also C<guestfs_journal_get_data_threshold>." };

  { defaults with
    name = "aug_setm"; added = (1, 23, 14);
    style = RInt "nodes", [String "base"; OptString "sub"; String "val"], [];
    proc_nr = Some 411;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/passwd"; "root:x:0:0:root:/root:/bin/bash\nbin:x:1:1:bin:/bin:/sbin/nologin\ndaemon:x:2:2:daemon:/sbin:/bin/csh\n"];
         ["aug_init"; "/"; "0"];
         ["aug_setm"; "/files/etc/passwd/*"; "shell"; "/sbin/nologin"];
         ["aug_save"];
         ["cat"; "/etc/passwd"]], "root:x:0:0:root:/root:/sbin/nologin\nbin:x:1:1:bin:/bin:/sbin/nologin\ndaemon:x:2:2:daemon:/sbin:/sbin/nologin\n"), [["aug_close"]]
    ];
    shortdesc = "set multiple Augeas nodes";
    longdesc = "\
Change multiple Augeas nodes in a single operation.  C<base> is
an expression matching multiple nodes.  C<sub> is a path expression
relative to C<base>.  All nodes matching C<base> are found, and then
for each node, C<sub> is changed to C<val>.  C<sub> may also be C<NULL>
in which case the C<base> nodes are modified.

This returns the number of nodes modified." };

  { defaults with
    name = "aug_label"; added = (1, 23, 14);
    style = RString "label", [String "augpath"], [];
    proc_nr = Some 412;
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/passwd"; "root:x:0:0:root:/root:/bin/bash\nbin:x:1:1:bin:/bin:/sbin/nologin\ndaemon:x:2:2:daemon:/sbin:/bin/csh\n"];
         ["aug_init"; "/"; "0"];
         ["aug_label"; "/files/etc/passwd/*[last()]"]], "daemon"), [["aug_close"]]
    ];
    shortdesc = "return the label from an Augeas path expression";
    longdesc = "\
The label (name of the last element) of the Augeas path expression
C<augpath> is returned.  C<augpath> must match exactly one node, else
this function returns an error." };

  { defaults with
    name = "internal_upload"; added = (1, 23, 30);
    style = RErr, [FileIn "filename"; String "tmpname"; Int "mode"], [];
    proc_nr = Some 413;
    visibility = VInternal;
    cancellable = true;
    shortdesc = "upload a file to the appliance (internal use only)";
    longdesc = "\
This function is used internally when setting up the appliance." };

  { defaults with
    name = "internal_exit"; added = (1, 23, 30);
    style = RErr, [], [];
    proc_nr = Some 414;
    (* Really VInternal, but we need to use it from the Perl bindings. XXX *)
    visibility = VDebug;
    cancellable = true;
    shortdesc = "cause the daemon to exit (internal use only)";
    longdesc = "\
This function is used internally when testing the appliance." };

  { defaults with
    name = "copy_attributes"; added = (1, 25, 21);
    style = RErr, [Pathname "src"; Pathname "dest"], [OBool "all"; OBool "mode"; OBool "xattributes"; OBool "ownership"];
    proc_nr = Some 415;
    shortdesc = "copy the attributes of a path (file/directory) to another";
    longdesc = "\
Copy the attributes of a path (which can be a file or a directory)
to another path.

By default C<no> attribute is copied, so make sure to specify any
(or C<all> to copy everything).

The optional arguments specify which attributes can be copied:

=over 4

=item C<mode>

Copy part of the file mode from C<source> to C<destination>. Only the
UNIX permissions and the sticky/setuid/setgid bits can be copied.

=item C<xattributes>

Copy the Linux extended attributes (xattrs) from C<source> to C<destination>.
This flag does nothing if the I<linuxxattrs> feature is not available
(see C<guestfs_feature_available>).

=item C<ownership>

Copy the owner uid and the group gid of C<source> to C<destination>.

=item C<all>

Copy B<all> the attributes from C<source> to C<destination>. Enabling it
enables all the other flags, if they are not specified already.

=back" };

  { defaults with
    name = "part_get_name"; added = (1, 25, 33);
    style = RString "name", [Device "device"; Int "partnum"], [];
    proc_nr = Some 416;
    shortdesc = "get partition name";
    longdesc = "\
This gets the partition name on partition numbered C<partnum> on
device C<device>.  Note that partitions are numbered from 1.

The partition name can only be read on certain types of partition
table.  This works on C<gpt> but not on C<mbr> partitions." };

  { defaults with
    name = "blkdiscard"; added = (1, 25, 44);
    style = RErr, [Device "device"], [];
    proc_nr = Some 417;
    optional = Some "blkdiscard";
    shortdesc = "discard all blocks on a device";
    longdesc = "\
This discards all blocks on the block device C<device>, giving
the free space back to the host.

This operation requires support in libguestfs, the host filesystem,
qemu and the host kernel.  If this support isn't present it may give
an error or even appear to run but do nothing.  You must also
set the C<discard> attribute on the underlying drive (see
C<guestfs_add_drive_opts>)." };

  { defaults with
    name = "blkdiscardzeroes"; added = (1, 25, 44);
    style = RBool "zeroes", [Device "device"], [];
    proc_nr = Some 418;
    optional = Some "blkdiscardzeroes";
    shortdesc = "return true if discarded blocks are read as zeroes";
    longdesc = "\
This call returns true if blocks on C<device> that have been
discarded by a call to C<guestfs_blkdiscard> are returned as
blocks of zero bytes when read the next time.

If it returns false, then it may be that discarded blocks are
read as stale or random data." };

  { defaults with
    name = "cpio_out"; added = (1, 27, 9);
    style = RErr, [String "directory"; FileOut "cpiofile"], [OString "format"];
    proc_nr = Some 419;
    cancellable = true;
    shortdesc = "pack directory into cpio file";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<cpiofile>.

The optional C<format> parameter can be used to select the format.
Only the following formats are currently permitted:

=over 4

=item C<newc>

New (SVR4) portable format.  This format happens to be compatible
with the cpio-like format used by the Linux kernel for initramfs.

This is the default format.

=item C<crc>

New (SVR4) portable format with a checksum.

=back" };

  { defaults with
    name = "journal_get_realtime_usec"; added = (1, 27, 18);
    style = RInt64 "usec", [], [];
    proc_nr = Some 420;
    optional = Some "journal";
    test_excuse = "tests in tests/journal subdirectory";
    shortdesc = "get the timestamp of the current journal entry";
    longdesc = "\
Get the realtime (wallclock) timestamp of the current journal entry." };

  { defaults with
    name = "statns"; added = (1, 27, 53);
    style = RStruct ("statbuf", "statns"), [Pathname "path"], [];
    proc_nr = Some 421;
    tests = [
      InitISOFS, Always, TestResult (
        [["statns"; "/empty"]], "ret->st_size == 0"), []
    ];
    shortdesc = "get file information";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as the L<stat(2)> system call." };

  { defaults with
    name = "lstatns"; added = (1, 27, 53);
    style = RStruct ("statbuf", "statns"), [Pathname "path"], [];
    proc_nr = Some 422;
    tests = [
      InitISOFS, Always, TestResult (
        [["lstatns"; "/empty"]], "ret->st_size == 0"), []
    ];
    shortdesc = "get file information for a symbolic link";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as C<guestfs_statns> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the L<lstat(2)> system call." };

  { defaults with
    name = "internal_lstatnslist"; added = (1, 27, 53);
    style = RStructList ("statbufs", "statns"), [Pathname "path"; FilenameList "names"], [];
    proc_nr = Some 423;
    visibility = VInternal;
    shortdesc = "lstat on multiple files";
    longdesc = "\
This is the internal call which implements C<guestfs_lstatnslist>." };

  { defaults with
    name = "blockdev_setra"; added = (1, 29, 10);
    style = RErr, [Device "device"; Int "sectors"], [];
    proc_nr = Some 424;
    tests = [
      InitEmpty, Always, TestRun (
        [["blockdev_setra"; "/dev/sda"; "1024" ]]), []
    ];
    shortdesc = "set readahead";
    longdesc = "\
Set readahead (in 512-byte sectors) for the device.

This uses the L<blockdev(8)> command." };

  { defaults with
    name = "btrfs_subvolume_get_default"; added = (1, 29, 17);
    style = RInt64 "id", [Mountable_or_Path "fs"], [];
    proc_nr = Some 425;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeGetDefault";
    tests = [
      InitPartition, Always, TestResult (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_subvolume_get_default"; "/dev/sda1"]], "ret > 0"), [];
      InitPartition, Always, TestResult (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_subvolume_get_default"; "/"]], "ret > 0"), []
    ];
    shortdesc = "get the default subvolume or snapshot of a filesystem";
    longdesc = "\
Get the default subvolume or snapshot of a filesystem mounted at C<mountpoint>." };

  { defaults with
    name = "btrfs_subvolume_show"; added = (1, 29, 17);
    style = RHashtable "btrfssubvolumeinfo", [Pathname "subvolume"], [];
    proc_nr = Some 426;
    optional = Some "btrfs"; camel_name = "BTRFSSubvolumeShow";
    tests = [
      InitPartition, Always, TestLastFail (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_subvolume_show"; "/"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_subvolume_create"; "/sub1"; "NOARG"];
         ["btrfs_subvolume_show"; "/sub1"]]), [];
      InitPartition, Always, TestLastFail (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["mkdir"; "/dir1"];
         ["btrfs_subvolume_show"; "/dir1"]]), [];
    ];
    shortdesc = "return detailed information of the subvolume";
    longdesc = "\
Return detailed information of the subvolume." };

  { defaults with
    name = "btrfs_quota_enable"; added = (1, 29, 17);
    style = RErr, [Mountable_or_Path "fs"; Bool "enable"], [];
    proc_nr = Some 427;
    optional = Some "btrfs"; camel_name = "BTRFSQuotaEnable";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_quota_enable"; "/dev/sda1"; "true"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_quota_enable"; "/dev/sda1"; "false"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "false"]]), [];
    ];
    shortdesc = "enable or disable subvolume quota support";
    longdesc = "\
Enable or disable subvolume quota support for filesystem which contains C<path>." };

  { defaults with
    name = "btrfs_quota_rescan"; added = (1, 29, 17);
    style = RErr, [Mountable_or_Path "fs"], [];
    proc_nr = Some 428;
    optional = Some "btrfs"; camel_name = "BTRFSQuotaRescan";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_quota_enable"; "/dev/sda1"; "true"];
         ["btrfs_quota_rescan"; "/dev/sda1"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_quota_rescan"; "/"]]), [];
    ];

    shortdesc = "trash all qgroup numbers and scan the metadata again with the current config";
    longdesc = "\
Trash all qgroup numbers and scan the metadata again with the current config." };

  { defaults with
    name = "btrfs_qgroup_limit"; added = (1, 29, 17);
    style = RErr, [Pathname "subvolume"; Int64 "size"], [];
    proc_nr = Some 429;
    optional = Some "btrfs"; camel_name = "BTRFSQgroupLimit";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_qgroup_limit"; "/"; "10737418240"]]), [];
      InitPartition, Always, TestLastFail (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "false"];
         ["btrfs_qgroup_limit"; "/"; "10737418240"]]), [];
    ];
    shortdesc = "limit the size of a subvolume";
    longdesc = "\
Limit the size of a subvolume which's path is C<subvolume>. C<size>
can have suffix of G, M, or K. " };

  { defaults with
    name = "btrfs_qgroup_create"; added = (1, 29, 17);
    style = RErr, [String "qgroupid"; Pathname "subvolume"], [];
    proc_nr = Some 430;
    optional = Some "btrfs"; camel_name = "BTRFSQgroupCreate";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_subvolume_create"; "/sub1"; "NOARG"];
         ["btrfs_qgroup_create"; "0/1000"; "/sub1"]]), [];
    ];
    shortdesc = "create a subvolume quota group";
    longdesc = "\
Create a quota group (qgroup) for subvolume at C<subvolume>." };

  { defaults with
    name = "btrfs_qgroup_destroy"; added = (1, 29, 17);
    style = RErr, [String "qgroupid"; Pathname "subvolume"], [];
    proc_nr = Some 431;
    optional = Some "btrfs"; camel_name = "BTRFSQgroupDestroy";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_subvolume_create"; "/sub1"; "NOARG"];
         ["btrfs_qgroup_create"; "0/1000"; "/sub1"];
         ["btrfs_qgroup_destroy"; "0/1000"; "/sub1"]]), [];
    ];
    shortdesc = "destroy a subvolume quota group";
    longdesc = "\
Destroy a quota group." };

  { defaults with
    name = "btrfs_qgroup_show"; added = (1, 29, 17);
    style = RStructList ("qgroups", "btrfsqgroup"), [Pathname "path"], [];
    proc_nr = Some 432;
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_subvolume_create"; "/sub1"; "NOARG"];
         ["btrfs_qgroup_create"; "0/1000"; "/sub1"];
         ["btrfs_qgroup_show"; "/"]]), [];
    ];
    optional = Some "btrfs"; camel_name = "BTRFSQgroupShow";
    shortdesc = "show subvolume quota groups";
    longdesc = "\
Show all subvolume quota groups in a btrfs filesystem, including their
usages." };

  { defaults with
    name = "btrfs_qgroup_assign"; added = (1, 29, 17);
    style = RErr, [String "src"; String "dst"; Pathname "path"], [];
    proc_nr = Some 433;
    optional = Some "btrfs"; camel_name = "BTRFSQgroupAssign";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_qgroup_create"; "0/1000"; "/"];
         ["btrfs_qgroup_create"; "1/1000"; "/"];
         ["btrfs_qgroup_assign"; "0/1000"; "1/1000"; "/"]]), [];
    ];
    shortdesc = "add a qgroup to a parent qgroup";
    longdesc = "\
Add qgroup C<src> to parent qgroup C<dst>. This command can group
several qgroups into a parent qgroup to share common limit." };

  { defaults with
    name = "btrfs_qgroup_remove"; added = (1, 29, 17);
    style = RErr, [String "src"; String "dst"; Pathname "path"], [];
    proc_nr = Some 434;
    optional = Some "btrfs"; camel_name = "BTRFSQgroupRemove";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_quota_enable"; "/"; "true"];
         ["btrfs_qgroup_create"; "0/1000"; "/"];
         ["btrfs_qgroup_create"; "1/1000"; "/"];
         ["btrfs_qgroup_assign"; "0/1000"; "1/1000"; "/"];
         ["btrfs_qgroup_remove"; "0/1000"; "1/1000"; "/"]]), [];
    ];
    shortdesc = "remove a qgroup from its parent qgroup";
    longdesc = "\
Remove qgroup C<src> from the parent qgroup C<dst>." };

  { defaults with
    name = "btrfs_scrub_start"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 435;
    optional = Some "btrfs"; camel_name = "BTRFSScrubStart";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_scrub_start"; "/"]]), [];
    ];
    shortdesc = "read all data from all disks and verify checksums";
    longdesc = "\
Reads all the data and metadata on the filesystem, and uses checksums
and the duplicate copies from RAID storage to identify and repair any
corrupt data." };

  { defaults with
    name = "btrfs_scrub_cancel"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 436;
    optional = Some "btrfs"; camel_name = "BTRFSScrubCancel";
    test_excuse = "test disk isn't large enough that btrfs_scrub_start completes before we can cancel it";
    shortdesc = "cancel a running scrub";
    longdesc = "\
Cancel a running scrub on a btrfs filesystem." };

  { defaults with
    name = "btrfs_scrub_resume"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 437;
    optional = Some "btrfs"; camel_name = "BTRFSScrubResume";
    test_excuse = "test disk isn't large enough that btrfs_scrub_start completes before we can cancel and resume it";
    shortdesc = "resume a previously canceled or interrupted scrub";
    longdesc = "\
Resume a previously canceled or interrupted scrub on a btrfs filesystem." };

{ defaults with
    name = "btrfs_balance_pause"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 438;
    optional = Some "btrfs"; camel_name = "BTRFSBalancePause";
    test_excuse = "test disk isn't large enough to test this thoroughly";
    shortdesc = "pause a running balance";
    longdesc = "\
Pause a running balance on a btrfs filesystem." };

{ defaults with
    name = "btrfs_balance_cancel"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 439;
    optional = Some "btrfs"; camel_name = "BTRFSBalanceCancel";
    test_excuse = "test disk isn't large enough that btrfs_balance completes before we can cancel it";
    shortdesc = "cancel a running or paused balance";
    longdesc = "\
Cancel a running balance on a btrfs filesystem." };

{ defaults with
    name = "btrfs_balance_resume"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [];
    proc_nr = Some 440;
    optional = Some "btrfs"; camel_name = "BTRFSBalanceResume";
    test_excuse = "test disk isn't large enough that btrfs_balance completes before we can pause and resume it";
    shortdesc = "resume a paused balance";
    longdesc = "\
Resume a paused balance on a btrfs filesystem." };

  { defaults with
    name = "btrfs_filesystem_defragment"; added = (1, 29, 22);
    style = RErr, [Pathname "path"], [OBool "flush"; OString "compress"];
    proc_nr = Some 443;
    optional = Some "btrfs"; camel_name = "BTRFSFilesystemDefragment";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_filesystem_defragment"; "/"; "true"; "lzo"]]), [];
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["touch"; "/hello"];
         ["btrfs_filesystem_defragment"; "/hello"; ""; "zlib"]]), [];
    ];
    shortdesc = "defragment a file or directory";
    longdesc = "\
Defragment a file or directory on a btrfs filesystem. compress is one of zlib or lzo." };

  { defaults with
    name = "btrfs_rescue_chunk_recover"; added = (1, 29, 22);
    style = RErr, [Device "device"], [];
    proc_nr = Some 444;
    optional = Some "btrfs"; camel_name = "BTRFSRescueChunkRecover";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_rescue_chunk_recover"; "/dev/sda1"]]), [];
    ];
    shortdesc = "recover the chunk tree of btrfs filesystem";
    longdesc = "\
Recover the chunk tree of btrfs filesystem by scanning the devices one by one." };

  { defaults with
    name = "btrfs_rescue_super_recover"; added = (1, 29, 22);
    style = RErr, [Device "device"], [];
    proc_nr = Some 445;
    optional = Some "btrfs"; camel_name = "BTRFSRescueSuperRecover";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfs_rescue_super_recover"; "/dev/sda1"]]), [];
    ];
    shortdesc = "recover bad superblocks from good copies";
    longdesc = "\
Recover bad superblocks from good copies." };

  { defaults with
    name = "part_set_gpt_guid"; added = (1, 29, 25);
    style = RErr, [Device "device"; Int "partnum"; GUID "guid"], [];
    proc_nr = Some 446;
    optional = Some "gdisk";
    tests = [
      InitGPT, Always, TestLastFail (
        [["part_set_gpt_guid"; "/dev/sda"; "1"; "f"]]), [];
      InitGPT, Always, TestResultString (
        [["part_set_gpt_guid"; "/dev/sda"; "1";
          "01234567-89AB-CDEF-0123-456789ABCDEF"];
         ["part_get_gpt_guid"; "/dev/sda"; "1"]],
        "01234567-89AB-CDEF-0123-456789ABCDEF"), [];
    ];
    shortdesc = "set the GUID of a GPT partition";
    longdesc = "\
Set the GUID of numbered GPT partition C<partnum> to C<guid>.  Return an
error if the partition table of C<device> isn't GPT, or if C<guid> is not a
valid GUID." };

  { defaults with
    name = "part_get_gpt_guid"; added = (1, 29, 25);
    style = RString "guid", [Device "device"; Int "partnum"], [];
    proc_nr = Some 447;
    optional = Some "gdisk";
    tests = [
      InitGPT, Always, TestResultString (
        [["part_set_gpt_guid"; "/dev/sda"; "1";
          "01234567-89AB-CDEF-0123-456789ABCDEF"];
         ["part_get_gpt_guid"; "/dev/sda"; "1"]],
        "01234567-89AB-CDEF-0123-456789ABCDEF"), [];
    ];
    shortdesc = "get the GUID of a GPT partition";
    longdesc = "\
Return the GUID of numbered GPT partition C<partnum>." };

{ defaults with
    name = "btrfs_balance_status"; added = (1, 29, 26);
    style = RStruct ("status", "btrfsbalance"), [Pathname "path"], [];
    proc_nr = Some 448;
    optional = Some "btrfs"; camel_name = "BTRFSBalanceStatus";
    test_excuse = "test disk isn't large enough that btrfs_balance completes before we can get its status";
    shortdesc = "show the status of a running or paused balance";
    longdesc = "\
Show the status of a running or paused balance on a btrfs filesystem." };

  { defaults with
    name = "btrfs_scrub_status"; added = (1, 29, 26);
    style = RStruct ("status", "btrfsscrub"), [Pathname "path"], [];
    proc_nr = Some 449;
    optional = Some "btrfs"; camel_name = "BTRFSScrubStatus";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_scrub_start"; "/"];
         ["btrfs_scrub_status"; "/"]]), [];
    ];
    shortdesc = "show status of running or finished scrub";
    longdesc = "\
Show status of running or finished scrub on a btrfs filesystem." };

  { defaults with
    name = "btrfstune_seeding"; added = (1, 29, 29);
    style = RErr, [Device "device"; Bool "seeding"], [];
    proc_nr = Some 450;
    optional = Some "btrfs"; camel_name = "BTRFSTuneSeeding";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfstune_seeding"; "/dev/sda1"; "true"];
         ["btrfstune_seeding"; "/dev/sda1"; "false"]]), []
    ];

    shortdesc = "enable or disable seeding of a btrfs device";
    longdesc = "\
Enable seeding of a btrfs device, this will force a fs readonly
so that you can use it to build other filesystems." };

  { defaults with
    name = "btrfstune_enable_extended_inode_refs"; added = (1, 29, 29);
    style = RErr, [Device "device"], [];
    proc_nr = Some 451;
    optional = Some "btrfs"; camel_name = "BTRFSTuneEnableExtendedInodeRefs";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfstune_enable_extended_inode_refs"; "/dev/sda1"]]), []
    ];

    shortdesc = "enable extended inode refs";
    longdesc = "\
This will Enable extended inode refs." };

  { defaults with
    name = "btrfstune_enable_skinny_metadata_extent_refs"; added = (1, 29, 29);
    style = RErr, [Device "device"], [];
    proc_nr = Some 452;
    optional = Some "btrfs"; camel_name = "BTRFSTuneEnableSkinnyMetadataExtentRefs";
    tests = [
      InitPartition, Always, TestRun (
        [["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["btrfstune_enable_skinny_metadata_extent_refs"; "/dev/sda1"]]), []
    ];

    shortdesc = "enable skinny metadata extent refs";
    longdesc = "\
This enable skinny metadata extent refs." };

  { defaults with
    name = "btrfs_image"; added = (1, 29, 32);
    style = RErr, [DeviceList "source"; Pathname "image"], [OInt "compresslevel"];
    proc_nr = Some 453;
    optional = Some "btrfs"; camel_name = "BTRFSImage";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "2047999"];
         ["part_add"; "/dev/sda"; "p"; "2048000"; "4095999"];
         ["mkfs_btrfs"; "/dev/sda1"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mkfs_btrfs"; "/dev/sda2"; ""; ""; "NOARG"; ""; "NOARG"; "NOARG"; ""; ""];
         ["mount"; "/dev/sda1"; "/"];
         ["btrfs_image"; "/dev/sda2"; "/1.img"; ""];
         ["btrfs_image"; "/dev/sda2"; "/2.img"; "2"]]), []
    ];

    shortdesc = "create an image of a btrfs filesystem";
    longdesc = "\
This is used to create an image of a btrfs filesystem.
All data will be zeroed, but metadata and the like is preserved." };

  { defaults with
    name = "part_get_mbr_part_type"; added = (1, 29, 32);
    style = RString "partitiontype", [Device "device"; Int "partnum"], [];
    proc_nr = Some 454;
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "e"; "204800"; "614400"];
         ["part_add"; "/dev/sda"; "l"; "204864"; "205988"];
         ["part_get_mbr_part_type"; "/dev/sda"; "5"]], "logical"), [];
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "e"; "204800"; "614400"];
         ["part_add"; "/dev/sda"; "l"; "204864"; "205988"];
         ["part_get_mbr_part_type"; "/dev/sda"; "2"]], "extended"), []
    ];

    shortdesc = "get the MBR partition type";
    longdesc = "\
This returns the partition type of an MBR partition
numbered C<partnum> on device C<device>.

It returns C<primary>, C<logical>, or C<extended>." };

  { defaults with
    name = "btrfs_replace"; added = (1, 29, 48);
    style = RErr, [Device "srcdev"; Device "targetdev"; Pathname "mntpoint"], [];
    proc_nr = Some 455;
    optional = Some "btrfs"; camel_name = "BTRFSReplace";
    test_excuse = "put the test in 'tests/btrfs' directory";
    shortdesc = "replace a btrfs managed device with another device";
    longdesc = "\
Replace device of a btrfs filesystem. On a live filesystem, duplicate the data
to the target device which is currently stored on the source device.
After completion of the operation, the source device is wiped out and
removed from the filesystem.

The C<targetdev> needs to be same size or larger than the C<srcdev>. Devices
which are currently mounted are never allowed to be used as the C<targetdev>." };

  { defaults with
    name = "set_uuid_random"; added = (1, 29, 50);
    style = RErr, [Device "device"], [];
    proc_nr = Some 456;
    tests = [
        InitBasicFS, Always, TestRun (
            [["set_uuid_random"; "/dev/sda1"]]), [];
      ];
    shortdesc = "set a random UUID for the filesystem";
    longdesc = "\
Set the filesystem UUID on C<device> to a random UUID.
If this fails and the errno is ENOTSUP,
means that there is no support for changing the UUID
for the type of the specified filesystem.

Only some filesystem types support setting UUIDs.

To read the UUID on a filesystem, call C<guestfs_vfs_uuid>." };

  { defaults with
    name = "vfs_minimum_size"; added = (1, 31, 18);
    style = RInt64 "sizeinbytes", [Mountable "mountable"], [];
    proc_nr = Some 457;
    tests = [
      InitBasicFS, Always, TestRun (
        [["vfs_minimum_size"; "/dev/sda1"]]), [];
      InitPartition, IfAvailable "ntfsprogs", TestRun(
        [["mkfs"; "ntfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["vfs_minimum_size"; "/dev/sda1"]]), [];
      InitPartition, IfAvailable "btrfs", TestRunOrUnsupported (
        [["mkfs"; "btrfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["vfs_minimum_size"; "/dev/sda1"]]), [];
      InitPartition, IfAvailable "xfs", TestRun (
        [["mkfs"; "xfs"; "/dev/sda1"; ""; "NOARG"; ""; ""; "NOARG"];
         ["mount"; "/dev/sda1"; "/"];
         ["vfs_minimum_size"; "/dev/sda1"]]), [];
    ];
    shortdesc = "get minimum filesystem size";
    longdesc = "\
Get the minimum size of filesystem in bytes.
This is the minimum possible size for filesystem shrinking.

If getting minimum size of specified filesystem is not supported,
this will fail and set errno as ENOTSUP.

See also L<ntfsresize(8)>, L<resize2fs(8)>, L<btrfs(8)>, L<xfs_info(8)>." };

  { defaults with
    name = "internal_feature_available"; added = (1, 31, 25);
    style = RInt "result", [String "group"], [];
    proc_nr = Some 458;
    visibility = VInternal;
    shortdesc = "test availability of some parts of the API";
    longdesc = "\
This is the internal call which implements C<guestfs_feature_available>." };

]

(* Non-API meta-commands available only in guestfish.
 *
 * Note (1): The only fields which are actually used are the
 * shortname, fish_alias, shortdesc and longdesc.
 *
 * Note (2): to refer to other commands, use L</shortname>.
 *
 * Note (3): keep this list sorted by shortname.
 *)
let fish_commands = [
  { defaults with
    name = "alloc";
    fish_alias = ["allocate"];
    shortdesc = "allocate and add a disk file";
    longdesc = " alloc filename size

This creates an empty (zeroed) file of the given size, and then adds
so it can be further examined.

For more advanced image creation, see L</disk-create>.

Size can be specified using standard suffixes, eg. C<1M>.

To create a sparse file, use L</sparse> instead.  To create a
prepared disk image, see L</PREPARED DISK IMAGES>." };

  { defaults with
    name = "copy_in";
    shortdesc = "copy local files or directories into an image";
    longdesc = " copy-in local [local ...] /remotedir

C<copy-in> copies local files or directories recursively into the disk
image, placing them in the directory called F</remotedir> (which must
exist).  This guestfish meta-command turns into a sequence of
L</tar-in> and other commands as necessary.

Multiple local files and directories can be specified, but the last
parameter must always be a remote directory.  Wildcards cannot be
used." };

  { defaults with
    name = "copy_out";
    shortdesc = "copy remote files or directories out of an image";
    longdesc = " copy-out remote [remote ...] localdir

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

 glob copy-out /home/* ." };

  { defaults with
    name = "delete_event";
    shortdesc = "delete a previously registered event handler";
    longdesc = " delete-event name

Delete the event handler which was previously registered as C<name>.
If multiple event handlers were registered with the same name, they
are all deleted.

See also the guestfish commands C<event> and C<list-events>." };

  { defaults with
    name = "display";
    shortdesc = "display an image";
    longdesc = " display filename

Use C<display> (a graphical display program) to display an image
file.  It downloads the file, and runs C<display> on it.

To use an alternative program, set the C<GUESTFISH_DISPLAY_IMAGE>
environment variable.  For example to use the GNOME display program:

 export GUESTFISH_DISPLAY_IMAGE=eog

See also L<display(1)>." };

  { defaults with
    name = "echo";
    shortdesc = "display a line of text";
    longdesc = " echo [params ...]

This echos the parameters to the terminal." };

  { defaults with
    name = "edit";
    fish_alias = ["vi"; "emacs"];
    shortdesc = "edit a file";
    longdesc = " edit filename

This is used to edit a file.  It downloads the file, edits it
locally using your editor, then uploads the result.

The editor is C<$EDITOR>.  However if you use the alternate
commands C<vi> or C<emacs> you will get those corresponding
editors." };

  { defaults with
    name = "event";
    shortdesc = "register a handler for an event or events";
    longdesc = " event name eventset \"shell script ...\"

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
C<$SHELL -c>, or if C<$SHELL> is not set then F</bin/sh -c>.

The shell script fragment receives callback parameters as
arguments C<$1>, C<$2> etc.  The actual event that was
called is available in the environment variable C<$EVENT>.

 event \"\" close \"echo closed\"
 event messages appliance,library,trace \"echo $@\"
 event \"\" progress \"echo progress: $3/$4\"
 event \"\" * \"echo $EVENT $@\"

See also the guestfish commands C<delete-event> and C<list-events>." };

  { defaults with
    name = "glob";
    shortdesc = "expand wildcards in command";
    longdesc = " glob command args...

Expand wildcards in any paths in the args list, and run C<command>
repeatedly on each matching path.

See L</WILDCARDS AND GLOBBING>." };

  { defaults with
    name = "hexedit";
    shortdesc = "edit with a hex editor";
    longdesc = " hexedit <filename|device>
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

To edit the superblock of an ext2 filesystem on F</dev/sda1>, do:

 hexedit /dev/sda1 0x400 0x400

(assuming the superblock is in the standard location).

This command requires the external L<hexedit(1)> program.  You
can specify another program to use by setting the C<HEXEDITOR>
environment variable.

See also L</hexdump>." };

  { defaults with
    name = "lcd";
    shortdesc = "change working directory";
    longdesc = " lcd directory

Change the local directory, ie. the current directory of guestfish
itself.

Note that C<!cd> won't do what you might expect." };

  { defaults with
    name = "list_events";
    shortdesc = "list event handlers";
    longdesc = " list-events

List the event handlers registered using the guestfish
C<event> command." };

  { defaults with
    name = "man";
    fish_alias = ["manual"];
    shortdesc = "open the manual";
    longdesc = "  man

Opens the manual page for guestfish." };

  { defaults with
    name = "more";
    fish_alias = ["less"];
    shortdesc = "view a file";
    longdesc = " more filename

 less filename

This is used to view a file.

The default viewer is C<$PAGER>.  However if you use the alternate
command C<less> you will get the C<less> command specifically." };

  { defaults with
    name = "reopen";
    shortdesc = "close and reopen libguestfs handle";
    longdesc = "  reopen

Close and reopen the libguestfs handle.  It is not necessary to use
this normally, because the handle is closed properly when guestfish
exits.  However this is occasionally useful for testing." };

  { defaults with
    name = "setenv";
    shortdesc = "set an environment variable";
    longdesc = "  setenv VAR value

Set the environment variable C<VAR> to the string C<value>.

To print the value of an environment variable use a shell command
such as:

 !echo $VAR" };

  { defaults with
    name = "sparse";
    shortdesc = "create a sparse disk image and add";
    longdesc = " sparse filename size

This creates an empty sparse file of the given size, and then adds
so it can be further examined.

In all respects it works the same as the L</alloc> command, except that
the image file is allocated sparsely, which means that disk blocks are
not assigned to the file until they are needed.  Sparse disk files
only use space when written to, but they are slower and there is a
danger you could run out of real disk space during a write operation.

For more advanced image creation, see L</disk-create>.

Size can be specified using standard suffixes, eg. C<1M>.

See also the guestfish L</scratch> command." };

  { defaults with
    name = "supported";
    shortdesc = "list supported groups of commands";
    longdesc = " supported

This command returns a list of the optional groups
known to the daemon, and indicates which ones are
supported by this build of the libguestfs appliance.

See also L<guestfs(3)/AVAILABILITY>." };

  { defaults with
    name = "time";
    shortdesc = "print elapsed time taken to run a command";
    longdesc = " time command args...

Run the command as usual, but print the elapsed time afterwards.  This
can be useful for benchmarking operations." };

  { defaults with
    name = "unsetenv";
    shortdesc = "unset an environment variable";
    longdesc = "  unsetenv VAR

Remove C<VAR> from the environment." };

]

(*----------------------------------------------------------------------*)

(* Some post-processing of the basic lists of actions. *)

(* Add the name of the C function:
 * c_name = short name, used by C bindings so we know what to export
 * c_function = full name that non-C bindings should call
 * c_optarg_prefix = prefix for optarg / bitmask names
 *)
let test_functions, non_daemon_functions, daemon_functions =
  let make_c_function f =
    match f with
    | { style = _, _, [] } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name;
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase f.name }
    | { style = _, _, (_::_); once_had_no_optargs = false } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name ^ "_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase f.name }
    | { style = _, _, (_::_); once_had_no_optargs = true } ->
      { f with
          c_name = f.name ^ "_opts";
          c_function = "guestfs_" ^ f.name ^ "_opts_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase f.name ^ "_OPTS";
          non_c_aliases = [ f.name ^ "_opts" ] }
  in
  let test_functions = List.map make_c_function test_functions in
  let non_daemon_functions = List.map make_c_function non_daemon_functions in
  let daemon_functions = List.map make_c_function daemon_functions in
  test_functions, non_daemon_functions, daemon_functions

(* Create a camel-case version of each name, unless the camel_name
 * field was set above.
 *)
let non_daemon_functions, daemon_functions =
  let make_camel_case name =
    List.fold_left (
      fun a b ->
        a ^ String.uppercase (Str.first_chars b 1) ^ Str.string_after b 1
    ) "" (Str.split (Str.regexp "_") name)
  in
  let make_camel_case_if_not_set f =
    if f.camel_name = "" then
      { f with camel_name = make_camel_case f.name }
    else
      f
  in
  let non_daemon_functions =
    List.map make_camel_case_if_not_set non_daemon_functions in
  let daemon_functions =
    List.map make_camel_case_if_not_set daemon_functions in
  non_daemon_functions, daemon_functions

(* All functions. *)
let all_functions = non_daemon_functions @ daemon_functions

let is_external { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest | VBindTest | VDebug -> true
  | VInternal -> false

let is_internal f = not (is_external f)

let is_documented { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest -> true
  | VBindTest | VDebug | VInternal -> false

let is_fish { visibility = v; style = (_, args, _) } =
  (* Internal functions are not exported to guestfish. *)
  match v with
  | VPublicNoFish | VStateTest | VBindTest | VInternal -> false
  | VPublic | VDebug ->
    (* Functions that take Pointer parameters cannot be used in
     * guestfish, since there is no way the user could safely
     * generate a pointer.
     *)
    not (List.exists (function Pointer _ -> true | _ -> false) args)

let external_functions =
  List.filter is_external all_functions

let internal_functions =
  List.filter is_internal all_functions

let documented_functions =
  List.filter is_documented all_functions

let fish_functions =
  List.filter is_fish all_functions

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let all_functions_sorted = List.sort action_compare all_functions

let external_functions_sorted =
  List.sort action_compare external_functions

let internal_functions_sorted =
  List.sort action_compare internal_functions

let documented_functions_sorted =
  List.sort action_compare documented_functions

let fish_functions_sorted =
  List.sort action_compare fish_functions

(* This is used to generate the src/MAX_PROC_NR file which
 * contains the maximum procedure number, a surrogate for the
 * ABI version number.  See src/Makefile.am for the details.
 *)
let max_proc_nr =
  let proc_nrs = List.map (
    function { proc_nr = Some n } -> n | { proc_nr = None } -> 0
  ) daemon_functions in
  List.fold_left max 0 proc_nrs
