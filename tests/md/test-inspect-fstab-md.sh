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

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest fedora-md1.img
skip_unless_phony_guest fedora-md2.img

rm -f inspect-fstab-md-{1,2}.img inspect-fstab-md.fstab inspect-fstab-md.output

# First, test the regular fedora image, which specifies /boot as /dev/md0
cp $top_builddir/test-data/phony-guests/fedora-md1.img inspect-fstab-md-1.img
cp $top_builddir/test-data/phony-guests/fedora-md2.img inspect-fstab-md-2.img

guestfish -i --format=raw -a inspect-fstab-md-1.img --format=raw -a inspect-fstab-md-2.img <<'EOF' | sort > inspect-fstab-md.output
  exists /boot/grub/grub.conf
EOF

if [ "$(cat inspect-fstab-md.output)" != "true" ]; then
    echo "$0: /boot not correctly mounted (/dev/md0)"
    exit 1
fi

# Test inspection when /boot is specfied as /dev/md/bootdev
cat <<'EOF' > inspect-fstab-md.fstab
/dev/VG/Root / ext2 default 0 0
/dev/md/bootdev /boot ext2 default 0 0
EOF

guestfish --format=raw -a inspect-fstab-md-1.img --format=raw -a inspect-fstab-md-2.img <<'EOF'
  run
  mount /dev/VG/Root /
  upload inspect-fstab-md.fstab /etc/fstab
EOF

guestfish -i --format=raw -a inspect-fstab-md-1.img --format=raw -a inspect-fstab-md-2.img <<'EOF' | sort > inspect-fstab-md.output
  exists /boot/grub/grub.conf
EOF

if [ "$(cat inspect-fstab-md.output)" != "true" ]; then
    echo "$0: error: /boot not correctly mounted (/dev/md/bootdev)"
    cat inspect-fstab-md.output
    exit 1
fi

rm inspect-fstab-md.fstab
rm inspect-fstab-md-[12].img
rm inspect-fstab-md.output
