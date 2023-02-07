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

open Types

(* APIs related to handle properties. *)

let non_daemon_functions = [
  { defaults with
    name = "set_hv"; added = (1, 23, 17);
    style = RErr, [String (PlainString, "hv")], [];
    fish_alias = ["hv"]; config_only = true;
    blocking = false;
    shortdesc = "set the hypervisor binary";
    longdesc = "\
Set the hypervisor binary that we will use.  The hypervisor
depends on the backend, but is usually the location of the
qemu/KVM hypervisor.

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
    style = RString (RPlainString, "hv"), [], [];
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
    name = "set_backend"; added = (1, 21, 26);
    style = RErr, [String (PlainString, "backend")], [];
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
    style = RString (RPlainString, "backend"), [], [];
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
    style = RString (RPlainString, "tmpdir"), [], [];
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
    style = RString (RPlainString, "cachedir"), [], [];
    blocking = false;
    shortdesc = "get the appliance cache directory";
    longdesc = "\
Get the directory used by the handle to store the appliance cache." };

  { defaults with
    name = "set_program"; added = (1, 21, 29);
    style = RErr, [String (PlainString, "program")], [];
    fish_alias = ["program"];
    blocking = false;
    shortdesc = "set the program name";
    longdesc = "\
Set the program name.  This is an informative string which the
main program may optionally set in the handle.

When the handle is created, the program name in the handle is
set to the basename from C<argv[0]>.  The program name can never
be C<NULL>." };

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
    name = "get_backend_settings"; added = (1, 25, 24);
    style = RStringList (RPlainString, "settings"), [], [];
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
    style = RErr, [StringList (PlainString, "settings")], [];
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
    style = RString (RPlainString, "val"), [String (PlainString, "name")], [];
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
    style = RErr, [String (PlainString, "name"); String (PlainString, "val")], [];
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
    style = RInt "count", [String (PlainString, "name")], [];
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
    name = "set_identifier"; added = (1, 31, 14);
    style = RErr, [String (PlainString, "identifier")], [];
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
    name = "get_sockdir"; added = (1, 33, 8);
    style = RString (RPlainString, "sockdir"), [], [];
    blocking = false;
    shortdesc = "get the temporary directory for sockets";
    longdesc = "\
Get the directory used by the handle to store temporary socket files.

This is different from C<guestfs_get_tmpdir>, as we need shorter
paths for sockets (due to the limited buffers of filenames for UNIX
sockets), and C<guestfs_get_tmpdir> may be too long for them.

The environment variable C<XDG_RUNTIME_DIR> controls the default
value: If C<XDG_RUNTIME_DIR> is set, then that is the default.
Else F</tmp> is the default." };

]

let daemon_functions = [
]
