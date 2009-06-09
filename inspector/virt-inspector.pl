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
use File::Temp qw/tempdir/;

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

Force reading a particular guest even if it appears to be active.  In
earlier versions of virt-inspector, this could be dangerous (for
example, corrupting the guest's disk image).  However in more recent
versions, it should not cause corruption, but might cause
virt-inspector to crash or produce incorrect results.

=cut

my $output = "text";

=back

The following options select the output format.  Use only one of them.
The default is a readable text report.

=over 4

=item B<--text> (default)

Plain text report.

=item B<--none>

Produce no output at all.

=item B<--xml>

If you select I<--xml> then you get XML output which can be fed
to other programs.

=item B<--perl>

If you select I<--perl> then you get Perl structures output which
can be used directly in another Perl program.

=item B<--fish>

=item B<--ro-fish>

If you select I<--fish> then we print a L<guestfish(1)> command
line which will automatically mount up the filesystems on the
correct mount points.  Try this for example:

 eval `virt-inspector --fish guest.img`

I<--ro-fish> is the same, but the I<--ro> option is passed to
guestfish so that the filesystems are mounted read-only.

=item B<--query>

In "query mode" we answer common questions about the guest, such
as whether it is fullvirt or needs a Xen hypervisor to run.

See section I<QUERY MODE> below.

=cut

my $windows_registry;

=item B<--windows-registry>

If this item is passed, I<and> the guest is Windows, I<and> the
external program C<reged> is available (see SEE ALSO section), then we
attempt to parse the Windows registry.  This allows much more
information to be gathered for Windows guests.

This is quite an expensive and slow operation, so we don't do it by
default.

=back

=cut

GetOptions ("help|?" => \$help,
	    "connect|c=s" => \$uri,
	    "force" => \$force,
	    "text" => sub { $output = "text" },
	    "none" => sub { $output = "none" },
	    "xml" => sub { $output = "xml" },
	    "perl" => sub { $output = "perl" },
	    "fish" => sub { $output = "fish" },
	    "guestfish" => sub { $output = "fish" },
	    "ro-fish" => sub { $output = "ro-fish" },
	    "ro-guestfish" => sub { $output = "ro-fish" },
	    "query" => sub { $output = "query" },
	    "windows-registry" => \$windows_registry,
    ) or pod2usage (2);
pod2usage (1) if $help;
pod2usage ("$0: no image or VM names given") if @ARGV == 0;

# Domain name or guest image(s)?

my @images;
if (-e $ARGV[0]) {
    @images = @ARGV;

    foreach (@images) {
	if (! -r $_) {
	    die "guest image $_ does not exist or is not readable\n"
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
$g->add_drive_ro ($_) foreach @images;
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
	    $g->is_file ("/boot.ini") ||
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

# We only support NT.  The control file /boot.ini contains a list of
# Windows installations and their %systemroot%s in a simple text
# format.
#
# XXX We could parse this better.  This won't work if /boot.ini is on
# a different drive from the %systemroot%, and in other unusual cases.

sub check_windows_root
{
    local $_;
    my $r = shift;

    my $boot_ini = resolve_windows_path ("/", "boot.ini");
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
	    $r->{systemroot} = resolve_windows_path ("/", $systemroot);
	    if (defined $r->{systemroot} && $windows_registry) {
		check_windows_registry ($r, $r->{systemroot});
	    }
	}
    }
}

sub check_windows_registry
{
    local $_;
    my $r = shift;
    my $systemroot = shift;

    # Download the system registry files.  Only download the
    # interesting ones, and we don't bother with user profiles at all.
    my $system32 = resolve_windows_path ($systemroot, "system32");
    if (defined $system32) {
	my $config = resolve_windows_path ($system32, "config");
	if (defined $config) {
	    my $software = resolve_windows_path ($config, "software");
	    if (defined $software) {
		load_windows_registry ($r, $software,
				       "HKEY_LOCAL_MACHINE\\SOFTWARE");
	    }
	    my $system = resolve_windows_path ($config, "system");
	    if (defined $system) {
		load_windows_registry ($r, $system,
				       "HKEY_LOCAL_MACHINE\\System");
	    }
	}
    }
}

sub load_windows_registry
{
    local $_;
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
	warn "reged command failed: $?";
	return;
    }

    # Some versions of reged segfault on inputs.  If that happens we
    # may get no / partial output file.  Anyway, if it exists, load
    # it.
    my $content;
    unless (open F, "$dir/out") {
	warn "no output from reged command: $!";
	return;
    }
    { local $/ = undef; $content = <F>; }
    close F;

    my @registry = ();
    @registry = @{$r->{registry}} if exists $r->{registry};
    push @registry, $content;
    $r->{registry} = \@registry;
}

# Because of case sensitivity, the actual path might have a different
# name, and ntfs-3g is always case sensitive.  Find out what the real
# path is.  Returns the correct full path, or undef.
sub resolve_windows_path
{
    local $_;
    my $parent = shift;		# Must exist, with correct case.
    my $dir = shift;

    foreach ($g->ls ($parent)) {
	if (lc ($_) eq lc ($dir)) {
	    if ($parent eq "/") {
		return "/$_"
	    } else {
		return "$parent/$_"
	    }
	}
    }

    undef;
}

sub check_grub
{
    local $_;
    my $r = shift;

    # Grub version, if we care.
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
    # Temporary directory for use by check_for_initrd.
    my $dir = tempdir (CLEANUP => 1);

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
	if ($oses{$root_dev}->{os} eq "linux") {
	    check_for_modprobe_aliases ($root_dev);
	    check_for_initrd ($root_dev, $dir);
	}

	$g->umount_all ();
    }
}

