#!/usr/bin/env perl
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

# Test that console debug messages work.

use strict;
use warnings;

use Sys::Guestfs;

exit 77 if $ENV{SKIP_TEST_CONSOLE_DEBUG_PL};

my $g = Sys::Guestfs->new ();

my $log_messages = "";
my $callback_invoked = 0;

sub callback {
    my $ev = shift;
    my $eh = shift;
    my $buf = shift;
    my $array = shift;

    $log_messages .= $buf;
    $callback_invoked++;
}

my $events = $Sys::Guestfs::EVENT_APPLIANCE;
my $eh;
$eh = $g->set_event_callback (\&callback, $events);

$g->set_verbose (1);

$g->add_drive_ro ("/dev/null");
$g->launch ();

my $magic = "abcdefgh9876543210";

$g->debug ("print", [$magic]);

$g->close ();

# Ensure the magic string appeared in the log messages.
if ($log_messages !~ /$magic/) {
    print "$0: log_messages does not contain magic string '$magic'\n";
    print "$0: callback was invoked $callback_invoked times\n";
    print "$0: log messages were:\n";
    print "-" x 40, "\n";
    print $log_messages;
    print "-" x 40, "\n";
    exit 1
}
