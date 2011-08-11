# Sys::Guestfs::Lib
# Copyright (C) 2009-2010 Red Hat Inc.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

package Sys::Guestfs::Lib;

use strict;
use warnings;

# The minor part of this version number is incremented when some
# change is made to this module.  The major part is incremented if we
# make a change which is not backwards compatible.  It is not related
# to the libguestfs version number.
use vars qw($VERSION);
$VERSION = '0.3';

use Carp qw(croak);

use Sys::Guestfs;
use File::Temp qw/tempdir/;
use Locale::TextDomain 'libguestfs';

# Optional:
eval "use Sys::Virt;";
eval "use XML::XPath;";
eval "use XML::XPath::XMLParser;";
eval "use Win::Hivex;";

=pod

=head1 NAME

Sys::Guestfs::Lib - Useful functions for using libguestfs from Perl

=head1 SYNOPSIS

 use Sys::Guestfs::Lib qw(open_guest ...);

 $g = open_guest ($name);

=head1 DESCRIPTION

C<Sys::Guestfs::Lib> is an extra library of useful functions for using
the libguestfs API from Perl.  It also provides tighter integration
with libvirt.

The basic libguestfs API is not covered by this manpage.  Please refer
instead to L<Sys::Guestfs(3)> and L<guestfs(3)>.  The libvirt API is
also not covered.  For that, see L<Sys::Virt(3)>.

=head1 DEPRECATION OF SOME FUNCTIONS

This module contains functions and code to perform inspection of guest
images.  Since libguestfs 1.5.3 this ability has moved into the core
API (see L<guestfs(3)/INSPECTION>).  The inspection functions in this
module are deprecated and will not be updated.  Each deprecated
function is marked in the documentation below.

=head1 BASIC FUNCTIONS

=cut

require Exporter;

use vars qw(@EXPORT_OK @ISA);

@ISA = qw(Exporter);
@EXPORT_OK = qw(open_guest feature_available
  get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system inspect_in_detail
  inspect_linux_kernel);

=head2 open_guest

 $g = open_guest ($name);

 $g = open_guest ($name, rw => 1, ...);

 $g = open_guest ($name, address => $uri, ...);

 $g = open_guest ([$img1, $img2, ...], address => $uri, format => $format, ...);

 ($g, $conn, $dom, @images) = open_guest ($name);

This function opens a libguestfs handle for either the libvirt domain
called C<$name>, or the disk image called C<$name>.  Any disk images
found through libvirt or specified explicitly are attached to the
libguestfs handle.

The C<Sys::Guestfs> handle C<$g> is returned, or if there was an error
it throws an exception.  To catch errors, wrap the call in an eval
block.

The first parameter is either a string referring to a libvirt domain
or a disk image, or (if a guest has several disk images) an arrayref
C<[$img1, $img2, ...]>.  For disk images, if the C<format> parameter
is specified then that format is forced.

The handle is I<read-only> by default.  Use the optional parameter
C<rw =E<gt> 1> to open a read-write handle.  However if you open a
read-write handle, this function will refuse to use active libvirt
domains.

The handle is still in the config state when it is returned, so you
have to call C<$g-E<gt>launch ()>.

The optional C<address> parameter can be added to specify the libvirt
URI.

The implicit libvirt handle is closed after this function, I<unless>
you call the function in C<wantarray> context, in which case the
function returns a tuple of: the open libguestfs handle, the open
libvirt handle, and the open libvirt domain handle, and a list of
[image,format] pairs.  (This is useful if you want to do other things
like pulling the XML description of the guest).  Note that if this is
a straight disk image, then C<$conn> and C<$dom> will be C<undef>.

If the C<Sys::Virt> module is not available, then libvirt is bypassed,
and this function can only open disk images.

The optional C<interface> parameter can be used to open devices with a
specified qemu interface.  See L<Sys::Guestfs/guestfs_add_drive_opts>
for more details.

=cut

