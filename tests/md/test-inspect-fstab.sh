#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# Test various aspects of core inspection of /etc/fstab.
# This also tests: https://bugzilla.redhat.com/668574

set -e
export LANG=C

guestfish=../../fish/guestfish
canonical="sed s,/dev/vd,/dev/sd,g"

rm -f test1.qcow2 test.fstab test.output

# Start with the regular (good) fedora image, modify /etc/fstab
# and then inspect it.
qemu-img create -F raw -b ../guests/fedora.img -f qcow2 test1.qcow2

cat <<'EOF' > test.fstab
/dev/VG/Root / ext2 default 0 0

# Xen-style partition names.
/dev/xvda1 /boot ext2 default 0 0

# Non-existent device.
/dev/sdb3 /var ext2 default 0 0

# Non-existent mountpoint.
/dev/VG/LV1 /nosuchfile ext2 default 0 0

# /dev/disk/by-id path (RHBZ#627675).
/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001 /id ext2 default 0 0
/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001-part1 /id1 ext2 default 0 0
/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001-part3 /id3 ext2 default 0 0
EOF

$guestfish -a test1.qcow2 <<'EOF'
  run
  mount-options "" /dev/VG/Root /
  upload test.fstab /etc/fstab
EOF

# This will give a warning, but should not fail.
$guestfish -a test1.qcow2 -i <<'EOF' | sort | $canonical > test.output
  inspect-get-mountpoints /dev/VG/Root
EOF

if [ "$(cat test.output)" != "/: /dev/VG/Root
/boot: /dev/sda1
/id1: /dev/sda1
/id3: /dev/disk/by-id/ata-QEMU_HARDDISK_QM00001-part3
/id: /dev/disk/by-id/ata-QEMU_HARDDISK_QM00001
/nosuchfile: /dev/VG/LV1
/var: /dev/sdb3" ]; then
    echo "$0: error #1: unexpected output from inspect-get-mountpoints command"
    cat test.output
    exit 1
fi

# Test device name hints

cat <<'EOF' > test.fstab
/dev/VG/Root / ext2 default 0 0

# Device name which requires a hint
/dev/xvdg1 /boot ext2 default 0 0
EOF

$guestfish -a test1.qcow2 <<'EOF'
  run
  mount-options "" /dev/VG/Root /
  upload test.fstab /etc/fstab
EOF

$guestfish <<'EOF' | $canonical > test.output
  add-drive-opts test1.qcow2 readonly:true name:xvdg
  run
  inspect-os
  inspect-get-mountpoints /dev/VG/Root
EOF

if [ "$(cat test.output)" != "/dev/VG/Root
/: /dev/VG/Root
/boot: /dev/sda1" ]; then
    echo "$0: error #2: unexpected output from inspect-get-mountpoints command"
    cat test.output
    exit 1
fi

cat <<'EOF' > test.fstab
/dev/VG/Root / ext2 default 0 0

# cciss device which requires a hint
/dev/cciss/c1d3p1 /boot ext2 default 0 0

# cciss device, whole disk
/dev/cciss/c1d3 /var ext2 default 0 0
EOF

$guestfish -a test1.qcow2 <<'EOF'
  run
  mount-options "" /dev/VG/Root /
  upload test.fstab /etc/fstab
EOF

$guestfish <<'EOF' | $canonical > test.output
  add-drive-opts test1.qcow2 readonly:true name:cciss/c1d3
  run
  inspect-os
  inspect-get-mountpoints /dev/VG/Root
EOF

if [ "$(cat test.output)" != "/dev/VG/Root
/: /dev/VG/Root
/boot: /dev/sda1
/var: /dev/sda" ]; then
    echo "$0: error #3: unexpected output from inspect-get-mountpoints command"
    cat test.output
    exit 1
fi

rm test.fstab
rm test1.qcow2
rm test.output
