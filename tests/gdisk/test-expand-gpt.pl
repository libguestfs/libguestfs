#!/usr/bin/env perl
# Copyright (C) 2015 Maxim Perevedentsev mperevedentsev@virtuozzo.com
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

sub tests {
	my $g = Sys::Guestfs->new ();

	foreach ("gpt", "mbr") {
		$g->disk_create ("gdisk/disk_$_.img",
                                 "qcow2", 50 * 1024 * 1024);
		$g->add_drive ("gdisk/disk_$_.img", format => "qcow2");
	}

	$g->launch ();

	$g->part_disk ("/dev/sda", "gpt");
	$g->part_disk ("/dev/sdb", "mbr");

	$g->close ();

	die if system ("qemu-img resize gdisk/disk_gpt.img 100M >/dev/null");

	$g = Sys::Guestfs->new ();

	foreach ("gpt", "mbr") {
		$g->add_drive ("gdisk/disk_$_.img", format => "qcow2");
	}

	$g->launch ();
	die if $g->part_expand_gpt ("/dev/sda");

	my $output = $g->debug ("sh", ["sgdisk", "-p", "/dev/sda"]);
	die if $output eq "";
	$output =~ s/\n/ /g;
	$output =~ s/.*last usable sector is (\d+).*/$1/g;

	my $end_sectors = 100 * 1024 * 2 - $output;
	die unless $end_sectors <= 34;

	# Negative test.
	eval { $g->part_expand_gpt ("/dev/sdb") };
	die unless $@;

	$g->close ();

	# Disk shrink test
	die if system ("qemu-img resize --shrink gdisk/disk_gpt.img 50M >/dev/null");

	$g = Sys::Guestfs->new ();

	$g->add_drive ("gdisk/disk_gpt.img", format => "qcow2");
	$g->launch ();

	die if $g->part_expand_gpt ("/dev/sda");

	$output = $g->debug ("sh", ["sgdisk", "-p", "/dev/sda"]);
	die if $output eq "";
	$output =~ s/\n/ /g;
	$output =~ s/.*last usable sector is (\d+).*/$1/g;

	$end_sectors = 50 * 1024 * 2 - $output;
	die unless $end_sectors <= 34;
}

eval { tests() };
system ("rm -f gdisk/disk_*.img");
if ($@) {
    die;
}
exit 0