sub open_guest
{
    local $_;
    my $first = shift;
    my %params = @_;

    my $rw = $params{rw};
    my $address = $params{address};
    my $interface = $params{interface};
    my $format = $params{format}; # undef == autodetect

    my @images = ();
    if (ref ($first) eq "ARRAY") {
        @images = @$first;
    } elsif (ref ($first) eq "SCALAR") {
        @images = ($first);
    } else {
        croak __"open_guest: first parameter must be a string or an arrayref"
    }

    # Check each element of @images is defined.
    # (See https://bugzilla.redhat.com/show_bug.cgi?id=601092#c3).
    foreach (@images) {
        croak __"open_guest: first argument contains undefined element"
            unless defined $_;
    }

    my ($conn, $dom);

    if (-e $images[0]) {
        foreach (@images) {
            croak __x("guest image {imagename} does not exist or is not readable",
                    imagename => $_)
                unless -r $_;
        }

        @images = map { [ $_, $format ] } @images;
    } else {
        die __"open_guest: no libvirt support (install Sys::Virt, XML::XPath and XML::XPath::XMLParser)"
            unless exists $INC{"Sys/Virt.pm"} &&
            exists $INC{"XML/XPath.pm"} &&
            exists $INC{"XML/XPath/XMLParser.pm"};

        die __"open_guest: too many domains listed on command line"
            if @images > 1;

        my @libvirt_args = ();
        push @libvirt_args, address => $address if defined $address;

        $conn = Sys::Virt->new (readonly => 1, @libvirt_args);
        die __"open_guest: cannot connect to libvirt" unless $conn;

        my @doms = $conn->list_defined_domains ();
        my $isitinactive = 1;
        unless ($rw) {
            # In the case where we want read-only access to a domain,
            # allow the user to specify an active domain too.
            push @doms, $conn->list_domains ();
            $isitinactive = 0;
        }
        foreach (@doms) {
            if ($_->get_name () eq $images[0]) {
                $dom = $_;
                last;
            }
        }

        unless ($dom) {
            if ($isitinactive) {
                die __x("{imagename} is not the name of an inactive libvirt domain\n",
                        imagename => $images[0]);
            } else {
                die __x("{imagename} is not the name of a libvirt domain\n",
                        imagename => $images[0]);
            }
        }

        # Get the names of the image(s).
        my $xml = $dom->get_xml_description ();

        my $p = XML::XPath->new (xml => $xml);
        my $nodes = $p->find ('//devices/disk');

        my @disks = ();
        my $node;
        foreach $node ($nodes->get_nodelist) {
            # The filename can be in dev or file attribute, hence:
            my $filename = $p->find ('./source/@dev', $node);
            unless ($filename) {
                $filename = $p->find ('./source/@file', $node);
                next unless $filename;
            }
            $filename = $filename->to_literal;

            # Get the disk format (may not be set).
            my $format = $p->find ('./driver/@type', $node);
            $format = $format->to_literal if $format;

            push @disks, [ $filename, $format ];
        }

        die __x("{imagename} seems to have no disk devices\n",
                imagename => $images[0])
            unless @disks;

        @images = @disks;
    }

    # We've now got the list of @images, so feed them to libguestfs.
    my $g = Sys::Guestfs->new ();
    foreach (@images) {
        my @args = ($_->[0]);
        push @args, format => $_->[1] if defined $_->[1];
        push @args, readonly => 1 unless $rw;
        push @args, iface => $interface if defined $interface;
        $g->add_drive_opts (@args);
    }

    return wantarray ? ($g, $conn, $dom, @images) : $g
}

=head2 feature_available

 $bool = feature_available ($g, $feature [, $feature ...]);

This function is a useful wrapper around the basic
C<$g-E<gt>available> call.

C<$g-E<gt>available> tests for availability of a list of features and
dies with an error if any is not available.

This call tests for the list of features and returns true if all are
available, or false otherwise.

For a list of features you can test for, see L<guestfs(3)/AVAILABILITY>.

=cut

sub feature_available {
    my $g = shift;

    eval { $g->available (\@_); };
    return $@ ? 0 : 1;
}

=head2 get_partitions

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API function L<Sys::Guestfs(3)/list_filesystems> instead.

=cut

sub get_partitions
{
    local $_;
    my $g = shift;

    # Look to see if any devices directly contain filesystems (RHBZ#590167).
    my @devices = $g->list_devices ();
    my @fses_on_device = ();
    foreach (@devices) {
        eval { $g->mount_ro ($_, "/"); };
        push @fses_on_device, $_ unless $@;
        $g->umount_all ();
    }

    my @partitions = $g->list_partitions ();
    my @pvs = $g->pvs ();
    @partitions = grep { ! _is_pv ($_, @pvs) } @partitions;

    my @lvs;
    @lvs = $g->lvs () if feature_available ($g, "lvm2");

    return sort (@fses_on_device, @lvs, @partitions);
}

sub _is_pv {
    local $_;
    my $t = shift;

    foreach (@_) {
        return 1 if $_ eq $t;
    }
    0;
}

=head2 resolve_windows_path

 $path = resolve_windows_path ($g, $path);

 $path = resolve_windows_path ($g, "/windows/system");
   ==> "/WINDOWS/System"
       or undef if no path exists

This function, which is specific to FAT/NTFS filesystems (ie.  Windows
guests), lets you look up a case insensitive C<$path> in the
filesystem and returns the true, case sensitive path as required by
the underlying kernel or NTFS-3g driver.

If C<$path> does not exist then this function returns C<undef>.

The C<$path> parameter must begin with C</> character and be separated
by C</> characters.  Do not use C<\>, drive names, etc.

=cut

sub resolve_windows_path
{
    my $g = shift;
    my $path = shift;

    my $r;
    eval { $r = $g->case_sensitive_path ($path); };
    return $r;
}

=head2 file_architecture

Deprecated function.  Replace any calls to this function with:

 $g->file_architecture ($path);

=cut

sub file_architecture
{
    my $g = shift;
    my $path = shift;

    return $g->file_architecture ($path);
}

=head1 OPERATING SYSTEM INSPECTION FUNCTIONS

=head2 inspect_all_partitions

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

