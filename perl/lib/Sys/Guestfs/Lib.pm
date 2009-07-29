# Sys::Guestfs::Lib
# Copyright (C) 2009 Red Hat Inc.
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

use Sys::Guestfs;
use File::Temp qw/tempdir/;
use Locale::TextDomain 'libguestfs';

# Optional:
eval "use Sys::Virt;";
eval "use XML::XPath;";
eval "use XML::XPath::XMLParser;";

=pod

=head1 NAME

Sys::Guestfs::Lib - Useful functions for using libguestfs from Perl

=head1 SYNOPSIS

 use Sys::Guestfs::Lib qw(open_guest inspect_all_partitions ...);

 $g = open_guest ($name);

 %fses = inspect_all_partitions ($g, \@partitions);

(and many more calls - see the rest of this manpage)

=head1 DESCRIPTION

C<Sys::Guestfs::Lib> is an extra library of useful functions for using
the libguestfs API from Perl.  It also provides tighter integration
with libvirt.

The basic libguestfs API is not covered by this manpage.  Please refer
instead to L<Sys::Guestfs(3)> and L<guestfs(3)>.  The libvirt API is
also not covered.  For that, see L<Sys::Virt(3)>.

=head1 BASIC FUNCTIONS

=cut

require Exporter;

use vars qw(@EXPORT_OK @ISA);

@ISA = qw(Exporter);
@EXPORT_OK = qw(open_guest get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system inspect_in_detail);

=head2 open_guest

 $g = open_guest ($name);

 $g = open_guest ($name, rw => 1, ...);

 $g = open_guest ($name, address => $uri, ...);

 $g = open_guest ([$img1, $img2, ...], address => $uri, ...);

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
C<[$img1, $img2, ...]>.

The handle is I<read-only> by default.  Use the optional parameter
C<rw =E<gt> 1> to open a read-write handle.  However if you open a
read-write handle, this function will refuse to use active libvirt
domains.

The handle is still in the config state when it is returned, so you
have to call C<$g-E<gt>launch ()> and C<$g-E<gt>wait_ready>.

The optional C<address> parameter can be added to specify the libvirt
URI.  In addition, L<Sys::Virt(3)> lists other parameters which are
passed through to C<Sys::Virt-E<gt>new> unchanged.

The implicit libvirt handle is closed after this function, I<unless>
you call the function in C<wantarray> context, in which case the
function returns a tuple of: the open libguestfs handle, the open
libvirt handle, and the open libvirt domain handle, and a list of
images.  (This is useful if you want to do other things like pulling
the XML description of the guest).  Note that if this is a straight
disk image, then C<$conn> and C<$dom> will be C<undef>.

If the C<Sys::Virt> module is not available, then libvirt is bypassed,
and this function can only open disk images.

=cut

