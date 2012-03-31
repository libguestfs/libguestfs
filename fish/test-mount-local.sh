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

# Test guestfish mount-local / mount-local-run commands.

# Skip if no FUSE.

test -w /dev/fuse || {
    echo "$0: Skipping this test"
    echo "  because /dev/fuse is missing or not writable by the current user."
    exit 0
}

set -e

if [ $# -gt 0 -a "$1" = "--run-test" ]; then
    # Create some files and read them back.
    echo 'hello' > mp/hello
    chmod 0600 mp/hello
    rm mp/hello

    echo 'hello' > mp/hello
    ln -s mp/hello mp/goodbye
    ln mp/hello mp/link
    rm mp/goodbye mp/link

    dd if=/dev/zero of=mp/zero bs=10k count=10
    sync
    rm mp/zero

    echo 'mount-local test successful' > mp/ok

    # Unmount the mountpoint.  Might need to retry this.
    count=10
    while ! fusermount -u mp && [ $count -gt 0 ]; do
        sleep 1
        ((count--))
    done

    exit 0
fi

rm -f test1.img test.errors
rm -rf mp

mkdir mp

if ! ./guestfish -N fs -m /dev/sda1 2>test.errors <<EOF; then
mount-local mp
! $0 --run-test &
mount-local-run

# /ok should have been created and left over by the test.
# If not, then the next command will fail.
cat /ok

EOF
    echo "$0: test failed."
    cat test.errors
    exit 1
fi

rm -f test1.img test.errors
rm -rf mp
