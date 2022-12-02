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

my $pid = 0;
END { kill 15, $pid if $pid > 0 };

exit 77 if $ENV{SKIP_TEST_NBD_PL};

# Check we have qemu-nbd.
if (system ("qemu-nbd --help >/dev/null 2>&1") != 0) {
    print "$0: test skipped because qemu-nbd program not found\n";
    exit 77
}

# Make a local copy of the disk so we can open it for writes.
my $disk = "../test-data/phony-guests/fedora.img";
if (! -r $disk || -z $disk) {
    print "$0: test skipped because $disk is not found\n";
    exit 77
}

system ("cp $disk fedora-nbd.img") == 0 || die;
$disk = "fedora-nbd.img";

my $has_format_opt = system ("qemu-nbd --help | grep -q -- --format") == 0;

sub run_test {
    my $readonly = shift;
    my $tcp = shift;

    my $cwd = getcwd ();
    my $server;
    my $pidfile = "$cwd/nbd/nbd.pid";
    unlink "$pidfile";
    my @qemu_nbd = ("qemu-nbd", $disk, "-t", "--pid-file", $pidfile);
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
        my $socket = "$cwd/nbd/unix.sock";
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

    # Wait for the pid file to appear.
    for (my $i = 0; $i < 60; ++$i) {
        last if -f $pidfile;
        sleep 1
    }
    die "qemu-nbd did not start up\n" if ! -f $pidfile;

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
    unlink $pidfile
}

# Since read-only and read-write paths are quite different, we have to
# test both separately.
for my $readonly (1, 0) {
    run_test ($readonly, 1);
}

# Test Unix domain socket codepath.
run_test (0, 0);

unlink $disk;

exit 0
