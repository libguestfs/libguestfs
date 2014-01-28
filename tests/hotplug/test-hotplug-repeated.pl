#!/usr/bin/perl
# Copyright (C) 2012 Red Hat Inc.
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Test repeatedly hotplugging a single disk.

use strict;
use warnings;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();

# Skip the test if the default backend isn't libvirt, since only
# the libvirt backend supports hotplugging.
my $backend = $g->get_backend ();
unless ($backend eq "libvirt" || $backend =~ /^libvirt:/) {
    print "$0: test skipped because backend ($backend) is not libvirt\n";
    exit 77
}

$g->launch ();

# Create a temporary disk.
$g->disk_create ("test-hotplug-repeated.img", "raw", 512 * 1024 * 1024);

my $start_t = time ();
while (time () - $start_t <= 60) {
    $g->add_drive ("test-hotplug-repeated.img",
                   label => "a", format => "raw");
    $g->remove_drive ("a");
}

# There should be no drives remaining.
my @devices = $g->list_devices ();
die unless 0 == @devices;

$g->shutdown ();
$g->close ();

unlink "test-hotplug-repeated.img";

exit 0
