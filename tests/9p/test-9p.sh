#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

# Test 9p filesystems for Avi.  As there is no way to add a 9p disk to
# libguestfs, we have to fake it using 'config'.

set -e

if [ -n "$SKIP_TEST_9P_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

backend="$(../../fish/guestfish get-backend)"
if [[ "$backend" != "direct" ]]; then
    echo "$0: test skipped because backend ($backend) is not 'direct'."
    exit 77
fi

rm -f test.img test.out

../../fish/guestfish <<EOF
# This dummy disk is not actually used, but libguestfs requires one.
sparse test.img 1M

config -device 'virtio-9p-pci,fsdev=test9p,mount_tag=test9p'
config -fsdev 'local,id=test9p,path=$(pwd),security_model=passthrough'

run

mount-9p test9p /
ls / | grep 'test-9p.sh\$' > test.out

EOF

if [ "$(cat test.out)" != "test-9p.sh" ]; then
    echo "$0: unexpected output from listing 9p directory:"
    cat test.out
fi

rm test.img test.out
