#!/usr/bin/env perl
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

# Test journal using test data from
# test-data/phony-guests/fedora-journal.tar.xz which is incorporated
# into the Fedora test image in test-data/phony-guests/fedora.img.

use strict;
use warnings;

use Sys::Guestfs;

exit 77 if $ENV{SKIP_TEST_JOURNAL_PL};

my $g = Sys::Guestfs->new ();
$g->add_drive ("../test-data/phony-guests/fedora.img",
               readonly => 1, format => "raw");
$g->launch ();

# If journal feature is not available, bail.
unless ($g->feature_available (["journal"])) {
    warn "$0: skipping test because journal feature is not available\n";
    exit 77;
}

# Mount the root filesystem.
$g->mount_ro ("/dev/VG/Root", "/");

# Open the journal.
$g->journal_open ("/var/log/journal");

eval {
    # Count the number of journal entries by iterating over them.
    # Save the first few.
    my $count = 0;
    my @entries = ();
    while ($g->journal_next ()) {
        $count++;
        my @fields = $g->journal_get ();
        # Turn the fields into a hash of field name -> data.
        my %fields = ();
        $fields{$_->{attrname}} = $_->{attrval} foreach @fields;
        push @entries, \%fields if $count <= 5;
    }

    die "incorrect # journal entries (got $count, expecting 2459)"
        unless $count == 2459;

    # Check a few fields.
    foreach ([0, "PRIORITY", "6"],
             [0, "MESSAGE_ID", "ec387f577b844b8fa948f33cad9a75e6"],
             [1, "_TRANSPORT", "driver"],
             [1, "_UID", "0"],
             [2, "_BOOT_ID", "1678ffea9ef14d87a96fa4aecd575842"],
             [2, "_HOSTNAME", "f20rawhidex64.home.annexia.org"],
             [4, "SYSLOG_IDENTIFIER", "kernel"]) {
        my %fields = %{$entries[$_->[0]]};
        my $fieldname = $_->[1];
        die "field ", $fieldname, " does not exist"
            unless exists $fields{$fieldname};
        my $expected = $_->[2];
        my $actual = $fields{$fieldname};
        die "unexpected data: got ", $fieldname, "=", $actual,
        ", expected ", $fieldname, "=", $expected unless $actual eq $expected;
    }
};
my $error = $@;
$g->journal_close ();
$g->shutdown ();
$g->close ();

die $error if $error;
exit 0
