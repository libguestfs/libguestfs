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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Test various aspects of core inspection of /etc/fstab.
# This also tests: https://bugzilla.redhat.com/668574

set -e
export LANG=C

guestfish=../fish/guestfish

rm -f test1.img test.fstab test.output

# Start with the regular (good) fedora image, modify /etc/fstab
# and then inspect it.
cp ../images/fedora.img test1.img

cat <<'EOF' > test.fstab
/dev/VG/Root / ext2 default 0 0

# Xen-style partition names.
/dev/xvda1 /boot ext2 default 0 0

# Non-existant device.
/dev/sdb3 /var ext2 default 0 0

# Non-existant mountpoint.
/dev/VG/LV1 /nosuchfile ext2 default 0 0
EOF

$guestfish -a test1.img <<'EOF'
  run
  mount-options "" /dev/VG/Root /
  upload test.fstab /etc/fstab
EOF

rm test.fstab

# This will give a warning, but should not fail.
$guestfish -a test1.img -i <<'EOF' | sort > test.output
  inspect-get-mountpoints /dev/VG/Root
EOF

rm test1.img

if [ "$(cat test.output)" != "/: /dev/VG/Root
/boot: /dev/vda1
/nosuchfile: /dev/VG/LV1
/var: /dev/sdb3" ]; then
    echo "$0: error: unexpected output from inspect-get-mountpoints command"
    cat test.output
    exit 1
fi

rm test.output
