#!/usr/bin/perl -w
# virt-v2v
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
use Sys::Guestfs::Lib qw(open_guest get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system inspect_in_detail);
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;
use File::Temp qw/tempdir/;
use XML::Writer;
use Locale::TextDomain 'libguestfs';

=encoding utf8

=head1 NAME

virt-v2v - Convert Xen or VMWare guests to KVM

=head1 SYNOPSIS

 virt-v2v xen_name -o kvm_name

 virt-v2v guest.ovf.zip -o kvm_name

 virt-v2v guest.img [guest.img ...]

=head1 DESCRIPTION

Virt-v2v converts guests from one virtualization hypervisor to
another.  Currently it is limited in what it can convert.  See the
table below.

 -------------------------------+----------------------------
 SOURCE                         | TARGET
 -------------------------------+----------------------------
 Xen domain managed by          |
 libvirt                        |
                                |
 Xen compatibility:             |
   - PV or FV kernel            |  KVM guest managed by
   - with or without PV drivers |  libvirt
   - RHEL 3.9+, 4.8+, 5.3+      |    - with virtio drivers
   - Windows XP, 2003           |
                                |
 -------------------------------+
                                |
 VMWare VMDK image with         |
 OVF metadata, exported from    |
 vSphere                        |
                                |
 VMWare compatibility:          |
   - RHEL 3.9+, 4.8+, 5.3+      |
   - VMWare tools               |
                                |
 -------------------------------+----------------------------

=head2 CONVERTING XEN DOMAINS

For Xen domains managed by libvirt, perform the initial conversion
using:

 virt-v2v xen_name -o kvm_name

where C<xen_name> is the libvirt Xen domain name, and C<kvm_name> is
the (new) name for the converted KVM guest.

Then test boot the new guest in KVM:

 virsh start kvm_name
 virt-viewer kvm_name

When you have verified that this works, shut down the new KVM domain
and I<commit> the changes by doing:

 virt-v2v --commit kvm_name

I<This command will destroy the original Xen domain>.

Or you can I<rollback> to the original Xen domain by doing:

 virt-v2v --rollback kvm_name

B<Very important note:> Do I<not> try to run both the original Xen
domain and the KVM domain at the same time!  This will cause guest
corruption.

=head2 CONVERTING VMWARE GUESTS

I<This section to be written>





=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $version;

=item B<--version>

Display version number and exit.

=cut

my $uri;

=item B<--connect URI> | B<-c URI>

If using libvirt, connect to the given I<URI>.  If omitted,
then we connect to the default libvirt hypervisor.

Libvirt is only used if you specify a C<domname> on the
command line.  If you specify guest block devices directly,
then libvirt is not used at all.

=cut

my $output;

=item B<--output name> | B<-o name>

Set the output guest name.

=cut

=back

=cut

GetOptions ("help|?" => \$help,
            "version" => \$version,
            "connect|c=s" => \$uri,
            "output|o=s" => \$output,
    ) or pod2usage (2);
pod2usage (1) if $help;
if ($version) {
    my $g = Sys::Guestfs->new ();
    my %h = $g->version ();
    print "$h{major}.$h{minor}.$h{release}$h{extra}\n";
    exit
}
pod2usage (__"virt-v2v: no image or VM names given") if @ARGV == 0;

# XXX This should be an option.  Disable for now until we get
# downloads working reliably.
my $use_windows_registry = 0;

my @params = (\@ARGV);
if ($uri) {
    push @params, address => $uri;
}
my ($g, $conn, $dom) = open_guest (@params);

$g->launch ();
$g->wait_ready ();

# List of possible filesystems.
my @partitions = get_partitions ($g);

# Now query each one to build up a picture of what's in it.
my %fses =
    inspect_all_partitions ($g, \@partitions,
                            use_windows_registry => $use_windows_registry);

#print "fses -----------\n";
#print Dumper(\%fses);

my $oses = inspect_operating_systems ($g, \%fses);

#print "oses -----------\n";
#print Dumper($oses);

# Only work on single-root operating systems.
my $root_dev;
my @roots = keys %$oses;
die __"no root device found in this operating system image" if @roots == 0;
die __"multiboot operating systems are not supported by v2v" if @roots > 1;
$root_dev = $roots[0];

# Mount up the disks and check for applications.

my $os = $oses->{$root_dev};
mount_operating_system ($g, $os);
inspect_in_detail ($g, $os);
$g->umount_all ();























=head1 SEE ALSO

L<virt-inspector(1)>,
L<guestfs(3)>,
L<guestfish(1)>,
L<Sys::Guestfs(3)>,
L<Sys::Guestfs::Lib(3)>,
L<Sys::Virt(3)>,
L<http://libguestfs.org/>.

For Windows registry parsing we require the C<reged> program
from L<http://home.eunet.no/~pnordahl/ntpasswd/>.

=head1 AUTHOR

Richard W.M. Jones L<http://et.redhat.com/~rjones/>

Matthew Booth L<mbooth@redhat.com>

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
