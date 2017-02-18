#!/bin/bash -
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

# https://bugzilla.redhat.com/show_bug.cgi?id=563450
# Test the order of added images

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest fedora.img
skip_unless_phony_guest debian.img
skip_unless_test_iso

rm -f rhbz563450.out

guestfish --ro > rhbz563450.out <<EOF
add $top_builddir/test-data/phony-guests/fedora.img readonly:true format:raw
add-cdrom $top_builddir/test-data/test.iso
add $top_builddir/test-data/phony-guests/debian.img readonly:true format:raw

run

list-devices | sed -r 's,^/dev/[abce-ln-z]+d,/dev/sd,'
echo ----
list-partitions | sed -r 's,^/dev/[abce-ln-z]+d,/dev/sd,'

ping-daemon
EOF

if [ "$(cat rhbz563450.out)" != "/dev/sda
/dev/sdb
/dev/sdc
----
/dev/sda1
/dev/sda2
/dev/sdc1
/dev/sdc2" ]; then
    echo "$0: unexpected output:"
    cat rhbz563450.out
    exit 1
fi

rm -f rhbz563450.out
