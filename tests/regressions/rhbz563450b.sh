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
# Test only CD-ROM disk images can be added

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_test_iso

rm -f rhbz563450b.out

guestfish --ro > rhbz563450b.out <<EOF
add-cdrom ../test-data/test.iso

run

list-devices | sed -r 's,^/dev/[abce-ln-z]+d,/dev/sd,'

ping-daemon
EOF

if [ "$(cat rhbz563450b.out)" != "/dev/sda" ]; then
    echo "$0: unexpected output:"
    cat rhbz563450b.out
    exit 1
fi

rm -f rhbz563450b.out
