#!/usr/bin/perl -w
# virt-inspector
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use warnings;
use strict;

use Sys::Guestfs;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;

# Optional:
eval "use Sys::Virt;";

=encoding utf8

=head1 NAME

virt-inspector - Display OS version, kernel, drivers, mount points, applications, etc. in a virtual machine

=head1 SYNOPSIS

 virt-inspector [--connect URI] domname

 virt-inspector guest.img [guest.img ...]

=head1 DESCRIPTION

B<virt-inspector> examines a virtual machine and tries to determine
the version of the OS, the kernel version, what drivers are installed,
whether the virtual machine is fully virtualized (FV) or
para-virtualized (PV), what applications are installed and more.

Virt-inspector can produce output in several formats, including a
readable text report, and XML for feeding into other programs.

Virt-inspector should only be run on I<inactive> virtual machines.
The program tries to determine that the machine is inactive and will
refuse to run if it thinks you are trying to inspect a running domain.

In the normal usage, use C<virt-inspector domname> where C<domname> is
the libvirt domain (see: C<virsh list --all>).

You can also run virt-inspector directly on disk images from a single
virtual machine.  Use C<virt-inspector guest.img>.  In rare cases a
domain has several block devices, in which case you should list them
one after another, with the first corresponding to the guest's
C</dev/sda>, the second to the guest's C</dev/sdb> and so on.

Virt-inspector can only inspect and report upon I<one domain at a
time>.  To inspect several virtual machines, you have to run
virt-inspector several times (for example, from a shell script
for-loop).

Because virt-inspector needs direct access to guest images, it won't
normally work over remote libvirt connections.

=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $uri;

=item B<--connect URI> | B<-c URI>

If using libvirt, connect to the given I<URI>.  If omitted,
then we connect to the default libvirt hypervisor.

Libvirt is only used if you specify a C<domname> on the
command line.  If you specify guest block devices directly,
then libvirt is not used at all.

=cut

my $force;

=item B<--force>

Force reading a particular guest even if it appears to
be active, or if the guest image is writable.  This is
dangerous and can even corrupt the guest image.

=cut

my $output = "text";

=item B<--text> (default)

=item B<--xml>

=item B<--fish>

=item B<--ro-fish>

Select the output format.  The default is a readable text report.

If you select I<--xml> then you get XML output which can be fed
to other programs.

If you select I<--fish> then we print a L<guestfish(1)> command
line which will automatically mount up the filesystems on the
correct mount points.  Try this for example:

 eval `virt-inspector --fish guest.img`

I<--ro-fish> is the same, but the I<--ro> option is passed to
guestfish so that the filesystems are mounted read-only.

=back

=cut

GetOptions ("help|?" => \$help,
	    "connect|c=s" => \$uri,
	    "force" => \$force,
	    "xml" => sub { $output = "xml" },
	    "fish" => sub { $output = "fish" },
	    "guestfish" => sub { $output = "fish" },
	    "ro-fish" => sub { $output = "ro-fish" },
	    "ro-guestfish" => sub { $output = "ro-fish" })
    or pod2usage (2);
pod2usage (1) if $help;
pod2usage ("$0: no image or VM names given") if @ARGV == 0;

# Domain name or guest image(s)?

my @images;
if (-e $ARGV[0]) {
    @images = @ARGV;

    # Until we get an 'add_drive_ro' call, we must check that qemu
    # will only open this image in readonly mode.
    # XXX Remove this hack at some point ...  or at least push it
    # into libguestfs.

    foreach (@images) {
	if (! -r $_) {
	    die "guest image $_ does not exist or is not readable\n"
	} elsif (-w $_ && !$force) {
	    die ("guest image $_ is writable! REFUSING TO PROCEED.\n".
		 "You can use --force to override this BUT that action\n".
		 "MAY CORRUPT THE DISK IMAGE.\n");
        }
    }
} else {
    die "no libvirt support (install Sys::Virt)"
	unless exists $INC{"Sys/Virt.pm"};

    pod2usage ("$0: too many domains listed on command line") if @ARGV > 1;

    my $vmm;
    if (defined $uri) {
	$vmm = Sys::Virt->new (uri => $uri, readonly => 1);
    } else {
	$vmm = Sys::Virt->new (readonly => 1);
    }
    die "cannot connect to libvirt $uri\n" unless $vmm;

    my @doms = $vmm->list_defined_domains ();
    my $dom;
    foreach (@doms) {
	if ($_->get_name () eq $ARGV[0]) {
	    $dom = $_;
	    last;
	}
    }
    die "$ARGV[0] is not the name of an inactive libvirt domain\n"
	unless $dom;

    # Get the names of the image(s).
    my $xml = $dom->get_xml_description ();

    my $p = new XML::XPath::XMLParser (xml => $xml);
    my $disks = $p->find ("//devices/disk");
    print "disks:\n";
    foreach ($disks->get_nodelist) {
	print XML::XPath::XMLParser::as_string($_);
    }

    die "XXX"
}

