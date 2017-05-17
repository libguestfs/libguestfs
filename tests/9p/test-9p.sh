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

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_backend direct

# The name of the virtio-9p device is different on some architectures.
case "$(uname -m)" in
    arm*)
	virtio_9p=virtio-9p-device
	;;
    s390*)
	virtio_9p=virtio-9p-ccw
	;;
    *)
	virtio_9p=virtio-9p-pci
	;;
esac

rm -f test-9p.img test-9p.out

guestfish <<EOF
# This dummy disk is not actually used, but libguestfs requires one.
sparse test-9p.img 1M

config -device '$virtio_9p,fsdev=test9p,mount_tag=test9p'
config -fsdev 'local,id=test9p,path=${abs_srcdir},security_model=passthrough'

run

mount-9p test9p /
ls / | grep 'test-9p.sh\$' > test-9p.out

EOF

if [ "$(cat test-9p.out)" != "test-9p.sh" ]; then
    echo "$0: unexpected output from listing 9p directory:"
    cat test-9p.out
    exit 1
fi

rm test-9p.img test-9p.out
