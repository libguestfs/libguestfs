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

let daemon_functions = [
  { defaults with
    name = "inspect_os"; added = (1, 5, 3);
    style = RStringList (RMountable, "roots"), [], [];
    impl = OCaml "Inspect.inspect_os";
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
    name = "inspect_get_roots"; added = (1, 7, 3);
    style = RStringList (RMountable, "roots"), [], [];
    impl = OCaml "Inspect.inspect_get_roots";
    shortdesc = "return list of operating systems found by last inspection";
    longdesc = "\
This function is a convenient way to get the list of root
devices, as returned from a previous call to C<guestfs_inspect_os>,
but without redoing the whole inspection process.

This returns an empty list if either no root devices were
found or the caller has not called C<guestfs_inspect_os>.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_type"; added = (1, 5, 3);
    style = RString (RPlainString, "name"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_type";
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
    style = RString (RPlainString, "arch"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_arch";
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
    style = RString (RPlainString, "distro"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_distro";
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

=item \"kalilinux\"

Kali Linux.

=item \"kylin\"

Kylin.

=item \"linuxmint\"

Linux Mint.

=item \"mageia\"

Mageia.

=item \"mandriva\"

Mandriva.

=item \"meego\"

MeeGo.

=item \"msdos\"

Microsoft DOS.

=item \"neokylin\"

NeoKylin.

=item \"netbsd\"

NetBSD.

=item \"openbsd\"

OpenBSD.

=item \"openmandriva\"

OpenMandriva Lx.

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

=item \"rocky\"

Rocky Linux.

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

=item \"voidlinux\"

Void Linux.

=item \"windows\"

Windows does not have distributions.  This string is
returned if the OS type is Windows.

=back

Future versions of libguestfs may return other strings here.
The caller should be prepared to handle any string.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_major_version"; added = (1, 5, 3);
    style = RInt "major", [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_major_version";
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
    style = RInt "minor", [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_minor_version";
    shortdesc = "get minor version of inspected operating system";
    longdesc = "\
This returns the minor version number of the inspected operating
system.

If the version could not be determined, then C<0> is returned.

Please read L<guestfs(3)/INSPECTION> for more details.
See also C<guestfs_inspect_get_major_version>." };

  { defaults with
    name = "inspect_get_product_name"; added = (1, 5, 3);
    style = RString (RPlainString, "product"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_product_name";
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
    name = "inspect_get_windows_systemroot"; added = (1, 5, 25);
    style = RString (RPlainString, "systemroot"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_windows_systemroot";
    shortdesc = "get Windows systemroot of inspected operating system";
    longdesc = "\
This returns the Windows systemroot of the inspected guest.
The systemroot is a directory path such as F</WINDOWS>.

This call assumes that the guest is Windows and that the
systemroot could be determined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_package_format"; added = (1, 7, 5);
    style = RString (RPlainString, "packageformat"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_package_format";
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
C<rpm>, C<deb>, C<ebuild>, C<pisi>, C<pacman>, C<pkgsrc>, C<apk>,
C<xbps>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_package_management"; added = (1, 7, 5);
    style = RString (RPlainString, "packagemanagement"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_package_management";
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
C<portage>, C<pisi>, C<pacman>, C<urpmi>, C<zypper>, C<apk>, C<xbps>.
Future versions of libguestfs may return other strings.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_hostname"; added = (1, 7, 9);
    style = RString (RPlainString, "hostname"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_hostname";
    shortdesc = "get hostname of the operating system";
    longdesc = "\
This function returns the hostname of the operating system
as found by inspection of the guest’s configuration files.

If the hostname could not be determined, then the
string C<unknown> is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_product_variant"; added = (1, 9, 13);
    style = RString (RPlainString, "variant"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_product_variant";
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
    style = RString (RPlainString, "controlset"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_windows_current_control_set";
    shortdesc = "get Windows CurrentControlSet of inspected operating system";
    longdesc = "\
This returns the Windows CurrentControlSet of the inspected guest.
The CurrentControlSet is a registry key name such as C<ControlSet001>.

This call assumes that the guest is Windows and that the
Registry could be examined by inspection.  If this is not
the case then an error is returned.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_windows_software_hive"; added = (1, 35, 26);
    style = RString (RPlainString, "path"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_windows_software_hive";
    shortdesc = "get the path of the Windows software hive";
    longdesc = "\
This returns the path to the hive (binary Windows Registry file)
corresponding to HKLM\\SOFTWARE.

This call assumes that the guest is Windows and that the guest
has a software hive file with the right name.  If this is not the
case then an error is returned.  This call does not check that the
hive is a valid Windows Registry hive.

You can use C<guestfs_hivex_open> to read or write to the hive.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_windows_system_hive"; added = (1, 35, 26);
    style = RString (RPlainString, "path"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_windows_system_hive";
    shortdesc = "get the path of the Windows system hive";
    longdesc = "\
This returns the path to the hive (binary Windows Registry file)
corresponding to HKLM\\SYSTEM.

This call assumes that the guest is Windows and that the guest
has a system hive file with the right name.  If this is not the
case then an error is returned.  This call does not check that the
hive is a valid Windows Registry hive.

You can use C<guestfs_hivex_open> to read or write to the hive.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_build_id"; added = (1, 49, 8);
    style = RString (RPlainString, "buildid"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_build_id";
    shortdesc = "get the system build ID";
    longdesc = "\
This returns the build ID of the system, or the string
C<\"unknown\"> if the system does not have a build ID.

For Windows, this gets the build number.  Although it is
returned as a string, it is (so far) always a number.  See
L<https://en.wikipedia.org/wiki/List_of_Microsoft_Windows_versions>
for some possible values.

For Linux, this returns the C<BUILD_ID> string from
F</etc/os-release>, although this is not often used.

Please read L<guestfs(3)/INSPECTION> for more details." };

  { defaults with
    name = "inspect_get_mountpoints"; added = (1, 5, 3);
    style = RHashtable (RPlainString, RMountable, "mountpoints"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_mountpoints";
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
    style = RStringList (RMountable, "filesystems"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_filesystems";
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
    name = "inspect_get_drive_mappings"; added = (1, 9, 17);
    style = RHashtable (RPlainString, RDevice, "drives"), [String (Mountable, "root")], [];
    impl = OCaml "Inspect.inspect_get_drive_mappings";
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
    name = "internal_list_rpm_applications"; added = (1, 45, 3);
    style = RStructList ("applications2", "application2"), [], [];
    visibility = VInternal;
    impl = OCaml "Rpm.internal_list_rpm_applications";
    shortdesc = "get applications from RPM guest";
    longdesc = "\
This internal function is used by C<guestfs_inspect_list_applications2>
to list the applications for RPM guests."};

]

let non_daemon_functions = [
  { defaults with
    name = "inspect_list_applications2"; added = (1, 19, 56);
    style = RStructList ("applications2", "application2"), [String (Mountable, "root")], [];
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

The name of the application.  For Linux guests, this is the package
name.

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
    name = "inspect_get_icon"; added = (1, 11, 12);
    style = RBufferOut "icon", [String (Mountable, "root")],  [OBool "favicon"; OBool "highquality"];
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

Unlike most other inspection API calls, the guest’s disks must be
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
L<wrestool(1)> program from the C<icoutils> package, and
several programs (L<bmptopnm(1)>, L<pnmtopng(1)>, L<pamcut(1)>)
from the C<netpbm> package.  These must be installed separately.

=item *

Operating system icons are usually trademarks.  Seek legal
advice before using trademarks in applications.

=back" };

  { defaults with
    name = "inspect_get_osinfo"; added = (1, 39, 1);
    style = RString (RPlainString, "id"), [String (Mountable, "root")], [];
    shortdesc = "get a possible osinfo short ID corresponding to this operating system";
    longdesc = "\
This function returns a possible short ID for libosinfo corresponding
to the guest.

I<Note:> The returned ID is only a guess by libguestfs, and nothing
ensures that it actually exists in osinfo-db.

If no ID could not be determined, then the string C<unknown> is
returned." };

]