# We've now got the list of @images, so feed them to libguestfs.
my $g = Sys::Guestfs->new ();
$g->add_drive ($_) foreach @images;
$g->launch ();
$g->wait_ready ();

# We want to get the list of LVs and partitions (ie. anything that
# could contain a filesystem).  Discard any partitions which are PVs.
my @partitions = $g->list_partitions ();
my @pvs = $g->pvs ();
sub is_pv {
    my $t = shift;
    foreach (@pvs) {
	return 1 if $_ eq $t;
    }
    0;
}
@partitions = grep { ! is_pv ($_) } @partitions;

my @lvs = $g->lvs ();

=head1 OUTPUT FORMAT

 Operating system(s)
 -------------------
 Linux (distro + version)
 Windows (version)
    |
    |
    +--- Filesystems ---------- Installed apps --- Kernel & drivers
         -----------            --------------     ----------------
         mount point => device  List of apps       Extra information
         mount point => device  and versions       about kernel(s)
              ...                                  and drivers
         swap => swap device
         (plus lots of extra information
         about each filesystem)

The output of virt-inspector is a complex two-level data structure.

At the top level is a list of the operating systems installed on the
guest.  (For the vast majority of guests, only a single OS is
installed.)  The data returned for the OS includes the name (Linux,
Windows), the distribution and version.

The diagram above shows what we return for each OS.

With the I<--xml> option the output is mapped into an XML document.
Unfortunately there is no clear schema for this document
(contributions welcome) but you can get an idea of the format by
looking at other documents and as a last resort the source for this
program.

With the I<--fish> or I<--ro-fish> option the mount points are mapped to
L<guestfish(1)> command line parameters, so that you can go in
afterwards and inspect the guest with everything mounted in the
right place.  For example:

 eval `virt-inspector --ro-fish guest.img`
 ==> guestfish --ro -a guest.img -m /dev/VG/LV:/ -m /dev/sda1:/boot

=cut

# List of possible filesystems.
my @devices = sort (@lvs, @partitions);

# Now query each one to build up a picture of what's in it.
my %fses = map { $_ => check_fs ($_) } @devices;

# Now the complex checking code itself.
# check_fs takes a device name (LV or partition name) and returns
# a hashref containing everything we can find out about the device.
sub check_fs {
    local $_;
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
	    check_grub (\%r);
	    goto OUT;
	}

	# Linux root?
	if ($g->is_dir ("/etc") && $g->is_dir ("/bin") &&
	    $g->is_file ("/etc/fstab")) {
	    $r{content} = "linux-root";
	    $r{is_root} = 1;
	    check_linux_root (\%r);
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
	    $g->is_file ("/ntldr")) {
	    $r{fstype} = "ntfs"; # XXX this is a guess
	    $r{fsos} = "windows";
	    $r{content} = "windows-root";
	    $r{is_root} = 1;
	    check_windows_root (\%r);
	    goto OUT;
	}
    }

  OUT:
    $g->umount_all ();
    return \%r;
}

