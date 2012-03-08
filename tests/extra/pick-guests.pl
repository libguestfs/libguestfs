#!/usr/bin/perl -w
# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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

# Pick guests at random on the local machine which are accessible.
# Note that the Makefile sets $LIBVIRT_DEFAULT_URI.

use strict;

use Sys::Guestfs;
use Sys::Virt;
use List::Util qw(shuffle);

die "$0 nr-guests\n" unless @ARGV == 1;
my $n = $ARGV[0];

my $vmm = Sys::Virt->new;
my @domains = ($vmm->list_domains, $vmm->list_defined_domains);

# Only guests which are accessible by the current (non-root) user.  On
# the machine where I run these tests, I have added my user account to
# the 'disk' group, so that most guests are accessible.  However
# because libvirt changes the permissions on guest disks, a guest
# which has been run on the machine becomes inaccessible, hence the
# need for this code - RWMJ.
my @accessible;
foreach my $dom (@domains) {
    my $name = $dom->get_name;
    my $g = Sys::Guestfs->new;
    eval {
        $g->add_domain ($name, readonly => 1);
        # $g->launch (); - don't actually need to do this
    };
    push @accessible, $name unless $@;
}

# Randomize the list of guests.
@accessible = shuffle (@accessible);

$n = @accessible if @accessible < $n;

# Return the first n guests from the list.
for (my $i = 0; $i < $n; ++$i) {
    print $accessible[$i], "\n";
}
