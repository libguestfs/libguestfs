#!/bin/bash -
# libguestfs virt-inspector test script
# Copyright (C) 2012-2014 Red Hat Inc.
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

export LANG=C
set -e
set -x

# Allow this test to be skipped.
if [ -n "$SKIP_TEST_VIRT_INSPECTOR_SH" ]; then
    echo "$0: skipping test because SKIP_TEST_VIRT_INSPECTOR_SH is set."
    exit 77
fi

# ntfs-3g can't set UUIDs right now, so ignore just that <uuid>.
diff_ignore="-I <uuid>[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]</uuid>"

for f in ../tests/guests/{debian,fedora,ubuntu,windows}.img; do
    # Ignore zero-sized windows.img if ntfs-3g is not installed.
    if [ -s "$f" ]; then
        b=$(basename "$f" .xml)
	$VG virt-inspector -a "$f" > "actual-$b.xml"
        # This 'diff' command will fail (because of -e option) if there
        # are any differences.
        diff -ur $diff_ignore "expected-$b.xml" "actual-$b.xml"
    fi
done

# We could also test this image, but mdadm is problematic for
# many users.
# $VG virt-inspector \
#   -a ../tests/guests/fedora-md1.img \
#   -a ../tests/guests/fedora-md2.img
