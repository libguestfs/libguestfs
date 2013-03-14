#!/usr/bin/perl
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

use strict;
use warnings;

use Sys::Guestfs;

my $disk = "../guests/fedora.img";

exit 77 if $ENV{SKIP_TEST_NBD_PL};

# Check we have qemu-nbd.
if (system ("qemu-nbd --help >/dev/null 2>&1") != 0) {
    print "$0: test skipped because qemu-nbd program not found\n";
    exit 77
}

if (! -r $disk || -z $disk) {
    print "$0: test skipped because $disk is not found\n";
    exit 77
}

# Since read-only and read-write paths are quite different, we have to
# test both separately.
my $readonly;
for $readonly (1, 0) {
    if ($readonly && Sys::Guestfs->new()->get_attach_method() eq "appliance") {
        printf "skipping readonly + appliance case:\n";
        printf "https://bugs.launchpad.net/qemu/+bug/1155677\n";
        next;
    }

    # Choose a random port number.  XXX Should check it is not in use.
    my $port = int (60000 + rand (5000));

    # Run the NBD server.
    print "Starting qemu-nbd server on port $port ...\n";
    my $pid = fork ();
    if ($pid == 0) {
        exec ("qemu-nbd", $disk, "-p", $port, "-t");
        die "qemu-nbd: $!";
    }

    my $g = Sys::Guestfs->new ();

    # Add an NBD drive.
    $g->add_drive ("", readonly => $readonly, format => "raw",
                   protocol => "nbd", server => "localhost", port => $port);

    # XXX qemu-nbd lacks any way to tell if it is awake and listening
    # for connections.  It could write a pid file or something.  Could
    # we check that the socket has been opened by looking in netstat?
    sleep (2);

    # This dies if qemu cannot connect to the NBD server.
    $g->launch ();

    # Inspection is quite a thorough test:
    my $root = $g->inspect_os ();
    die "$root != /dev/VG/Root" unless $root eq "/dev/VG/Root";

    # Note we have to close the handle (hence killing qemu), and we
    # have to kill qemu-nbd.
    $g->close ();
    kill 15, $pid;
    waitpid ($pid, 0) or die "waitpid: $pid: $!";
}

exit 0
