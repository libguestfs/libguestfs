#!/bin/bash -
# libguestfs
# Copyright (C) 2010 Red Hat Inc.
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

# Test tar_in call when we upload something which is larger than
# available space.
# https://bugzilla.redhat.com/show_bug.cgi?id=580246

set -e
export LANG=C

rm -f test.img test.tar

dd if=/dev/zero of=test.img bs=1M count=2
tar cf test.tar test.img

output=$(
../../fish/guestfish 2>&1 <<'EOF'
add test.img
run
mkfs ext2 /dev/sda
mount /dev/sda /
-tar-in test.tar /
EOF
)

rm -f test.img test.tar

# Check for error message in the output.
if [[ ! $output =~ libguestfs:.error:.tar_in ]]; then
    echo "Missing error message from tar-in (expecting an error message)"
    exit 1
fi
