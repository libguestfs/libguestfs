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

(* APIs related to handle properties.
 * All the APIs in this file are deprecated.
 *)

let non_daemon_functions = [
  { defaults with
    name = "set_qemu"; added = (1, 0, 6);
    style = RErr, [OptString "hv"], [];
    fish_alias = ["qemu"]; config_only = true;
    blocking = false;
    deprecated_by = Replaced_by "set_hv";
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
    deprecated_by = Replaced_by "get_hv";
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
    name = "set_selinux"; added = (1, 0, 67);
    style = RErr, [Bool "selinux"], [];
    fish_alias = ["selinux"]; config_only = true;
    blocking = false;
    deprecated_by = Replaced_by "selinux_relabel";
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
    deprecated_by = Replaced_by "selinux_relabel";
    shortdesc = "get SELinux enabled flag";
    longdesc = "\
This returns the current setting of the selinux flag which
is passed to the appliance at boot time.  See C<guestfs_set_selinux>.

For more information on the architecture of libguestfs,
see L<guestfs(3)>." };

  { defaults with
    name = "set_attach_method"; added = (1, 9, 8);
    style = RErr, [String (PlainString, "backend")], [];
    fish_alias = ["attach-method"]; config_only = true;
    blocking = false;
    deprecated_by = Replaced_by "set_backend";
    shortdesc = "set the backend";
    longdesc = "\
Set the method that libguestfs uses to connect to the backend
guestfsd daemon.

See L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "get_attach_method"; added = (1, 9, 8);
    style = RString (RPlainString, "backend"), [], [];
    blocking = false;
    deprecated_by = Replaced_by "get_backend";
    tests = [
      InitNone, Always, TestRun (
        [["get_attach_method"]]), []
    ];
    shortdesc = "get the backend";
    longdesc = "\
Return the current backend.

See C<guestfs_set_backend> and L<guestfs(3)/BACKEND>." };

  { defaults with
    name = "set_direct"; added = (1, 0, 72);
    style = RErr, [Bool "direct"], [];
    deprecated_by = Replaced_by "internal_get_console_socket";
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
    deprecated_by = Replaced_by "internal_get_console_socket";
    blocking = false;
    shortdesc = "get direct appliance mode flag";
    longdesc = "\
Return the direct appliance mode flag." };

]

let daemon_functions = [
]
