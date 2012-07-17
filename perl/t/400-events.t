# libguestfs Perl bindings -*- perl -*-
# Copyright (C) 2011 Red Hat Inc.
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
use Test::More tests => 7;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
ok ($g);

sub log_callback {
    my $ev = shift;
    my $eh = shift;
    my $buf = shift;
    my $array = shift;

    chomp $buf if $ev == $Sys::Guestfs::EVENT_APPLIANCE;

    # We don't get to see this output because it is eaten up by the
    # test harness, but generate it anyway.
    printf("perl event logged: event=0x%x eh=%d buf='%s' array=[%s]\n",
           $ev, $eh, $buf, join (", ", @$array));
}

my $close_invoked = 0;

sub close_callback {
    $close_invoked++;
    log_callback (@_);
}

# Register an event callback for all log messages.
my $events = $Sys::Guestfs::EVENT_APPLIANCE | $Sys::Guestfs::EVENT_LIBRARY |
    $Sys::Guestfs::EVENT_TRACE;
my $eh;
$eh = $g->set_event_callback (\&log_callback, $events);
ok ($eh >= 0);

# Check that the close event is invoked.
$g->set_event_callback (\&close_callback, $Sys::Guestfs::EVENT_CLOSE);
ok ($eh >= 0);

# Now make sure we see some messages.
$g->set_trace (1);
$g->set_verbose (1);
ok (1);

# Do some stuff.
$g->add_drive_ro ("/dev/null");
$g->set_autosync (1);
ok (1);

# Close the handle.  The close callback should be invoked.
ok ($close_invoked == 0);
undef $g;
ok ($close_invoked == 1);
