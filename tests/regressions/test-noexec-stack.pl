#!/usr/bin/perl
# Copyright (C) 2009 Red Hat Inc.
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

die("NOEXEC_CHECK not set") unless(exists($ENV{NOEXEC_CHECK}));

my @files = split(/ /, $ENV{NOEXEC_CHECK});

FILES: foreach my $file (@files) {
    my $output;
    my @cmd = ('readelf', '-l', $file);
    open($output, '-|', @cmd)
        or die("$0: failed to run: '".join(' ', @cmd)."': $!\n");

    my $offset;
    my $line = 1;

    # Find the offset of the Flags field
    while(<$output>) {
        next unless(/^\s*Type\b/);

        my @lines;
        push(@lines, $_);

        # Look for a Flg field on this line (32 bit)
        $offset = index($_, 'Flg ');

        if(-1 == $offset) {
            # 64 bit is split over 2 lines. Look for a Flags field on the next
            # line
            $_ = <$output>;
            $offset = index($_, 'Flags ');
            $line = 2;
            push(@lines, $_);
        }

        die("Unrecognised header: ".join("\n", @lines)) if(-1 == $offset);
        last;
    }

    # Find the GNU_STACK entry
    while(<$output>) {
        next unless(/^\s*GNU_STACK\b/);

        # Skip over input lines according to the header
        for(my $i = 1; $i < $line; $i++) {
            $_ = <$output>;
        }

        my $flags = substr($_, $offset, 3);

        $flags =~ /^[ R][ W]([ E])$/ or die("Unrecognised flags: $flags");

        if('E' eq $1) {
            print "***** $file has an executable stack *****\n";
            exit(1);
        }

        next FILES;
    }

    die("Didn't find GNU_STACK entry");
}
