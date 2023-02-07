#!/usr/bin/env perl
# libguestfs
# Copyright (C) 2012-2023 Red Hat Inc.
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

use strict;
use warnings;

my $progname = $0;
$progname =~ s{.*/}{};

# This test requires the perl 'Expect' module.  If it doesn't
# exist, skip the test.
eval "use Expect";

unless (exists $INC{"Expect.pm"}) {
    print STDERR "$progname: test skipped because there is no perl Expect module\n";
    exit 77
}

# Run virt-rescue and make sure we get to the rescue prompt.
my $exp = Expect->spawn ("virt-rescue", "--scratch")
    or die "$progname: Expect could not spawn virt-rescue: $!\n";

my $timeout = 5 * 60;
my $r;
$r = $exp->expect ($timeout, '><rescue>');

unless (defined $r) {
    my $see_errors;
    if ($ENV{LIBGUESTFS_DEBUG}) {
        $see_errors = "Look for errors in the debug output above."
    } else {
        $see_errors = "Try setting LIBGUESTFS_DEBUG=1 and running the test again."
    }
    die "$progname: virt-rescue did not print the '><rescue>' prompt within\n$timeout seconds, or exited before getting to the prompt.\n$see_errors\n";
}

# Send a simple command; expect to get back to the prompt.
$exp->send ("ls -1\n");

$timeout = 60;
$r = $exp->expect ($timeout, '><rescue>');

unless (defined $r) {
    die "$progname: virt-rescue did not return to the prompt after sending a command\n";
}

# Check virt-rescue shell exits when we send the 'exit' command.
$exp->send ("exit\n");
$exp->soft_close ();
