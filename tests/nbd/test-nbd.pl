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

use strict;
use warnings;

use POSIX qw(getcwd);

use Sys::Guestfs;

my $disk = "../guests/fedora.img";

my $pid = 0;
END { kill 15, $pid if $pid > 0 };

exit 77 if $ENV{SKIP_TEST_NBD_PL};

if (Sys::Guestfs->new()->get_backend() eq "uml") {
    print "$0: test skipped because UML backend does not support NBD\n";
    exit 77
}

# Check we have qemu-nbd.
if (system ("qemu-nbd --help >/dev/null 2>&1") != 0) {
    print "$0: test skipped because qemu-nbd program not found\n";
    exit 77
}

if (! -r $disk || -z $disk) {
    print "$0: test skipped because $disk is not found\n";
    exit 77
}

my $has_format_opt = system ("qemu-nbd --help | grep -q -- --format") == 0;

sub run_test {
    my $readonly = shift;
    my $tcp = shift;

    my $server;
    my @qemu_nbd = ("qemu-nbd", $disk, "-t");
    if ($has_format_opt) {
        push @qemu_nbd, "--format", "raw";
    }
    if ($tcp) {
        # Choose a random port number.  XXX Should check it is not in use.
        my $port = int (60000 + rand (5000));
        push @qemu_nbd, "-p", $port;
        $server = "localhost:$port";
    }
    else {
        # qemu-nbd insists the socket path is absolute.
        my $cwd = getcwd ();
        my $socket = "$cwd/unix.sock";
        unlink "$socket";
        push @qemu_nbd, "-k", "$socket";
        $server = "unix:$socket";
    }

    # Run the NBD server.
    print "Starting ", join (" ", @qemu_nbd), " ...\n";
    $pid = fork ();
    if ($pid == 0) {
        exec (@qemu_nbd);
        die "qemu-nbd: $!";
    }

    # XXX qemu-nbd lacks any way to tell if it is awake and listening
    # for connections.  It could write a pid file or something.  Could
    # we check that the socket has been opened by looking in netstat?
    sleep (2);

    my $g = Sys::Guestfs->new ();

    # Add an NBD drive.
    $g->add_drive ("", readonly => $readonly, format => "raw",
                   protocol => "nbd", server => [$server]);

    # This dies if qemu cannot connect to the NBD server.
    $g->launch ();

    # Inspection is quite a thorough test:
    my @roots = $g->inspect_os ();
    die "roots should be a 1-sized array" unless @roots == 1;
    die "$roots[0] != /dev/VG/Root" unless $roots[0] eq "/dev/VG/Root";

    # Note we have to close the handle (hence killing qemu), and we
    # have to kill qemu-nbd.
    $g->close ();
    kill 15, $pid;
    waitpid ($pid, 0) or die "waitpid: $pid: $!";
    $pid = 0;
}

# Since read-only and read-write paths are quite different, we have to
# test both separately.
for my $readonly (1, 0) {
    if ($readonly && Sys::Guestfs->new()->get_backend() eq "direct") {
        printf "skipping readonly + appliance case:\n";
        printf "https://bugs.launchpad.net/qemu/+bug/1155677\n";
        next;
    }

    run_test ($readonly, 1);
}

# Test Unix domain socket codepath.
if (Sys::Guestfs->new()->get_backend() !~ /^libvirt/) {
    run_test (0, 0);
} else {
    printf "skipping Unix domain socket test:\n";
    printf "https://bugzilla.redhat.com/show_bug.cgi?id=922888\n";
}

exit 0
