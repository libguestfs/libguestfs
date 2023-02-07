#!/bin/bash -
# libguestfs
# Copyright (C) 2012-2023 Red Hat Inc.
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

# Test guestfish mount-local / mount-local-run commands.

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_fuse

set -e

if [ $# -gt 0 -a "$1" = "--run-test" ]; then
    # Create some files and read them back.
    echo 'hello' > test-mount-local-mp/hello
    chmod 0600 test-mount-local-mp/hello
    rm test-mount-local-mp/hello

    echo 'hello' > test-mount-local-mp/hello
    ln -s test-mount-local-mp/hello test-mount-local-mp/goodbye
    ln test-mount-local-mp/hello test-mount-local-mp/link
    rm test-mount-local-mp/goodbye test-mount-local-mp/link

    dd if=/dev/zero of=test-mount-local-mp/zero bs=10k count=10
    sync
    rm test-mount-local-mp/zero

    echo 'mount-local test successful' > test-mount-local-mp/ok

    # Unmount the mountpoint.
    ../fuse/guestunmount test-mount-local-mp

    exit 0
fi

rm -f test-mount-local.img test-mount-local.errors
rm -rf test-mount-local-mp

mkdir test-mount-local-mp

if ! guestfish -N test-mount-local.img=fs -m /dev/sda1 2>test-mount-local.errors <<EOF; then
mount-local test-mount-local-mp
! $0 --run-test &
mount-local-run

# /ok should have been created and left over by the test.
# If not, then the next command will fail.
cat /ok

EOF
    echo "$0: test failed."
    cat test-mount-local.errors
    exit 1
fi

rm test-mount-local.img test-mount-local.errors
rm -r test-mount-local-mp
