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

=encoding utf8

=head1 NAME

virt-v2v - Convert Xen guests to KVM

=head1 SYNOPSIS

 virt-v2v xen_name -o kvm_name

 virt-v2v guest.img [guest.img ...]

=head1 DESCRIPTION






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

GetOptions ("help|?" => \$help,
	    "connect|c=s" => \$uri,
    ) or pod2usage (2);
pod2usage (1) if $help;
pod2usage ("$0: no image or VM names given") if @ARGV == 0;

# my $g;
# if ($uri) {
#     $g = open_guest (\@ARGV, rw => $rw, address => $uri);
# } else {
#     $g = open_guest (\@ARGV, rw => $rw);
# }

# $g->launch ();
# $g->wait_ready ();

# # List of possible filesystems.
# my @partitions = get_partitions ($g);

# # Now query each one to build up a picture of what's in it.
# my %fses =
#     inspect_all_partitions ($g, \@partitions,
#       use_windows_registry => $windows_registry);

# #print "fses -----------\n";
# #print Dumper(\%fses);

# my $oses = inspect_operating_systems ($g, \%fses);

# #print "oses -----------\n";
# #print Dumper($oses);

# # Mount up the disks and check for applications.

# my $root_dev;
# foreach $root_dev (sort keys %$oses) {
#     my $os = $oses->{$root_dev};
#     mount_operating_system ($g, $os);
#     inspect_in_detail ($g, $os);
#     $g->umount_all ();
# }

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