# Turn /dev/vd* and /dev/hd* into canonical device names
# (see BLOCK DEVICE NAMING in guestfs(3)).

sub _canonical_dev ($)
{
    my ($dev) = @_;
    return "/dev/sd$1" if $dev =~ m{^/dev/[vh]d(\w+)};
    return $dev;
}

sub inspect_all_partitions
{
    local $_;
    my $g = shift;
    my $parts = shift;
    my @parts = @$parts;
    return map { _canonical_dev ($_) => inspect_partition ($g, $_) } @parts;
}

=head2 inspect_partition

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

sub inspect_partition
{
    local $_;
    my $g = shift;
    my $dev = shift;		# LV or partition name.

    my %r;			# Result hash.

    # First try 'file(1)' on it.
    my $file = $g->file ($dev);
    if ($file =~ /ext2 filesystem data/) {
        $r{fstype} = "ext2";
        $r{fsos} = "linux";
    } elsif ($file =~ /ext3 filesystem data/) {
        $r{fstype} = "ext3";
        $r{fsos} = "linux";
    } elsif ($file =~ /ext4 filesystem data/) {
        $r{fstype} = "ext4";
        $r{fsos} = "linux";
    } elsif ($file =~ m{Linux/i386 swap file}) {
        $r{fstype} = "swap";
        $r{fsos} = "linux";
        $r{is_swap} = 1;
    }

    # If it's ext2/3/4, then we want the UUID and label.
    if (exists $r{fstype} && $r{fstype} =~ /^ext/) {
        $r{uuid} = $g->get_e2uuid ($dev);
        $r{label} = $g->get_e2label ($dev);
    }

    # Try mounting it, fnarrr.
    if (!$r{is_swap}) {
        $r{is_mountable} = 1;
        eval { $g->mount_ro ($dev, "/") };
        if ($@) {
            # It's not mountable, probably empty or some format
            # we don't understand.
            $r{is_mountable} = 0;
            goto OUT;
        }

        # Grub /boot?
        if ($g->is_file ("/grub/menu.lst") ||
            $g->is_file ("/grub/grub.conf")) {
            $r{content} = "linux-grub";
            _check_grub ($g, \%r);
            goto OUT;
        }

        # Linux root?
        if ($g->is_dir ("/etc") && $g->is_dir ("/bin") &&
            $g->is_file ("/etc/fstab")) {
            $r{content} = "linux-root";
            $r{is_root} = 1;
            _check_linux_root ($g, \%r);
            goto OUT;
        }

        # Linux /usr/local.
        if ($g->is_dir ("/etc") && $g->is_dir ("/bin") &&
            $g->is_dir ("/share") && !$g->exists ("/local") &&
            !$g->is_file ("/etc/fstab")) {
            $r{content} = "linux-usrlocal";
            goto OUT;
        }

        # Linux /usr.
        if ($g->is_dir ("/etc") && $g->is_dir ("/bin") &&
            $g->is_dir ("/share") && $g->exists ("/local") &&
            !$g->is_file ("/etc/fstab")) {
            $r{content} = "linux-usr";
            goto OUT;
        }

        # Windows root?
        if ($g->is_file ("/AUTOEXEC.BAT") ||
            $g->is_file ("/autoexec.bat") ||
            $g->is_dir ("/Program Files") ||
            $g->is_dir ("/WINDOWS") ||
            $g->is_file ("/boot.ini") ||
            $g->is_file ("/ntldr")) {
            $r{fstype} = "ntfs"; # XXX this is a guess
            $r{fsos} = "windows";
            $r{content} = "windows-root";
            $r{is_root} = 1;
            _check_windows_root ($g, \%r);
            goto OUT;
        }
    }

  OUT:
    $g->umount_all ();
    return \%r;
}