sub check_linux_root
{
    local $_;
    my $r = shift;

    # Look into /etc to see if we recognise the operating system.
    if ($g->is_file ("/etc/redhat-release")) {
	$_ = $g->cat ("/etc/redhat-release");
	if (/Fedora release (\d+\.\d+)/) {
	    $r->{osdistro} = "fedora";
	    $r->{osversion} = "$1"
	} elsif (/(Red Hat Enterprise Linux|CentOS|Scientific Linux).*release (\d+).*Update (\d+)/) {
	    $r->{osdistro} = "redhat";
	    $r->{osversion} = "$2.$3";
        } elsif (/(Red Hat Enterprise Linux|CentOS|Scientific Linux).*release (\d+(?:\.(\d+))?)/) {
	    $r->{osdistro} = "redhat";
	    $r->{osversion} = "$2";
	} else {
	    $r->{osdistro} = "redhat";
	}
    } elsif ($g->is_file ("/etc/debian_version")) {
	$_ = $g->cat ("/etc/debian_version");
	if (/(\d+\.\d+)/) {
	    $r->{osdistro} = "debian";
	    $r->{osversion} = "$1";
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
}

sub check_windows_root
{
    local $_;
    my $r = shift;

    # XXX Windows version.
    # List of applications.
}

sub check_grub
{
    local $_;
    my $r = shift;

    # XXX Kernel versions, grub version.
}

#print Dumper (\%fses);

#----------------------------------------------------------------------
# Now find out how many operating systems we've got.  Usually just one.

my %oses = ();

foreach (sort keys %fses) {
    if ($fses{$_}->{is_root}) {
	my %r = (
	    root => $fses{$_},
	    root_device => $_
	);
	get_os_version (\%r);
	assign_mount_points (\%r);
	$oses{$_} = \%r;
    }
}

sub get_os_version
{
    local $_;
    my $r = shift;

    $r->{os} = $r->{root}->{fsos} if exists $r->{root}->{fsos};
    $r->{distro} = $r->{root}->{osdistro} if exists $r->{root}->{osdistro};
    $r->{version} = $r->{root}->{osversion} if exists $r->{root}->{osversion};
}

sub assign_mount_points
{
    local $_;
    my $r = shift;

    $r->{mounts} = { "/" => $r->{root_device} };
    $r->{filesystems} = { $r->{root_device} => $r->{root} };

    # Use /etc/fstab if we have it to mount the rest.
    if (exists $r->{root}->{fstab}) {
	my @fstab = @{$r->{root}->{fstab}};
	foreach (@fstab) {
	    my ($spec, $file) = @$_;

	    my ($dev, $fs) = find_filesystem ($spec);
	    if ($dev) {
		$r->{mounts}->{$file} = $dev;
		$r->{filesystems}->{$dev} = $fs;
		if (exists $fs->{used}) {
		    $fs->{used}++
		} else {
		    $fs->{used} = 1
	        }
	    }
	}
    }
}

# Find filesystem by device name, LABEL=.. or UUID=..
sub find_filesystem
{
    local $_ = shift;

    if (/^LABEL=(.*)/) {
	my $label = $1;
	foreach (sort keys %fses) {
	    if (exists $fses{$_}->{label} &&
		$fses{$_}->{label} eq $label) {
		return ($_, $fses{$_});
	    }
	}
	warn "unknown filesystem label $label\n";
	return ();
    } elsif (/^UUID=(.*)/) {
	my $uuid = $1;
	foreach (sort keys %fses) {
	    if (exists $fses{$_}->{uuid} &&
		$fses{$_}->{uuid} eq $uuid) {
		return ($_, $fses{$_});
	    }
	}
	warn "unknown filesystem UUID $uuid\n";
	return ();
    } else {
	return ($_, $fses{$_}) if exists $fses{$_};

	if (m{^/dev/hd(.*)} && exists $fses{"/dev/sd$1"}) {
	    return ("/dev/sd$1", $fses{"/dev/sd$1"});
	}
	if (m{^/dev/xvd(.*)} && exists $fses{"/dev/sd$1"}) {
	    return ("/dev/sd$1", $fses{"/dev/sd$1"});
	}

	return () if m{/dev/cdrom};

	warn "unknown filesystem $_\n";
	return ();
    }
}

#print Dumper(\%oses);

#----------------------------------------------------------------------
# Mount up the disks so we can check for applications
# and kernels.  Skip this if the output is "*fish" because
# we don't need to know.

if ($output !~ /.*fish$/) {
    my $root_dev;
    foreach $root_dev (sort keys %oses) {
	my $mounts = $oses{$root_dev}->{mounts};
	# Have to mount / first.  Luckily '/' is early in the ASCII
	# character set, so this should be OK.
	foreach (sort keys %$mounts) {
	    $g->mount_ro ($mounts->{$_}, $_)
		if $_ ne "swap" && ($_ eq '/' || $g->is_dir ($_));
	}

	check_for_applications ($root_dev);
	check_for_kernels ($root_dev);

	umount_all ();
    }
}

sub check_for_applications
{
    local $_;
    my $root_dev = shift;

    # XXX rpm -qa, look in Program Files, or whatever
}

sub check_for_kernels
{
    local $_;
    my $root_dev = shift;

    # XXX
}

#----------------------------------------------------------------------
# Output.

if ($output eq "fish" || $output eq "ro-fish") {
    my @osdevs = keys %oses;
    # This only works if there is a single OS.
    die "--fish output is only possible with a single OS\n" if @osdevs != 1;

    my $root_dev = $osdevs[0];

    print "guestfish";
    if ($output eq "ro-fish") {
	print " --ro";
    }

    print " -a $_" foreach @images;

    my $mounts = $oses{$root_dev}->{mounts};
    # Have to mount / first.  Luckily '/' is early in the ASCII
    # character set, so this should be OK.
    foreach (sort keys %$mounts) {
	print " -m $mounts->{$_}:$_" if $_ ne "swap";
    }
    print "\n"
}



=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<Sys::Guestfs(3)>,
L<Sys::Virt(3)>

=head1 AUTHOR

Richard W.M. Jones L<http://et.redhat.com/~rjones/>

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
