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

(* Inspection APIs. *)

let non_daemon_functions = [
  { defaults with
    name = "inspect_list_applications"; added = (1, 7, 8);
    style = RStructList ("applications", "application"), [String (Mountable, "root")], [];
    deprecated_by = Replaced_by "inspect_list_applications2";
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

The name of the application.  For Linux guests, this is the package
name.

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

]

let daemon_functions = [
  { defaults with
    name = "inspect_get_format"; added = (1, 9, 4);
    style = RString (RPlainString, "format"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_format";
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "get format of inspected operating system";
    longdesc = "\
Before libguestfs 1.38, there was some unreliable support for detecting
installer CDs.  This API would return:

=over 4

=item C<installed>

This is an installed operating system.

=item C<installer>

The disk image being inspected is not an installed operating system,
but a I<bootable> install disk, live CD, or similar.

=item C<unknown>

The format of this disk image is not known.

=back

In libguestfs E<ge> 1.38, this only returns C<installed>.
Use libosinfo directly to detect installer CDs.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_live"; added = (1, 9, 4);
    style = RBool "live", [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_is_live";
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "get live flag for install disk";
    longdesc = "\
This is deprecated and always returns C<false>.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_netinst"; added = (1, 9, 4);
    style = RBool "netinst", [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_is_netinst";
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "get netinst (network installer) flag for install disk";
    longdesc = "\
This is deprecated and always returns C<false>.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_is_multipart"; added = (1, 9, 4);
    style = RBool "multipart", [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_is_multipart";
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "get multipart flag for install disk";
    longdesc = "\
This is deprecated and always returns C<false>.

Please read L<guestfs(3)/INSPECTION> for more details." };

]
