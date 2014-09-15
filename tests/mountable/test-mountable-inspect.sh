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
export LANG=C

canonical="sed s,/dev/vd,/dev/sd,g"

# Allow the test to be skipped since btrfs is often broken.
if [ -n "$SKIP_TEST_MOUNTABLE_INSPECT_SH" ]; then
    echo "$0: skipping test because environment variable is set."
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support qcow2"
    exit 77
fi

# Bail if btrfs is not available.
if ! guestfish -a /dev/null run : available btrfs; then
    echo "$0: skipping test because btrfs is not available"
    exit 77
fi

rm -f root.tmp test.qcow2 test.output

# Start with the regular (good) fedora image, modify /etc/fstab
# and then inspect it.
guestfish -- \
  disk-create test.qcow2 qcow2 -1 \
    backingfile:../guests/fedora-btrfs.img backingformat:raw

# Test that basic inspection works and the expected filesystems are
# found
guestfish -a test.qcow2 -i <<'EOF' | sort | $canonical > test.output
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
guestfish -a test.qcow2 -i <<'EOF' > test.output
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
