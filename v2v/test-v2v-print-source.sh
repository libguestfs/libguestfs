#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2014 Red Hat Inc.
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

# Test --print-source option.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
f=$top_builddir/test-data/phony-guests/windows.img

d=test-v2v-print-source.d
rm -rf $d
mkdir $d

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o local -os $d \
    --print-source > $d/output

mv $d/output $d/output.orig
< $d/output.orig \
grep -v 'Opening the source' |
grep -v 'Source guest information' |
sed -e 's,/.*/,/,' |
grep -v '^$' \
> $d/output

if [ "$(cat $d/output)" != "    source name: windows
hypervisor type: test
         memory: 1073741824 (bytes)
       nr vCPUs: 1
   CPU features: 
       firmware: unknown
        display: 
          video: qxl
          sound: 
disks:
	/windows.img (raw) [virtio-blk]
removable media:
NICs:
	Network \"default\" mac: 00:11:22:33:44:55 [virtio]" ]; then
    echo "$0: unexpected output from test:"
    cat $d/output.orig
    exit 1
fi

rm -r $d