sub open_guest
{
    local $_;
    my $first = shift;
    my %params = @_;

    my $readwrite = $params{rw};

    my @images = ();
    if (ref ($first) eq "ARRAY") {
	@images = @$first;
    } elsif (ref ($first) eq "SCALAR") {
	@images = ($first);
    } else {
	die __"open_guest: first parameter must be a string or an arrayref"
    }

    my ($conn, $dom);

    if (-e $images[0]) {
	foreach (@images) {
	    die __x("guest image {imagename} does not exist or is not readable",
		    imagename => $_)
		unless -r $_;
	}
    } else {
	die __"open_guest: no libvirt support (install Sys::Virt, XML::XPath and XML::XPath::XMLParser)"
	    unless exists $INC{"Sys/Virt.pm"} &&
	    exists $INC{"XML/XPath.pm"} &&
	    exists $INC{"XML/XPath/XMLParser.pm"};

	die __"open_guest: too many domains listed on command line"
	    if @images > 1;

	$conn = Sys::Virt->new (readonly => 1, @_);
	die __"open_guest: cannot connect to libvirt" unless $conn;

	my @doms = $conn->list_defined_domains ();
	my $isitinactive = 1;
	unless ($readwrite) {
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
	my @disks = $p->findnodes ('//devices/disk/source/@dev');
	push (@disks, $p->findnodes ('//devices/disk/source/@file'));

	die __x("{imagename} seems to have no disk devices\n",
		imagename => $images[0])
	    unless @disks;

	@images = map { $_->getData } @disks;
    }

    # We've now got the list of @images, so feed them to libguestfs.
    my $g = Sys::Guestfs->new ();
    foreach (@images) {
	if ($readwrite) {
	    $g->add_drive ($_);
	} else {
	    $g->add_drive_ro ($_);
	}
    }

    return wantarray ? ($g, $conn, $dom, @images) : $g
}

=head2 get_partitions

 @partitions = get_partitions ($g);

This function takes an open libguestfs handle C<$g> and returns all
partitions and logical volumes found on it.

What is returned is everything that could contain a filesystem (or
swap).  Physical volumes are excluded from the list, and so are any
devices which are partitioned (eg. C</dev/sda> would not be returned
if C</dev/sda1> exists).

=cut

sub get_partitions
{
    my $g = shift;

    my @partitions = $g->list_partitions ();
    my @pvs = $g->pvs ();
    @partitions = grep { ! _is_pv ($_, @pvs) } @partitions;

    my @lvs = $g->lvs ();

    return sort (@lvs, @partitions);
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
    local $_;
    my $g = shift;
    my $path = shift;

    if (substr ($path, 0, 1) ne "/") {
	warn __"resolve_windows_path: path must start with a / character";
	return undef;
    }

    my @elems = split (/\//, $path);
    shift @elems;

    # Start reconstructing the path at the top.
    $path = "/";

    foreach my $dir (@elems) {
	my $found = 0;
	foreach ($g->ls ($path)) {
	    if (lc ($_) eq lc ($dir)) {
		if ($path eq "/") {
		    $path = "/$_";
		    $found = 1;
		} else {
		    $path = "$path/$_";
		    $found = 1;
		}
	    }
	}
	return undef unless $found;
    }

    return $path;
}

=head2 file_architecture

 $arch = file_architecture ($g, $path)

The C<file_architecture> function lets you get the architecture for a
particular binary or library in the guest.  By "architecture" we mean
what processor it is compiled for (eg. C<i586> or C<x86_64>).

The function works on at least the following types of files:

=over 4

=item *

many types of Un*x binary

=item *

many types of Un*x shared library

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

=back

=cut

sub _elf_arch_to_canonical
{
    local $_ = shift;

    if ($_ eq "Intel 80386") {
	return "i386";
    } elsif ($_ eq "Intel 80486") {
	return "i486";	# probably not in the wild
    } elsif ($_ eq "x86-64") {
	return "x86_64";
    } elsif ($_ eq "AMD x86-64") {
	return "x86_64";
    } elsif (/SPARC32/) {
	return "sparc";
    } elsif (/SPARC V9/) {
	return "sparc64";
    } elsif ($_ eq "IA-64") {
	return "ia64";
    } elsif (/64.*PowerPC/) {
	return "ppc64";
    } elsif (/PowerPC/) {
	return "ppc";
    } else {
	warn __x("returning non-canonical architecture type '{arch}'",
		 arch => $_);
	return $_;
    }
}

my @_initrd_binaries = ("nash", "modprobe", "sh", "bash");

sub file_architecture
{
    local $_;
    my $g = shift;
    my $path = shift;

    # Our basic tool is 'file' ...
    my $file = $g->file ($path);

    if ($file =~ /ELF.*(?:executable|shared object|relocatable), (.+?),/) {
	# ELF executable or shared object.  We need to convert
	# what file(1) prints into the canonical form.
	return _elf_arch_to_canonical ($1);
    } elsif ($file =~ /PE32 executable/) {
	return "i386";		# Win32 executable or DLL
    } elsif ($file =~ /PE32\+ executable/) {
	return "x86_64";	# Win64 executable or DLL
    }

    elsif ($file =~ /cpio archive/) {
	# Probably an initrd.
	my $zcat = "cat";
	if ($file =~ /gzip/) {
	    $zcat = "zcat";
	} elsif ($file =~ /bzip2/) {
	    $zcat = "bzcat";
	}

	# Download and unpack it to find a binary file.
	my $dir = tempdir (CLEANUP => 1);
	$g->download ($path, "$dir/initrd");

	my $bins = join " ", map { "bin/$_" } @_initrd_binaries;
	my $cmd = "cd $dir && $zcat initrd | cpio --quiet -id $bins";
	my $r = system ($cmd);
	die __x("cpio command failed: {error}", error => $?)
	    unless $r == 0;

	foreach my $bin (@_initrd_binaries) {
	    if (-f "$dir/bin/$bin") {
		$_ = `file $dir/bin/$bin`;
		if (/ELF.*executable, (.+?),/) {
		    return _elf_arch_to_canonical ($1);
		}
	    }
	}

	die __x("file_architecture: no known binaries found in initrd image: {path}",
		path => $path);
    }

    die __x("file_architecture: unknown architecture: {path}",
	    path => $path);
}

=head1 OPERATING SYSTEM INSPECTION FUNCTIONS

The functions in this section can be used to inspect the operating
system(s) available inside a virtual machine image.  For example, you
can find out if the VM is Linux or Windows, how the partitions are
meant to be mounted, and what applications are installed.

If you just want a simple command-line interface to this
functionality, use the L<virt-inspector(1)> tool.  The documentation
below covers the case where you want to access this functionality from
a Perl program.

Once you have the list of partitions (from C<get_partitions>) there
are several steps involved:

=over 4

=item 1.

Look at each partition separately and find out what is on it.

The information you get back includes whether the partition contains a
filesystem or swapspace, what sort of filesystem (eg. ext3, ntfs), and
a first pass guess at the content of the filesystem (eg. Linux boot,
Windows root).

The result of this step is a C<%fs> hash of information, one hash for
each partition.

See: C<inspect_partition>, C<inspect_all_partitions>

=item 2.

Work out the relationship between partitions.

In this step we work out how partitions are related to each other.  In
the case of a single-boot VM, we work out how the partitions are
mounted in respect of each other (eg. C</dev/sda1> is mounted as
C</boot>).  In the case of a multi-boot VM where there are several
roots, we may identify several operating system roots, and mountpoints
can even be shared.

The result of this step is a single hash called C<%oses> which is
described in more detail below, but at the top level looks like:

 %oses = {
   '/dev/VG/Root1' => \%os1,
   '/dev/VG/Root2' => \%os2,
 }
 
 %os1 = {
   os => 'linux',
   mounts => {
     '/' => '/dev/VG/Root1',
     '/boot' => '/dev/sda1',
   },
   ...
 }

(example shows a multi-boot VM containing two root partitions).

See: C<inspect_operating_systems>

=item 3.

Mount up the disks.

Previous to this point we've essentially been looking at each
partition in isolation.  Now we construct a true guest filesystem by
mounting up all of the disks.  Only once everything is mounted up can
we run commands in the OS context to do more detailed inspection.

See: C<mount_operating_system>

=item 4.

Check for kernels and applications.

This step now does more detailed inspection, where we can look for
kernels, applications and more installed in the guest.

The result of this is an enhanced C<%os> hash.

See: C<inspect_in_detail>

=item 5.

Generate output.

This library does not contain functions for generating output based on
the analysis steps above.  Use a command line tool such as
L<virt-inspector(1)> to get useful output.

=back

=head2 inspect_all_partitions

 %fses = inspect_all_partitions ($g, \@partitions);

 %fses = inspect_all_partitions ($g, \@partitions, use_windows_registry => 1);

This calls C<inspect_partition> for each partition in the list
C<@partitions>.

The result is a hash which maps partition name to C<\%fs> hashref.

The contents of the C<%fs> hash and the meaning of the
C<use_windows_registry> flag are explained below.

=cut

sub inspect_all_partitions
{
    local $_;
    my $g = shift;
    my $parts = shift;
    my @parts = @$parts;
    return map { $_ => inspect_partition ($g, $_, @_) } @parts;
}

=head2 inspect_partition

 \%fs = inspect_partition ($g, $partition);

 \%fs = inspect_partition ($g, $partition, use_windows_registry => 1);

This function inspects the device named C<$partition> in isolation and
tries to determine what it is.  It returns information such as whether
the partition is formatted, and with what, whether it is mountable,
and what it appears to contain (eg. a Windows root, or a Linux /usr).

If C<use_windows_registry> is set to 1, then we will try to download
and parse the content of the Windows registry (for Windows root
devices).  However since this is an expensive and error-prone
operation, we don't do this by default.  It also requires the external
program C<reged>, patched to remove numerous crashing bugs in the
upstream version.

The returned value is a hashref C<\%fs> which may contain the
following top-level keys (any key can be missing):

=over 4

=item fstype

Filesystem type, eg. "ext2" or "ntfs"

=item fsos

Apparent filesystem OS, eg. "linux" or "windows"

=item is_swap

If set, the partition is a swap partition.

=item uuid

Filesystem UUID.

=item label

Filesystem label.

=item is_mountable

If set, the partition could be mounted by libguestfs.

=item content

Filesystem content, if we could determine it.  One of: "linux-grub",
"linux-root", "linux-usrlocal", "linux-usr", "windows-root".

=item osdistro

(For Linux root partitions only).
Operating system distribution.  One of: "fedora", "rhel", "centos",
"scientific", "debian".

=item package_format

(For Linux root partitions only)
The package format used by the guest distribution. One of: "rpm", "dpkg".

=item package_management

(For Linux root partitions only)
The package management tool used by the guest distribution. One of: "rhn",
"yum", "apt".

=item os_major_version

(For root partitions only).
Operating system major version number.

=item os_minor_version

(For root partitions only).
Operating system minor version number.

=item fstab

(For Linux root partitions only).
The contents of the C</etc/fstab> file.

=item boot_ini

(For Windows root partitions only).
The contents of the C</boot.ini> (NTLDR) file.

=item registry

The value is an arrayref, which is a list of Windows registry
file contents, in Windows C<.REG> format.

=back

=cut

sub inspect_partition
{
    local $_;
    my $g = shift;
    my $dev = shift;		# LV or partition name.
    my %params = @_;

    my $use_windows_registry = $params{use_windows_registry};

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
	    _check_windows_root ($g, \%r, $use_windows_registry);
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
	    $r->{osdistro} = "fedora";
	    $r->{os_major_version} = "$1";
	    $r->{os_minor_version} = "$2" if(defined($2));
	    $r->{package_management} = "yum";
	}
        
        elsif (/(Red Hat Enterprise Linux|CentOS|Scientific Linux)/) {
            my $distro = $1;

            if($distro eq "Red Hat Enterprise Linux") {
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
        $r->{package_format} = "dpkg";
        $r->{package_management} = "apt";

	$_ = $g->cat ("/etc/debian_version");
	if (/(\d+)\.(\d+)/) {
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
# XXX We could parse this better.  This won't work if /boot.ini is on
# a different drive from the %systemroot%, and in other unusual cases.

sub _check_windows_root
{
    local $_;
    my $g = shift;
    my $r = shift;
    my $use_windows_registry = shift;

    my $boot_ini = resolve_windows_path ($g, "/boot.ini");
    $r->{boot_ini} = $boot_ini;

    if (defined $r->{boot_ini}) {
	$_ = $g->cat ($boot_ini);
	my @lines = split /\n/;
	my $section;
	my $systemroot;
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

	if (defined $systemroot) {
	    $r->{systemroot} = resolve_windows_path ($g, "/$systemroot");
	    if (defined $r->{systemroot}) {
		_check_windows_arch ($g, $r, $r->{systemroot});
		if ($use_windows_registry) {
		    _check_windows_registry ($g, $r, $r->{systemroot});
		}
	    }
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
    # interesting ones, and we don't bother with user profiles at all.

    my $configdir = resolve_windows_path ($g, "$systemroot/system32/config");
    if (defined $configdir) {
	my $softwaredir = resolve_windows_path ($g, "$configdir/software");
	if (defined $softwaredir) {
	    _load_windows_registry ($g, $r, $softwaredir,
				    "HKEY_LOCAL_MACHINE\\SOFTWARE");
	}
	my $systemdir = resolve_windows_path ($g, "$configdir/system");
	if (defined $systemdir) {
	    _load_windows_registry ($g, $r, $systemdir,
				    "HKEY_LOCAL_MACHINE\\System");
	}
    }
}

sub _load_windows_registry
{
    local $_;
    my $g = shift;
    my $r = shift;
    my $regfile = shift;
    my $prefix = shift;

    my $dir = tempdir (CLEANUP => 1);

    $g->download ($regfile, "$dir/reg");

    # 'reged' command is particularly noisy.  Redirect stdout and
    # stderr to /dev/null temporarily.
    open SAVEOUT, ">&STDOUT";
    open SAVEERR, ">&STDERR";
    open STDOUT, ">/dev/null";
    open STDERR, ">/dev/null";

    my @cmd = ("reged", "-x", "$dir/reg", "$prefix", "\\", "$dir/out");
    my $res = system (@cmd);

    close STDOUT;
    close STDERR;
    open STDOUT, ">&SAVEOUT";
    open STDERR, ">&SAVEERR";
    close SAVEOUT;
    close SAVEERR;

    unless ($res == 0) {
	warn __x("reged command failed: {errormsg}", errormsg => $?);
	return;
    }

    # Some versions of reged segfault on inputs.  If that happens we
    # may get no / partial output file.  Anyway, if it exists, load
    # it.
    my $content;
    unless (open F, "$dir/out") {
	warn __x("no output from reged command: {errormsg}", errormsg => $!);
	return;
    }
    { local $/ = undef; $content = <F>; }
    close F;

    my @registry = ();
    @registry = @{$r->{registry}} if exists $r->{registry};
    push @registry, $content;
    $r->{registry} = \@registry;
}

sub _check_grub
{
    local $_;
    my $g = shift;
    my $r = shift;

    # Grub version, if we care.
}

=head2 inspect_operating_systems

 \%oses = inspect_operating_systems ($g, \%fses);

This function works out how partitions are related to each other.  In
the case of a single-boot VM, we work out how the partitions are
mounted in respect of each other (eg. C</dev/sda1> is mounted as
C</boot>).  In the case of a multi-boot VM where there are several
roots, we may identify several operating system roots, and mountpoints
can even be shared.

This function returns a hashref C<\%oses> which at the top level looks
like:

 %oses = {
   '/dev/VG/Root' => \%os,
 }
 
(There can be multiple roots for a multi-boot VM).

The C<\%os> hash contains the following keys (any can be omitted):

=over 4

=item os

Operating system type, eg. "linux", "windows".

=item arch

Operating system userspace architecture, eg. "i386", "x86_64".

=item distro

Operating system distribution, eg. "debian".

=item major_version

Operating system major version, eg. "4".

=item minor_version

Operating system minor version, eg "3".

=item root

The value is a reference to the root partition C<%fs> hash.

=item root_device

The value is the name of the root partition (as a string).

=item mounts

Mountpoints.
The value is a hashref like this:

 mounts => {
   '/' => '/dev/VG/Root',
   '/boot' => '/dev/sda1',
 }

=item filesystems

Filesystems (including swap devices and unmounted partitions).
The value is a hashref like this:

 filesystems => {
   '/dev/sda1' => \%fs,
   '/dev/VG/Root' => \%fs,
   '/dev/VG/Swap' => \%fs,
 }

=back

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

    return \%oses;
}

sub _get_os_version
{
    local $_;
    my $g = shift;
    my $r = shift;

    $r->{os} = $r->{root}->{fsos} if exists $r->{root}->{fsos};
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

	    my ($dev, $fs) = _find_filesystem ($g, $fses, $spec);
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

    if (/^LABEL=(.*)/) {
	my $label = $1;
	foreach (sort keys %$fses) {
	    if (exists $fses->{$_}->{label} &&
		$fses->{$_}->{label} eq $label) {
		return ($_, $fses->{$_});
	    }
	}
	warn __x("unknown filesystem label {label}\n", label => $label);
	return ();
    } elsif (/^UUID=(.*)/) {
	my $uuid = $1;
	foreach (sort keys %$fses) {
	    if (exists $fses->{$_}->{uuid} &&
		$fses->{$_}->{uuid} eq $uuid) {
		return ($_, $fses->{$_});
	    }
	}
	warn __x("unknown filesystem UUID {uuid}\n", uuid => $uuid);
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
	if (m{^/dev/xvd(.*)} && exists $fses->{"/dev/sd$1"}) {
	    return ("/dev/sd$1", $fses->{"/dev/sd$1"});
	}
	if (m{^/dev/mapper/(.*)-(.*)$} && exists $fses->{"/dev/$1/$2"}) {
	    return ("/dev/$1/$2", $fses->{"/dev/$1/$2"});
	}

	return () if m{/dev/cdrom};

	warn __x("unknown filesystem {fs}\n", fs => $_);
	return ();
    }
}

=head2 mount_operating_system

 mount_operating_system ($g, \%os, [$ro]);

This function mounts the operating system described in the
C<%os> hash according to the C<mounts> table in that hash (see
C<inspect_operating_systems>).

The partitions are mounted read-only unless the third parameter
is specified as zero explicitly.

To reverse the effect of this call, use the standard
libguestfs API call C<$g-E<gt>umount_all ()>.

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
                $g->mount ($mounts->{$_}, $_)
            }
        }
    }
}

=head2 inspect_in_detail

 mount_operating_system ($g, \%os);
 inspect_in_detail ($g, \%os);
 $g->umount_all ();

The C<inspect_in_detail> function inspects the mounted operating
system for installed applications, installed kernels, kernel modules,
system architecture, and more.

It adds extra keys to the existing C<%os> hash reflecting what it
finds.  These extra keys are:

=over 4

=item apps

List of applications.

=item kernels

List of kernels.

This is a hash of kernel version =E<gt> a hash with the following keys:

=over 4

=item version

Kernel version.

=item arch

Kernel architecture (eg. C<x86-64>).

=item modules

List of modules.

=back

=item modprobe_aliases

(For Linux VMs).
The contents of the modprobe configuration.

=item initrd_modules

(For Linux VMs).
The kernel modules installed in the initrd.  The value is
a hashref of kernel version to list of modules.

=back

=cut

sub inspect_in_detail
{
    local $_;
    my $g = shift;
    my $os = shift;

    _check_for_applications ($g, $os);
    _check_for_kernels ($g, $os);
    if ($os->{os} eq "linux") {
	_check_for_modprobe_aliases ($g, $os);
	_check_for_initrd ($g, $os);
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
	    my @lines = $g->command_lines
		(["rpm",
		  "-q", "-a",
		  "--qf", "%{name} %{epoch} %{version} %{release} %{arch}\n"]);
	    foreach (@lines) {
		if (m/^(.*) (.*) (.*) (.*) (.*)$/) {
		    my $epoch = $2;
		    $epoch = "" if $epoch eq "(none)";
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

sub _check_for_kernels
{
    local $_;
    my $g = shift;
    my $os = shift;

    my @kernels;

    my $osn = $os->{os};
    if ($osn eq "linux") {
	# Installed kernels will have a corresponding /lib/modules/<version>
	# directory, which is the easiest way to find out what kernels
	# are installed, and what modules are available.
	foreach ($g->ls ("/lib/modules")) {
	    if ($g->is_dir ("/lib/modules/$_")) {
		my %kernel;
		$kernel{version} = $_;

		# List modules.
		my @modules;
		my $any_module;
		my $prefix = "/lib/modules/$_";
		foreach ($g->find ($prefix)) {
		    if (m,/([^/]+)\.ko$, || m,([^/]+)\.o$,) {
			$any_module = "$prefix$_" unless defined $any_module;
			push @modules, $1;
		    }
		}

		$kernel{modules} = \@modules;

		# Determine kernel architecture by looking at the arch
		# of any kernel module.
		$kernel{arch} = file_architecture ($g, $any_module);

		push @kernels, \%kernel;
	    }
	}

    } elsif ($osn eq "windows") {
	# XXX
    }

    $os->{kernels} = \@kernels;
}

# Check /etc/modprobe.conf to see if there are any specified
# drivers associated with network (ethX) or hard drives.  Normally
# one might find something like:
#
#  alias eth0 xennet
#  alias scsi_hostadapter xenblk
#
# XXX This doesn't look beyond /etc/modprobe.conf, eg. in /etc/modprobe.d/

sub _check_for_modprobe_aliases
{
    local $_;
    my $g = shift;
    my $os = shift;

    # Initialise augeas
    my $success = 0;
    $success = $g->aug_init("/", 16);

    # Register /etc/modules.conf and /etc/conf.modules to the Modprobe lens
    my @results;
    @results = $g->aug_match("/augeas/load/Modprobe/incl");

    # Calculate the next index of /augeas/load/Modprobe/incl
    my $i = 1;
    foreach ( @results ) {
        next unless m{/augeas/load/Modprobe/incl\[(\d*)]};
        $i = $1 + 1 if ($1 == $i);
    }

    $success = $g->aug_set("/augeas/load/Modprobe/incl[$i]",
                           "/etc/modules.conf");
    $i++;
    $success = $g->aug_set("/augeas/load/Modprobe/incl[$i]",
                                  "/etc/conf.modules");

    # Make augeas reload
    $success = $g->aug_load();

    my %modprobe_aliases;

    for my $pattern qw(/files/etc/conf.modules/alias
                       /files/etc/modules.conf/alias
                       /files/etc/modprobe.conf/alias
                       /files/etc/modprobe.d/*/alias) {
        @results = $g->aug_match($pattern);

        for my $path ( @results ) {
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

# Get a listing of device drivers in any initrd corresponding to a
# kernel.  This is an indication of what can possibly be booted.

sub _check_for_initrd
{
    local $_;
    my $g = shift;
    my $os = shift;

    my %initrd_modules;

    foreach my $initrd ($g->ls ("/boot")) {
	if ($initrd =~ m/^initrd-(.*)\.img$/ && $g->is_file ("/boot/$initrd")) {
	    my $version = $1;
	    my @modules;

	    # Disregard old-style compressed ext2 files and only
	    # work with real compressed cpio files, since cpio
	    # takes ages to (fail to) process anything else.
	    if ($g->file ("/boot/$initrd") =~ /cpio/) {
		eval {
		    @modules = $g->initrd_list ("/boot/$initrd");
		};
		unless ($@) {
		    @modules = grep { m,([^/]+)\.ko$, || m,([^/]+)\.o$, }
		    @modules;
		    $initrd_modules{$version} = \@modules
		} else {
		    warn __x("{filename}: could not read initrd format",
			     filename => "/boot/$initrd");
	        }
	    }
	}
    }

    $os->{initrd_modules} = \%initrd_modules;
}


1;

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

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