sub _check_linux_root
{
    local $_;
    my $g = shift;
    my $r = shift;

    # Look into /etc to see if we recognise the operating system.
    # N.B. don't use $g->is_file here, because it might be a symlink
    if ($g->exists ("/etc/redhat-release")) {
        $r->{package_format} = "rpm";

        $_ = $g->cat ("/etc/redhat-release");
        if (/Fedora release (\d+)(?:\.(\d+))?/) {
            chomp; $r->{product_name} = $_;
            $r->{osdistro} = "fedora";
            $r->{os_major_version} = "$1";
            $r->{os_minor_version} = "$2" if(defined($2));
            $r->{package_management} = "yum";
        }

        elsif (/(Red Hat|CentOS|Scientific Linux)/) {
            chomp; $r->{product_name} = $_;

            my $distro = $1;

            if($distro eq "Red Hat") {
                $r->{osdistro} = "rhel";
            }

            elsif($distro eq "CentOS") {
                $r->{osdistro} = "centos";
                $r->{package_management} = "yum";
            }

            elsif($distro eq "Scientific Linux") {
                $r->{osdistro} = "scientific";
                $r->{package_management} = "yum";
            }

            # Shouldn't be possible
            else { die };

            if (/$distro.*release (\d+).*Update (\d+)/) {
                $r->{os_major_version} = "$1";
                $r->{os_minor_version} = "$2";
            }

            elsif (/$distro.*release (\d+)(?:\.(\d+))?/) {
                $r->{os_major_version} = "$1";

                if(defined($2)) {
                    $r->{os_minor_version} = "$2";
                } else {
                    $r->{os_minor_version} = "0";
                }
            }

            # Package management in RHEL changed in version 5
            if ($r->{osdistro} eq "rhel") {
                if ($r->{os_major_version} >= 5) {
                    $r->{package_management} = "yum";
                } else {
                    $r->{package_management} = "rhn";
                }
            }
        }

        else {
            $r->{osdistro} = "redhat-based";
        }
    } elsif ($g->is_file ("/etc/debian_version")) {
        $r->{package_format} = "deb";
        $r->{package_management} = "apt";

        $_ = $g->cat ("/etc/debian_version");
        if (/(\d+)\.(\d+)/) {
            chomp; $r->{product_name} = $_;
            $r->{osdistro} = "debian";
            $r->{os_major_version} = "$1";
            $r->{os_minor_version} = "$2";
        } else {
            $r->{osdistro} = "debian";
        }
    }

    # Parse the contents of /etc/fstab.  This is pretty vital so
    # we can determine where filesystems are supposed to be mounted.
    eval "\$_ = \$g->cat ('/etc/fstab');";
    if (!$@ && $_) {
        my @lines = split /\n/;
        my @fstab;
        foreach (@lines) {
            my @fields = split /[ \t]+/;
            if (@fields >= 2) {
                my $spec = $fields[0]; # first column (dev/label/uuid)
                my $file = $fields[1]; # second column (mountpoint)
                if ($spec =~ m{^/} ||
                    $spec =~ m{^LABEL=} ||
                    $spec =~ m{^UUID=} ||
                    $file eq "swap") {
                    push @fstab, [$spec, $file]
                }
            }
        }
        $r->{fstab} = \@fstab if @fstab;
    }

    # Determine the architecture of this root.
    my $arch;
    foreach ("/bin/bash", "/bin/ls", "/bin/echo", "/bin/rm", "/bin/sh") {
        if ($g->is_file ($_)) {
            $arch = file_architecture ($g, $_);
            last;
        }
    }

    $r->{arch} = $arch if defined $arch;
}

# We only support NT.  The control file /boot.ini contains a list of
# Windows installations and their %systemroot%s in a simple text
# format.
#
# XXX We don't handle the case where /boot.ini is on a different
# partition very well (Windows Vista and later).

sub _check_windows_root
{
    local $_;
    my $g = shift;
    my $r = shift;

    my $boot_ini = resolve_windows_path ($g, "/boot.ini");
    $r->{boot_ini} = $boot_ini;

    my $systemroot;
    if (defined $r->{boot_ini}) {
        $_ = $g->cat ($boot_ini);
        my @lines = split /\n/;
        my $section;
        foreach (@lines) {
            if (m/\[.*\]/) {
                $section = $1;
            } elsif (m/^default=.*?\\(\w+)$/i) {
                $systemroot = $1;
                last;
            } elsif (m/\\(\w+)=/) {
                $systemroot = $1;
                last;
            }
        }
    }

    if (!defined $systemroot) {
        # Last ditch ... try to guess %systemroot% location.
        foreach ("windows", "winnt") {
            my $dir = resolve_windows_path ($g, "/$_/system32");
            if (defined $dir) {
                $systemroot = $_;
                last;
            }
        }
    }

    if (defined $systemroot) {
        $r->{systemroot} = resolve_windows_path ($g, "/$systemroot");
        if (defined $r->{systemroot}) {
            _check_windows_arch ($g, $r, $r->{systemroot});
            _check_windows_registry ($g, $r, $r->{systemroot});
        }
    }
}

# Find Windows userspace arch.

sub _check_windows_arch
{
    local $_;
    my $g = shift;
    my $r = shift;
    my $systemroot = shift;

    my $cmd_exe =
        resolve_windows_path ($g, $r->{systemroot} . "/system32/cmd.exe");
    $r->{arch} = file_architecture ($g, $cmd_exe) if $cmd_exe;
}

