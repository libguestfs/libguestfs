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

# Test the handling of MD devices specified in /etc/fstab

set -e
export LANG=C

if [ -n "$SKIP_TEST_INSPECT_FSTAB_MD_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

# The first test requires a new Augeas lens for parsing mdadm.conf.
# If this is not present in the appliance or on the host, skip the
# test.
f=$(grep mdadm_conf.aug ../../appliance/supermin.d/hostfiles | head -1)
if [ -z "$f" -o ! -f "$f" ]; then
    echo "$0: test skipped because Augeas mdadm.conf lens is not available."
    exit 77
fi

guestfish=../../fish/guestfish

rm -f test1.img test.fstab test.output

# First, test the regular fedora image, which specifies /boot as /dev/md0
cp ../guests/fedora-md1.img test1.img
cp ../guests/fedora-md2.img test2.img

$guestfish -i test[12].img <<'EOF' | sort > test.output
  exists /boot/grub/grub.conf
EOF

if [ "$(cat test.output)" != "true" ]; then
    echo "$0: /boot not correctly mounted (/dev/md0)"
    exit 1
fi

# Test inspection when /boot is specfied as /dev/md/boot
cat <<'EOF' > test.fstab
/dev/VG/Root / ext2 default 0 0
/dev/md/boot /boot ext2 default 0 0
EOF

$guestfish -a test1.img -a test2.img <<'EOF'
  run
  mount-options "" /dev/VG/Root /
  upload test.fstab /etc/fstab
EOF

$guestfish -i test[12].img <<'EOF' | sort > test.output
  exists /boot/grub/grub.conf
EOF

if [ "$(cat test.output)" != "true" ]; then
    echo "$0: error: /boot not correctly mounted (/dev/md/boot)"
    cat test.output
    exit 1
fi

rm test.fstab
rm test[12].img
rm test.output
