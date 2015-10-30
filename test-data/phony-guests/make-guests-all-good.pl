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

# Make the 'guests-all-good.xml' file.

use strict;
use warnings;

my $outdir = `pwd`; chomp $outdir;

print <<__EOT__;
<!--
This file is generated from $0.

ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.

To use the test guests by name, specify the following libvirt URI:
test://\$(abs_builddir)/guests-all-good.xml

eg:
  ./run ./df/virt-df -c test://$outdir/guests-all-good.xml
  ./run ./align/virt-alignment-scan -c test://$outdir/guests-all-good.xml

Note this differs from 'guests.xml' just in that none of these guests
have missing disks, etc.
-->
<node>
__EOT__

foreach (@ARGV) {
    my $name = $_;
    $name =~ s/.img//;

    if (-f $_ && -s $_) {
        print <<__EOT__;
  <domain type='test'>
    <name>$name</name>
    <memory>1048576</memory>
    <os>
      <type>hvm</type>
      <boot dev='hd'/>
    </os>
    <devices>
      <disk type='file' device='disk'>
        <driver name='qemu' type='raw'/>
        <source file='$outdir/$_'/>
        <target dev='vda' bus='virtio'/>
      </disk>
    </devices>
  </domain>
__EOT__
    }
}

print "</node>";
