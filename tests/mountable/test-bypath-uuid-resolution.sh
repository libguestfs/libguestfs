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

# Test that /dev/disk/by-path entries in fstab are resolved to
# appliance device names during inspection.

source ./functions.sh
set -e
set -x

skip_if_skipped
skip_unless_phony_guest fedora.img

canonical="sed s,/dev/vd,/dev/sd,g"

root=bypath-resolution.tmp
output=bypath-resolution.output
overlay=bypath-resolution.qcow2
fstab=bypath-resolution.fstab
rm -f $root $output $overlay $fstab

# Create overlay image based on fedora.
guestfish -- \
  disk-create $overlay qcow2 -1 \
    backingfile:$top_builddir/test-data/phony-guests/fedora.img \
    backingformat:raw

# Create fstab with a /dev/disk/by-path entry for /boot.
# Root (/) is on LVM in fedora.img so we keep that unchanged.
cat <<'EOF' > $fstab
/dev/disk/by-path/pci-0000:00:04.0-scsi-0:0:0:0-part1 /boot ext2 defaults 0 0
/dev/VG/Root / ext2 defaults 0 0
EOF

# Upload modified fstab.
guestfish --format=qcow2 -a $overlay <<EOF
run
mount /dev/VG/Root /
upload $fstab /etc/fstab
umount-all
EOF

# Run inspection and get mountpoints.
guestfish --format=qcow2 -a $overlay -i <<EOF | sort | $canonical > $output
  inspect-get-roots | head -1 > $root
  <! echo inspect-get-mountpoints \"\`cat $root\`\"
EOF

# The by-path entry for /boot should resolve to /dev/sda1.
if [ "$(cat $output)" != "/: /dev/VG/Root
/boot: /dev/sda1" ]; then
    echo "$0: error: unexpected output from inspect-get-mountpoints"
    cat $output
    exit 1
fi

rm -f $root $output $overlay $fstab