sub _check_windows_registry
{
    local $_;
    my $g = shift;
    my $r = shift;
    my $systemroot = shift;

    # Download the system registry files.  Only download the
    # interesting ones (SOFTWARE and SYSTEM).  We don't bother with
    # the user ones.

    return unless exists $INC{"Win/Hivex.pm"};

    my $configdir = resolve_windows_path ($g, "$systemroot/system32/config");
    return unless defined $configdir;

    my $tmpdir = tempdir (CLEANUP => 1);

    my $software = resolve_windows_path ($g, "$configdir/software");
    my $software_hive;
    if (defined $software) {
        eval {
            $g->download ($software, "$tmpdir/software");
            $software_hive = Win::Hivex->open ("$tmpdir/software");
        };
        warn "$@\n" if $@;
        $r->{windows_software_hive} = $software;
    }

    my $system = resolve_windows_path ($g, "$configdir/system");
    my $system_hive;
    if (defined $system) {
        eval {
            $g->download ($system, "$tmpdir/system");
            $system_hive = Win::Hivex->open ("$tmpdir/system");
        };
        warn "$@\n" if $@;
        $r->{windows_system_hive} = $system;
    }

    # Get the ProductName, major and minor version, etc.
    if (defined $software_hive) {
        my $cv_node;
        eval {
            $cv_node = $software_hive->root;
            $cv_node = $software_hive->node_get_child ($cv_node, $_)
                foreach ("Microsoft", "Windows NT", "CurrentVersion");
        };
        warn "$@\n" if $@;

        if ($cv_node) {
            my @values = $software_hive->node_values ($cv_node);

            foreach (@values) {
                my $k = $software_hive->value_key ($_);
                if ($k eq "ProductName") {
                    $_ = $software_hive->value_string ($_);
                    $r->{product_name} = $_ if defined $_;
                } elsif ($k eq "CurrentVersion") {
                    $_ = $software_hive->value_string ($_);
                    if (defined $_ && m/^(\d+)\.(\d+)/) {
                        $r->{os_major_version} = $1;
                        $r->{os_minor_version} = $2;
                    }
                } elsif ($k eq "CurrentBuild") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_current_build} = $_ if defined $_;
                } elsif ($k eq "SoftwareType") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_software_type} = $_ if defined $_;
                } elsif ($k eq "CurrentType") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_current_type} = $_ if defined $_;
                } elsif ($k eq "RegisteredOwner") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_registered_owner} = $_ if defined $_;
                } elsif ($k eq "RegisteredOrganization") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_registered_organization} = $_ if defined $_;
                } elsif ($k eq "InstallationType") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_installation_type} = $_ if defined $_;
                } elsif ($k eq "EditionID") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_edition_id} = $_ if defined $_;
                } elsif ($k eq "ProductID") {
                    $_ = $software_hive->value_string ($_);
                    $r->{windows_product_id} = $_ if defined $_;
                }
            }
        }
    }
}

sub _check_grub
{
    local $_;
    my $g = shift;
    my $r = shift;

    # Grub version, if we care.
}

=head2 inspect_operating_systems

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

sub inspect_operating_systems
{
    local $_;
    my $g = shift;
    my $fses = shift;

    my %oses = ();

    foreach (sort keys %$fses) {
        if ($fses->{$_}->{is_root}) {
            my %r = (
                root => $fses->{$_},
                root_device => $_
                );
            _get_os_version ($g, \%r);
            _assign_mount_points ($g, $fses, \%r);
            $oses{$_} = \%r;
        }
    }

    # If we didn't find any operating systems then it's an error (RHBZ#591142).
    if (0 == keys %oses) {
        die __"No operating system could be detected inside this disk image.\n\nThis may be because the file is not a disk image, or is not a virtual machine\nimage, or because the OS type is not understood by virt-inspector.\n\nIf you feel this is an error, please file a bug report including as much\ninformation about the disk image as possible.\n";
    }

    return \%oses;
}

sub _get_os_version
{
    local $_;
    my $g = shift;
    my $r = shift;

    $r->{os} = $r->{root}->{fsos} if exists $r->{root}->{fsos};
    $r->{product_name} = $r->{root}->{product_name}
        if exists $r->{root}->{product_name};
    $r->{distro} = $r->{root}->{osdistro} if exists $r->{root}->{osdistro};
    $r->{major_version} = $r->{root}->{os_major_version}
        if exists $r->{root}->{os_major_version};
    $r->{minor_version} = $r->{root}->{os_minor_version}
        if exists $r->{root}->{os_minor_version};
    $r->{package_format} = $r->{root}->{package_format}
        if exists $r->{root}->{package_format};
    $r->{package_management} = $r->{root}->{package_management}
        if exists $r->{root}->{package_management};
    $r->{arch} = $r->{root}->{arch} if exists $r->{root}->{arch};
}

sub _assign_mount_points
{
    local $_;
    my $g = shift;
    my $fses = shift;
    my $r = shift;

    $r->{mounts} = { "/" => $r->{root_device} };
    $r->{filesystems} = { $r->{root_device} => $r->{root} };

    # Use /etc/fstab if we have it to mount the rest.
    if (exists $r->{root}->{fstab}) {
        my @fstab = @{$r->{root}->{fstab}};
        foreach (@fstab) {
            my ($spec, $file) = @$_;

            my ($dev, $fs) = _find_filesystem ($g, $fses, $spec, $file);
            if ($dev) {
                $r->{mounts}->{$file} = $dev;
                $r->{filesystems}->{$dev} = $fs;
                if (exists $fs->{used}) {
                    $fs->{used}++
                } else {
                    $fs->{used} = 1
                }
                $fs->{spec} = $spec;
            }
        }
    }
}

