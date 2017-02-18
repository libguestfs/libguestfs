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

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_feature_available btrfs

canonical="sed s,/dev/vd,/dev/sd,g"

rm -f root.tmp test.qcow2 test.output

# Start with the regular (good) fedora image, modify /etc/fstab
# and then inspect it.
guestfish -- \
  disk-create test.qcow2 qcow2 -1 \
    backingfile:../../test-data/phony-guests/fedora-btrfs.img backingformat:raw

# Test that basic inspection works and the expected filesystems are
# found
guestfish --format=qcow2 -a test.qcow2 -i <<'EOF' | sort | $canonical > test.output
  inspect-get-roots | head -1 > root.tmp
  <! echo inspect-get-mountpoints "`cat root.tmp`"
EOF

if [ "$(cat test.output)" != "/: btrfsvol:/dev/sda2/root
/boot: /dev/sda1
/home: btrfsvol:/dev/sda2/home" ]; then
    echo "$0: error #1: unexpected output from inspect-get-mountpoints"
    cat test.output
    exit 1
fi

# Additional sanity check: did we get the release name right?
guestfish --format=qcow2 -a test.qcow2 -i <<'EOF' > test.output
  inspect-get-roots | head -1 > root.tmp
  <! echo inspect-get-product-name "`cat root.tmp`"
EOF

if [ "$(cat test.output)" != "Fedora release 14 (Phony)" ]; then
    echo "$0: error #2: unexpected output from inspect-get-product-name"
    cat test.output
    exit 1
fi

rm root.tmp
rm test.qcow2
rm test.output