sub check_for_applications
{
    local $_;
    my $root_dev = shift;

    my @apps;

    my $os = $oses{$root_dev}->{os};
    if ($os eq "linux") {
	my $distro = $oses{$root_dev}->{distro};
	if (defined $distro && ($distro eq "redhat" || $distro eq "fedora")) {
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
    } elsif ($os eq "windows") {
	# XXX
	# I worked out a general plan for this, but haven't
	# implemented it yet.  We can iterate over /Program Files
	# looking for *.EXE files, which we download, then use
	# i686-pc-mingw32-windres on, to find the VERSIONINFO
	# section, which has a lot of useful information.
    }

    $oses{$root_dev}->{apps} = \@apps;
}

sub check_for_kernels
{
    local $_;
    my $root_dev = shift;

    my @kernels;

    my $os = $oses{$root_dev}->{os};
    if ($os eq "linux") {
	# Installed kernels will have a corresponding /lib/modules/<version>
	# directory, which is the easiest way to find out what kernels
	# are installed, and what modules are available.
	foreach ($g->ls ("/lib/modules")) {
	    if ($g->is_dir ("/lib/modules/$_")) {
		my %kernel;
		$kernel{version} = $_;

		# List modules.
		my @modules;
		foreach ($g->find ("/lib/modules/$_")) {
		    if (m,/([^/]+)\.ko$, || m,([^/]+)\.o$,) {
			push @modules, $1;
		    }
		}

		$kernel{modules} = \@modules;

		push @kernels, \%kernel;
	    }
	}

    } elsif ($os eq "windows") {
	# XXX
    }

    $oses{$root_dev}->{kernels} = \@kernels;
}

# Check /etc/modprobe.conf to see if there are any specified
# drivers associated with network (ethX) or hard drives.  Normally
# one might find something like:
#
#  alias eth0 xennet
#  alias scsi_hostadapter xenblk
#
# XXX This doesn't look beyond /etc/modprobe.conf, eg. in /etc/modprobe.d/

sub check_for_modprobe_aliases
{
    local $_;
    my $root_dev = shift;

    my @lines;
    eval { @lines = $g->read_lines ("/etc/modprobe.conf"); };
    return if $@ || !@lines;

    my %modprobe_aliases;

    foreach (@lines) {
	$modprobe_aliases{$1} = $2 if /^\s*alias\s+(\S+)\s+(\S+)/;
    }

    $oses{$root_dev}->{modprobe_aliases} = \%modprobe_aliases;
}

# Get a listing of device drivers in any initrd corresponding to a
# kernel.  This is an indication of what can possibly be booted.

sub check_for_initrd
{
    local $_;
    my $root_dev = shift;
    my $dir = shift;

    my %initrd_modules;

    foreach my $initrd ($g->ls ("/boot")) {
	if ($initrd =~ m/^initrd-(.*)\.img$/ && $g->is_file ("/boot/$initrd")) {
	    my $version = $1;
	    my @modules = ();
	    # We have to download these to a temporary file.
	    $g->download ("/boot/$initrd", "$dir/initrd");

	    my $cmd = "zcat $dir/initrd | file -";
	    open P, "$cmd |" or die "$cmd: $!";
	    my $lines;
	    { local $/ = undef; $lines = <P>; }
	    close P;
	    if ($lines =~ /ext\d filesystem data/) {
		# Before initramfs came along, these were compressed
		# ext2 filesystems.  We could run another libguestfs
		# instance to unpack these, but punt on them for now. (XXX)
		warn "initrd image is unsupported ext2/3/4 filesystem\n";
	    }
	    elsif ($lines =~ /cpio/) {
		my $cmd = "zcat $dir/initrd | cpio --quiet -it";
		open P, "$cmd |" or die "$cmd: $!";
		while (<P>) {
		    push @modules, $1
			if m,([^/]+)\.ko$, || m,([^/]+)\.o$,;
		}
		close P;
		unlink "$dir/initrd";
		$initrd_modules{$version} = \@modules;
	    }
	    else {
		# What?
		warn "unrecognized initrd image: $lines\n";
	    }
	}
    }

    $oses{$root_dev}->{initrd_modules} = \%initrd_modules;
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

# Perl output.
elsif ($output eq "perl") {
    print Dumper(\%oses);
}

# Plain text output (the default).
elsif ($output eq "text") {
    output_text ();
}

# XML output.
elsif ($output eq "xml") {
    output_xml ();
}

# Query mode.
elsif ($output eq "query") {
    output_query ();
}

sub output_text
{
    output_text_os ($oses{$_}) foreach sort keys %oses;
}

sub output_text_os
{
    my $os = shift;

    print $os->{os}, " " if exists $os->{os};
    print $os->{distro}, " " if exists $os->{distro};
    print $os->{version}, " " if exists $os->{version};
    print "on ", $os->{root_device}, ":\n";

    print "  Mountpoints:\n";
    my $mounts = $os->{mounts};
    foreach (sort keys %$mounts) {
	printf "    %-30s %s\n", $mounts->{$_}, $_
    }

    print "  Filesystems:\n";
    my $filesystems = $os->{filesystems};
    foreach (sort keys %$filesystems) {
	print "    $_:\n";
	print "      label: $filesystems->{$_}{label}\n"
	    if exists $filesystems->{$_}{label};
	print "      UUID: $filesystems->{$_}{uuid}\n"
	    if exists $filesystems->{$_}{uuid};
	print "      type: $filesystems->{$_}{fstype}\n"
	    if exists $filesystems->{$_}{fstype};
	print "      content: $filesystems->{$_}{content}\n"
	    if exists $filesystems->{$_}{content};
    }

    if (exists $os->{modprobe_aliases}) {
	my %aliases = %{$os->{modprobe_aliases}};
	my @keys = sort keys %aliases;
	if (@keys) {
	    print "  Modprobe aliases:\n";
	    foreach (@keys) {
		printf "    %-30s %s\n", $_, $aliases{$_}
	    }
	}
    }

    if (exists $os->{initrd_modules}) {
	my %modvers = %{$os->{initrd_modules}};
	my @keys = sort keys %modvers;
	if (@keys) {
	    print "  Initrd modules:\n";
	    foreach (@keys) {
		my @modules = @{$modvers{$_}};
		print "    $_:\n";
		print "      $_\n" foreach @modules;
	    }
	}
    }

    print "  Applications:\n";
    my @apps =  @{$os->{apps}};
    foreach (@apps) {
	print "    $_->{name} $_->{version}\n"
    }

    print "  Kernels:\n";
    my @kernels = @{$os->{kernels}};
    foreach (@kernels) {
	print "    $_->{version}\n";
	my @modules = @{$_->{modules}};
	foreach (@modules) {
	    print "      $_\n";
	}
    }

    if (exists $os->{root}->{registry}) {
	print "  Windows Registry entries:\n";
	# These are just lumps of text - dump them out.
	foreach (@{$os->{root}->{registry}}) {
	    print "$_\n";
	}
    }
}

sub output_xml
{
    print "<operatingsystems>\n";
    output_xml_os ($oses{$_}) foreach sort keys %oses;
    print "</operatingsystems>\n";
}

sub output_xml_os
{
    my $os = shift;

    print "<operatingsystem>\n";

    print "<os>", $os->{os}, "</os>\n" if exists $os->{os};
    print "<distro>", $os->{distro}, "</distro>\n" if exists $os->{distro};
    print "<version>", $os->{version}, "</version>\n" if exists $os->{version};
    print "<root>", $os->{root_device}, "</root>\n";

    print "<mountpoints>\n";
    my $mounts = $os->{mounts};
    foreach (sort keys %$mounts) {
	printf "<mountpoint dev='%s'>%s</mountpoint>\n",
	  $mounts->{$_}, $_
    }
    print "</mountpoints>\n";

    print "<filesystems>\n";
    my $filesystems = $os->{filesystems};
    foreach (sort keys %$filesystems) {
	print "<filesystem dev='$_'>\n";
	print "<label>$filesystems->{$_}{label}</label>\n"
	    if exists $filesystems->{$_}{label};
	print "<uuid>$filesystems->{$_}{uuid}</uuid>\n"
	    if exists $filesystems->{$_}{uuid};
	print "<type>$filesystems->{$_}{fstype}</type>\n"
	    if exists $filesystems->{$_}{fstype};
	print "<content>$filesystems->{$_}{content}</content>\n"
	    if exists $filesystems->{$_}{content};
	print "</filesystem>\n";
    }
    print "</filesystems>\n";

    if (exists $os->{modprobe_aliases}) {
	my %aliases = %{$os->{modprobe_aliases}};
	my @keys = sort keys %aliases;
	if (@keys) {
	    print "<modprobealiases>\n";
	    foreach (@keys) {
		printf "<alias device=\"%s\">%s</alias>\n", $_, $aliases{$_}
	    }
	    print "</modprobealiases>\n";
	}
    }

    if (exists $os->{initrd_modules}) {
	my %modvers = %{$os->{initrd_modules}};
	my @keys = sort keys %modvers;
	if (@keys) {
	    print "<initrds>\n";
	    foreach (@keys) {
		my @modules = @{$modvers{$_}};
		print "<initrd version=\"$_\">\n";
		print "<module>$_</module>\n" foreach @modules;
		print "</initrd>\n";
	    }
	    print "</initrds>\n";
	}
    }

    print "<applications>\n";
    my @apps =  @{$os->{apps}};
    foreach (@apps) {
	print "<application>\n";
	print "<name>$_->{name}</name><version>$_->{version}</version>\n";
	print "</application>\n";
    }
    print "</applications>\n";

    print "<kernels>\n";
    my @kernels = @{$os->{kernels}};
    foreach (@kernels) {
	print "<kernel>\n";
	print "<version>$_->{version}</version>\n";
	print "<modules>\n";
	my @modules = @{$_->{modules}};
	foreach (@modules) {
	    print "<module>$_</module>\n";
	}
	print "</modules>\n";
	print "</kernel>\n";
    }
    print "</kernels>\n";

    if (exists $os->{root}->{registry}) {
	print "<windowsregistryentries>\n";
	# These are just lumps of text - dump them out.
	foreach (@{$os->{root}->{registry}}) {
	    print "<windowsregistryentry>\n";
	    print escape_xml($_), "\n";
	    print "</windowsregistryentry>\n";
	}
	print "</windowsregistryentries>\n";
    }

    print "</operatingsystem>\n";
}

sub escape_xml
{
    local $_ = shift;

    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    return $_;
}

=head1 QUERY MODE

When you use C<virt-inspector --query>, the output is a series of
lines of the form:

 windows=no
 linux=yes
 fullvirt=yes
 xen_pv_drivers=no

(each answer is usually C<yes> or C<no>, or the line is completely
missing if we could not determine the answer at all).

If the guest is multiboot, you can get apparently conflicting answers
(eg. C<windows=yes> and C<linux=yes>, or a guest which is both
fullvirt and has a Xen PV kernel).  This is normal, and just means
that the guest can do both things, although it might require operator
intervention such as selecting a boot option when the guest is
booting.

This section describes the full range of answers possible.

=over 4

=cut

sub output_query
{
    output_query_windows ();
    output_query_linux ();
    output_query_rhel ();
    output_query_fedora ();
    output_query_debian ();
    output_query_fullvirt ();
    output_query_xen_domU_kernel ();
    output_query_xen_pv_drivers ();
    output_query_virtio_drivers ();
}

=item windows=(yes|no)

Answer C<yes> if Microsoft Windows is installed in the guest.

=cut

sub output_query_windows
{
    my $windows = "no";
    foreach my $os (keys %oses) {
	$windows="yes" if $oses{$os}->{os} eq "windows";
    }
    print "windows=$windows\n";
}

=item linux=(yes|no)

Answer C<yes> if a Linux kernel is installed in the guest.

=cut

sub output_query_linux
{
    my $linux = "no";
    foreach my $os (keys %oses) {
	$linux="yes" if $oses{$os}->{os} eq "linux";
    }
    print "linux=$linux\n";
}

=item rhel=(yes|no)

Answer C<yes> if the guest contains Red Hat Enterprise Linux.

=cut

sub output_query_rhel
{
    my $rhel = "no";
    foreach my $os (keys %oses) {
	$rhel="yes" if $oses{$os}->{os} eq "linux" && $oses{$os}->{distro} eq "redhat";
    }
    print "rhel=$rhel\n";
}

=item fedora=(yes|no)

Answer C<yes> if the guest contains the Fedora Linux distribution.

=cut

sub output_query_fedora
{
    my $fedora = "no";
    foreach my $os (keys %oses) {
	$fedora="yes" if $oses{$os}->{os} eq "linux" && $oses{$os}->{distro} eq "fedora";
    }
    print "fedora=$fedora\n";
}

=item debian=(yes|no)

Answer C<yes> if the guest contains the Debian Linux distribution.

=cut

sub output_query_debian
{
    my $debian = "no";
    foreach my $os (keys %oses) {
	$debian="yes" if $oses{$os}->{os} eq "linux" && $oses{$os}->{distro} eq "debian";
    }
    print "debian=$debian\n";
}

=item fullvirt=(yes|no)

Answer C<yes> if there is at least one operating system kernel
installed in the guest which runs fully virtualized.  Such a guest
would require a hypervisor which supports full system virtualization.

=cut

sub output_query_fullvirt
{
    # The assumption is full-virt, unless all installed kernels
    # are identified as paravirt.
    # XXX Fails on Windows guests.
    foreach my $os (keys %oses) {
	foreach my $kernel (@{$oses{$os}->{kernels}}) {
	    my $is_pv = $kernel->{version} =~ m/xen/;
	    unless ($is_pv) {
		print "fullvirt=yes\n";
		return;
	    }
	}
    }
    print "fullvirt=no\n";
}

=item xen_domU_kernel=(yes|no)

Answer C<yes> if there is at least one Linux kernel installed in
the guest which is compiled as a Xen DomU (a Xen paravirtualized
guest).

=cut

sub output_query_xen_domU_kernel
{
    foreach my $os (keys %oses) {
	foreach my $kernel (@{$oses{$os}->{kernels}}) {
	    my $is_xen = $kernel->{version} =~ m/xen/;
	    if ($is_xen) {
		print "xen_domU_kernel=yes\n";
		return;
	    }
	}
    }
    print "xen_domU_kernel=no\n";
}

=item xen_pv_drivers=(yes|no)

Answer C<yes> if the guest has Xen paravirtualized drivers installed
(usually the kernel itself will be fully virtualized, but the PV
drivers have been installed by the administrator for performance
reasons).

=cut

sub output_query_xen_pv_drivers
{
    foreach my $os (keys %oses) {
	foreach my $kernel (@{$oses{$os}->{kernels}}) {
	    foreach my $module (@{$kernel->{modules}}) {
		if ($module =~ m/xen-/) {
		    print "xen_pv_drivers=yes\n";
		    return;
		}
	    }
	}
    }
    print "xen_pv_drivers=no\n";
}

=item virtio_drivers=(yes|no)

Answer C<yes> if the guest has virtio paravirtualized drivers
installed.  Virtio drivers are commonly used to improve the
performance of KVM.

=cut

sub output_query_virtio_drivers
{
    foreach my $os (keys %oses) {
	foreach my $kernel (@{$oses{$os}->{kernels}}) {
	    foreach my $module (@{$kernel->{modules}}) {
		if ($module =~ m/virtio_/) {
		    print "virtio_drivers=yes\n";
		    return;
		}
	    }
	}
    }
    print "virtio_drivers=no\n";
}

=back

=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<Sys::Guestfs(3)>,
L<Sys::Virt(3)>.

For Windows registry parsing we require the C<reged> program
from L<http://home.eunet.no/~pnordahl/ntpasswd/>.

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