# Find filesystem by device name, LABEL=.. or UUID=..
sub _find_filesystem
{
    my $g = shift;
    my $fses = shift;
    local $_ = shift;
    my $file = shift;

    if (/^LABEL=(.*)/) {
        my $label = $1;
        my $dev;
        eval {
            $dev = $g->findfs_label ($label);
        };
        warn "unknown filesystem LABEL=$label in /etc/fstab: $@\n" if $@;
        return () if !defined $dev;
        $dev = _canonical_dev ($dev);
        return ($dev, $fses->{$dev}) if exists $fses->{$dev};
        # Otherwise return nothing.  It's just a filesystem that we are
        # ignoring, eg. swap.
        return ();
    } elsif (/^UUID=(.*)/) {
        my $uuid = $1;
        my $dev;
        eval {
            $dev = $g->findfs_uuid ($uuid);
        };
        warn "unknown filesystem UUID=$uuid in /etc/fstab: $@\n" if $@;
        return () if !defined $dev;
        $dev = _canonical_dev ($dev);
        return ($dev, $fses->{$dev}) if exists $fses->{$dev};
        # Otherwise return nothing.  It's just a filesystem that we are
        # ignoring, eg. swap.
        return ();
    } else {
        return ($_, $fses->{$_}) if exists $fses->{$_};

        # The following is to handle the case where an fstab entry specifies a
        # specific device rather than its label or uuid, and the libguestfs
        # appliance has named the device differently due to the use of a
        # different driver.
        # This will work as long as the underlying drivers recognise devices in
        # the same order.
        if (m{^/dev/hd(.*)} && exists $fses->{"/dev/sd$1"}) {
            return ("/dev/sd$1", $fses->{"/dev/sd$1"});
        }
        if (m{^/dev/vd(.*)} && exists $fses->{"/dev/sd$1"}) {
            return ("/dev/sd$1", $fses->{"/dev/sd$1"});
        }
        if (m{^/dev/xvd(.*)} && exists $fses->{"/dev/sd$1"}) {
            return ("/dev/sd$1", $fses->{"/dev/sd$1"});
        }
        if (m{^/dev/mapper/(.*)-(.*)$} && exists $fses->{"/dev/$1/$2"}) {
            return ("/dev/$1/$2", $fses->{"/dev/$1/$2"});
        }

	return () if $file =~ (/media\/cdrom/);
        return () if m{/dev/cdrom};
        return () if m{/dev/fd0};

        warn __x("unknown filesystem {fs}\n", fs => $_);
        return ();
    }
}

=head2 mount_operating_system

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

sub mount_operating_system
{
    local $_;
    my $g = shift;
    my $os = shift;
    my $ro = shift;		# Read-only?

    $ro = 1 unless defined $ro; # ro defaults to 1 if unspecified

    my $mounts = $os->{mounts};

    # Have to mount / first.  Luckily '/' is early in the ASCII
    # character set, so this should be OK.
    foreach (sort keys %$mounts) {
        if($_ ne "swap" && $_ ne "none" && ($_ eq '/' || $g->is_dir ($_))) {
            if($ro) {
                $g->mount_ro ($mounts->{$_}, $_)
            } else {
                $g->mount_options ("", $mounts->{$_}, $_)
            }
        }
    }
}

=head2 inspect_in_detail

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

sub inspect_in_detail
{
    local $_;
    my $g = shift;
    my $os = shift;

    _check_for_applications ($g, $os);
    _check_for_kernels ($g, $os);
    if ($os->{os} eq "linux") {
        _find_modprobe_aliases ($g, $os);
    }
}

sub _check_for_applications
{
    local $_;
    my $g = shift;
    my $os = shift;

    my @apps;

    my $osn = $os->{os};
    if ($osn eq "linux") {
        my $package_format = $os->{package_format};
        if (defined $package_format && $package_format eq "rpm") {
            my @lines = ();
            eval {
                @lines = $g->command_lines
                    (["rpm",
                      "-q", "-a", "--qf",
                      "%{name} %{epoch} %{version} %{release} %{arch}\n"]);
            };

            warn(__x("Error running rpm -qa: {error}", error => $@)) if ($@);

            @lines = sort @lines;
            foreach (@lines) {
                if (m/^(.*) (.*) (.*) (.*) (.*)$/) {
                    my $epoch = $2;
                    undef $epoch if $epoch eq "(none)";
                    my $app = {
                        name => $1,
                        epoch => $epoch,
                        version => $3,
                        release => $4,
                        arch => $5
                    };
                    push @apps, $app
                }
            }
        } elsif (defined $package_format && $package_format eq "deb") {
            my @lines = ();
            eval {
                @lines = $g->command_lines
                    (["dpkg-query",
                      "-f", '${Package} ${Version} ${Architecture} ${Status}\n',
                      "-W"]);
            };

            warn(__x("Error running dpkg-query: {error}", error => $@)) if ($@);

            @lines = sort @lines;
            foreach (@lines) {
                if (m/^(.*) (.*) (.*) (.*) (.*) (.*)$/) {
                    if ( $6 eq "installed" ) {
                        my $app = {
                            name => $1,
                            version => $2,
                            arch => $3
                        };
                        push @apps, $app
                    }
                }
            }
        }
    } elsif ($osn eq "windows") {
        # XXX
        # I worked out a general plan for this, but haven't
        # implemented it yet.  We can iterate over /Program Files
        # looking for *.EXE files, which we download, then use
        # i686-pc-mingw32-windres on, to find the VERSIONINFO
        # section, which has a lot of useful information.
    }

    $os->{apps} = \@apps;
}

