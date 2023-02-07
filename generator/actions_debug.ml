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

(* Debug APIs. *)

let non_daemon_functions = [
  { defaults with
    name = "debug_drives"; added = (1, 13, 22);
    style = RStringList (RPlainString, "cmdline"), [], [];
    visibility = VDebug;
    blocking = false;
    shortdesc = "debug the drives (internal use only)";
    longdesc = "\
This returns the internal list of drives.  ‘debug’ commands are
not part of the formal API and can be removed or changed at any time." };

]

let daemon_functions = [
  { defaults with
    name = "debug"; added = (1, 0, 11);
    style = RString (RPlainString, "result"), [String (PlainString, "subcmd"); StringList (PlainString, "extraargs")], [];
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
    name = "debug_upload"; added = (1, 3, 5);
    style = RErr, [String (FileIn, "filename"); String (PlainString, "tmpname"); Int "mode"], [];
    visibility = VDebug;
    cancellable = true;
    shortdesc = "upload a file to the appliance (internal use only)";
    longdesc = "\
The C<guestfs_debug_upload> command uploads a file to
the libguestfs appliance.

There is no comprehensive help for this command.  You have
to look at the file F<daemon/debug.c> in the libguestfs source
to find out what it is for." };

]
