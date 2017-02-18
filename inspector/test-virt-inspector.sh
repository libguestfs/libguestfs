#!/bin/bash -
# libguestfs virt-inspector test script
# Copyright (C) 2012-2017 Red Hat Inc.
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

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

# ntfs-3g can't set UUIDs right now, so ignore just that <uuid>.
diff_ignore="-I <uuid>[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]</uuid>"

for f in ../test-data/phony-guests/{debian,fedora,ubuntu,archlinux,coreos,windows}.img; do
    # Ignore zero-sized windows.img if ntfs-3g is not installed.
    if [ -s "$f" ]; then
        b=$(basename "$f" .xml)
	$VG virt-inspector --format=raw -a "$f" > "actual-$b.xml"
        # This 'diff' command will fail (because of -e option) if there
        # are any differences.
        diff -ur $diff_ignore "expected-$b.xml" "actual-$b.xml"
    fi
done

# We could also test this image, but mdadm is problematic for
# many users.
# $VG virt-inspector \
#   -a ../test-data/phony-guests/fedora-md1.img \
#   -a ../test-data/phony-guests/fedora-md2.img
