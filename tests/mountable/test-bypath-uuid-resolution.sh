#!/bin/bash -
# libguestfs
# Copyright (C) 2025 Red Hat Inc.
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

# Test /dev/disk/by-path to UUID resolution in fstab

source ./functions.sh
set -e
set -x

skip_if_skipped
skip_unless_phony_guest fedora.img

canonical="sed s,/dev/vd,/dev/sd,g"
output=bypath-uuid-resolution.output
overlay=bypath-uuid-resolution.qcow2
fstab=bypath-uuid-resolution.fstab
rm -f $output $overlay $fstab

# Create overlay image based on fedora
guestfish -- \
  disk-create $overlay qcow2 -1 \
    backingfile:$top_builddir/test-data/phony-guests/fedora.img \
    backingformat:raw

# Create fstab with /dev/disk/by-path entries
# Note: Root (/) is on LVM in fedora.img, so we test with /boot which is on a partition
cat <<'EOF' > $fstab
# Test /dev/disk/by-path resolution for partition
/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:0:0-part1 /boot ext2 defaults 0 0
# Root is kept as LVM for now
/dev/VG/Root / ext2 defaults 0 0
EOF

# Upload modified fstab
guestfish --format=qcow2 -a $overlay <<EOF
run
mount /dev/VG/Root /
upload $fstab /etc/fstab
umount-all
EOF

# Test mountpoint resolution
guestfish --format=qcow2 -a $overlay <<EOF | sort | $canonical > $output
run
inspect-os
inspect-get-mountpoints /dev/VG/Root
EOF

# Check that /boot was resolved to UUID
# The by-path entry should be converted to UUID= format
if grep -q "^/boot: UUID=" $output; then
    echo "PASS: /dev/disk/by-path entry for /boot resolved to UUID"
else
    echo "$0: FAIL: /boot not resolved to UUID"
    echo "Expected UUID= entry for /boot, got:"
    cat $output
    exit 1
fi

# Verify root is still on LVM (unchanged)
if grep -q "^/: /dev/VG/Root" $output; then
    echo "PASS: Root LVM device preserved"
else
    echo "$0: FAIL: Root device changed unexpectedly"
    cat $output
    exit 1
fi

rm -f $output $overlay $fstab