# Find the path which needs to be prepended to paths in grub.conf to make them
# absolute
sub _find_grub_prefix
{
    my ($g, $os) = @_;

    my $fses = $os->{filesystems};
    die("filesystems undefined") unless(defined($fses));

    # Look for the filesystem which contains grub
    my $grubdev;
    foreach my $dev (keys(%$fses)) {
        my $fsinfo = $fses->{$dev};
        if(exists($fsinfo->{content}) && $fsinfo->{content} eq "linux-grub") {
            $grubdev = $dev;
            last;
        }
    }

    my $mounts = $os->{mounts};
    die("mounts undefined") unless(defined($mounts));

    # Find where the filesystem is mounted
    if(defined($grubdev)) {
        foreach my $mount (keys(%$mounts)) {
            if($mounts->{$mount} eq $grubdev) {
                return "" if($mount eq '/');
                return $mount;
            }
        }

        die("$grubdev defined in filesystems, but not in mounts");
    }

    # If we didn't find it, look for /boot/grub/menu.lst, then try to work out
    # what filesystem it's on. We use menu.lst rather than grub.conf because
    # debian only uses menu.lst, and anaconda creates a symlink for it.
    die(__"Can't find grub on guest") unless($g->exists('/boot/grub/menu.lst'));

    # Look for the most specific mount point in mounts
    foreach my $path (qw(/boot/grub /boot /)) {
        if(exists($mounts->{$path})) {
            return "" if($path eq '/');
            return $path;
        }
    }

    die("Couldn't determine which filesystem holds /boot/grub/menu.lst");
}

sub _check_for_kernels
{
    my ($g, $os) = @_;

    if ($os->{os} eq "linux" && feature_available ($g, "augeas")) {
        # Iterate over entries in grub.conf, populating $os->{boot}
        # For every kernel we find, inspect it and add to $os->{kernels}

        my $grub = _find_grub_prefix($g, $os);
        my $grub_conf = "/etc/grub.conf";

        # Debian and other's have no /etc/grub.conf:
        if ( ! -f "$grub_conf" ) {
            $grub_conf = "$grub/grub/menu.lst";
        }

        my @boot_configs;

        # We want
        #  $os->{boot}
        #       ->{configs}
        #         ->[0]
        #           ->{title}   = "Fedora (2.6.29.6-213.fc11.i686.PAE)"
        #           ->{kernel}  = \kernel
        #           ->{cmdline} = "ro root=/dev/mapper/vg_mbooth-lv_root rhgb"
        #           ->{initrd}  = \initrd
        #       ->{default} = \config
        #       ->{grub_fs} = "/boot"
        # Initialise augeas
        $g->aug_init("/", 16);

        my @configs = ();
        # Get all configurations from grub
        foreach my $bootable
            ($g->aug_match("/files/$grub_conf/title"))
        {
            my %config = ();
            $config{title} = $g->aug_get($bootable);

            my $grub_kernel;
            eval { $grub_kernel = $g->aug_get("$bootable/kernel"); };
            if($@) {
                warn __x("Grub entry {title} has no kernel",
                         title => $config{title});
            }

            # Check we've got a kernel entry
            if(defined($grub_kernel)) {
                my $path = "$grub$grub_kernel";

                # Reconstruct the kernel command line
                my @args = ();
                foreach my $arg ($g->aug_match("$bootable/kernel/*")) {
                    $arg =~ m{/kernel/([^/]*)$}
                        or die("Unexpected return from aug_match: $arg");

                    my $name = $1;
                    my $value;
                    eval { $value = $g->aug_get($arg); };

                    if(defined($value)) {
                        push(@args, "$name=$value");
                    } else {
                        push(@args, $name);
                    }
                }
                $config{cmdline} = join(' ', @args) if(scalar(@args) > 0);

                my $kernel;
                if ($g->exists($path)) {
                    $kernel =
                        inspect_linux_kernel($g, $path, $os->{package_format});
                } else {
                    warn __x("grub refers to {path}, which doesn't exist\n",
                             path => $path);
                }

                # Check the kernel was recognised
                if(defined($kernel)) {
                    # Put this kernel on the top level kernel list
                    $os->{kernels} ||= [];
                    push(@{$os->{kernels}}, $kernel);

                    $config{kernel} = $kernel;

                    # Look for an initrd entry
                    my $initrd;
                    eval {
                        $initrd = $g->aug_get("$bootable/initrd");
                    };

                    unless($@) {
                        $config{initrd} =
                            _inspect_initrd($g, $os, "$grub$initrd",
                                            $kernel->{version});
                    } else {
                        warn __x("Grub entry {title} does not specify an ".
                                 "initrd", title => $config{title});
                    }
                }
            }

            push(@configs, \%config);
        }


        # Create the top level boot entry
        my %boot;
        $boot{configs} = \@configs;
        $boot{grub_fs} = $grub;

        # Add the default configuration
        eval {
            $boot{default} = $g->aug_get("/files/$grub_conf/default");
        };

        $os->{boot} = \%boot;
    }

    elsif ($os->{os} eq "windows") {
        # XXX
    }
}

