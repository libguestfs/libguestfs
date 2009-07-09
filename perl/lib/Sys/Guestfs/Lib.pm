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

# Optional:
eval "use Sys::Virt;";
eval "use XML::XPath;";
eval "use XML::XPath::XMLParser;";

=pod

=head1 NAME

Sys::Guestfs::Lib - Useful functions for using libguestfs from Perl

=head1 SYNOPSIS

 use Sys::Guestfs::Lib qw(#any symbols you want to use);

 $g = open_guest ($name);

=head1 DESCRIPTION

C<Sys::Guestfs::Lib> is an extra library of useful functions for using
the libguestfs API from Perl.  It also provides tighter integration
with libvirt.

The basic libguestfs API is not covered by this manpage.  Please refer
instead to L<Sys::Guestfs(3)> and L<guestfs(3)>.  The libvirt API is
also not covered.  For that, see L<Sys::Virt(3)>.

=head1 FUNCTIONS

=cut

require Exporter;

use vars qw(@EXPORT_OK @ISA);

@ISA = qw(Exporter);
@EXPORT_OK = qw(open_guest);

=head2 open_guest

 $g = open_guest ($name);

 $g = open_guest ($name, rw => 1, ...);

 $g = open_guest ($name, address => $uri, ...);

 $g = open_guest ([$img1, $img2, ...], address => $uri, ...);

 ($g, $conn, $dom) = open_guest ($name);

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
libvirt handle, and the open libvirt domain handle.  (This is useful
if you want to do other things like pulling the XML description of the
guest).  Note that if this is a straight disk image, then C<$conn> and
C<$dom> will be C<undef>.

If the C<Sys::Virt> module is not available, then libvirt is bypassed,
and this function can only open disk images.

=cut

sub open_guest
{
    my $first = shift;
    my %params = @_;

    my $readwrite = $params{rw};

    my @images = ();
    if (ref ($first) eq "ARRAY") {
	@images = @$first;
    } elsif (ref ($first) eq "SCALAR") {
	@images = ($first);
    } else {
	die "open_guest: first parameter must be a string or an arrayref"
    }

    my ($conn, $dom);

    if (-e $images[0]) {
	foreach (@images) {
	    die "guest image $_ does not exist or is not readable"
		unless -r $_;
	}
    } else {
	die "open_guest: no libvirt support (install Sys::Virt, XML::XPath and XML::XPath::XMLParser)"
	    unless exists $INC{"Sys/Virt.pm"} &&
	    exists $INC{"XML/XPath.pm"} &&
	    exists $INC{"XML/XPath/XMLParser.pm"};

	die "open_guest: too many domains listed on command line"
	    if @images > 1;

	$conn = Sys::Virt->new (readonly => 1, @_);
	die "open_guest: cannot connect to libvirt" unless $conn;

	my @doms = $conn->list_defined_domains ();
	my $isitinactive = "an inactive libvirt domain";
	unless ($readwrite) {
	    # In the case where we want read-only access to a domain,
	    # allow the user to specify an active domain too.
	    push @doms, $conn->list_domains ();
	    $isitinactive = "a libvirt domain";
	}
	foreach (@doms) {
	    if ($_->get_name () eq $images[0]) {
		$dom = $_;
		last;
	    }
	}
	die "$images[0] is not the name of $isitinactive\n" unless $dom;

	# Get the names of the image(s).
	my $xml = $dom->get_xml_description ();

	my $p = XML::XPath->new (xml => $xml);
	my @disks = $p->findnodes ('//devices/disk/source/@dev');
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

    return wantarray ? ($g, $conn, $dom) : $g
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