=head2 inspect_linux_kernel

This function is deprecated.  It will not be updated in future
versions of libguestfs.  New code should not use this function.  Use
the core API functions instead, see L<guestfs(3)/INSPECTION>.

=cut

sub inspect_linux_kernel
{
    my ($g, $path, $package_format) = @_;

    my %kernel = ();

    $kernel{path} = $path;

    # If this is a packaged kernel, try to work out the name of the package
    # which installed it. This lets us know what to install to replace it with,
    # e.g. kernel, kernel-smp, kernel-hugemem, kernel-PAE
    if($package_format eq "rpm") {
        my $package;
        eval { $package = $g->command(['rpm', '-qf', '--qf',
                                       '%{NAME}', $path]); };
        $kernel{package} = $package if defined($package);;
    }

    # Try to get the kernel version by running file against it
    my $version;
    my $filedesc = $g->file($path);
    if($filedesc =~ /^$path: Linux kernel .*\bversion\s+(\S+)\b/) {
        $version = $1;
    }

    # Sometimes file can't work out the kernel version, for example because it's
    # a Xen PV kernel. In this case try to guess the version from the filename
    else {
        if($path =~ m{/boot/vmlinuz-(.*)}) {
            $version = $1;

            # Check /lib/modules/$version exists
            if(!$g->is_dir("/lib/modules/$version")) {
                warn __x("Didn't find modules directory {modules} for kernel ".
                         "{path}", modules => "/lib/modules/$version",
                         path => $path);

                # Give up
                return undef;
            }
        } else {
            warn __x("Couldn't guess kernel version number from path for ".
                     "kernel {path}", path => $path);

            # Give up
            return undef;
        }
    }

    $kernel{version} = $version;

    # List modules.
    my @modules;
    my $any_module;
    my $prefix = "/lib/modules/$version";
    foreach my $module ($g->find ($prefix)) {
        if ($module =~ m{/([^/]+)\.(?:ko|o)$}) {
            $any_module = "$prefix$module" unless defined $any_module;
            push @modules, $1;
        }
    }

    $kernel{modules} = \@modules;

    # Determine kernel architecture by looking at the arch
    # of any kernel module.
    $kernel{arch} = file_architecture ($g, $any_module);

    return \%kernel;
}

# Find all modprobe aliases. Specifically, this looks in the following
# locations:
#  * /etc/conf.modules
#  * /etc/modules.conf
#  * /etc/modprobe.conf
#  * /etc/modprobe.d/*

sub _find_modprobe_aliases
{
    local $_;
    my $g = shift;
    my $os = shift;

    # Initialise augeas
    $g->aug_init("/", 16);

    my %modprobe_aliases;

    for my $pattern (qw(/files/etc/conf.modules/alias
                        /files/etc/modules.conf/alias
                        /files/etc/modprobe.conf/alias
                        /files/etc/modprobe.d/*/alias)) {
        for my $path ( $g->aug_match($pattern) ) {
            $path =~ m{^/files(.*)/alias(?:\[\d*\])?$}
                or die __x("{path} doesn't match augeas pattern",
                           path => $path);
            my $file = $1;

            my $alias;
            $alias = $g->aug_get($path);

            my $modulename;
            $modulename = $g->aug_get($path.'/modulename');

            my %aliasinfo;
            $aliasinfo{modulename} = $modulename;
            $aliasinfo{augeas} = $path;
            $aliasinfo{file} = $file;

            $modprobe_aliases{$alias} = \%aliasinfo;
        }
    }

    $os->{modprobe_aliases} = \%modprobe_aliases;
}

# Get a listing of device drivers from an initrd
sub _inspect_initrd
{
    my ($g, $os, $path, $version) = @_;

    my @modules;

    # Disregard old-style compressed ext2 files and only work with real
    # compressed cpio files, since cpio takes ages to (fail to) process anything
    # else.
    if ($g->exists($path) && $g->file($path) =~ /cpio/) {
        eval {
            @modules = $g->initrd_list ($path);
        };
        unless ($@) {
            @modules = grep { m{([^/]+)\.(?:ko|o)$} } @modules;
        } else {
            warn __x("{filename}: could not read initrd format",
                     filename => "$path");
        }
    }

    # Add to the top level initrd_modules entry
    $os->{initrd_modules} ||= {};
    $os->{initrd_modules}->{$version} = \@modules;

    return \@modules;
}

1;

=head1 COPYRIGHT

Copyright (C) 2009-2010 Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<virt-inspector(1)>,
L<Sys::Guestfs(3)>,
L<guestfs(3)>,
L<http://libguestfs.org/>,
L<Sys::Virt(3)>,
L<http://libvirt.org/>,
L<guestfish(1)>.

=cut
