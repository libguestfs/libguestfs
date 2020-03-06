#!/bin/bash -
# libguestfs virt-sparsify --in-place test script
# Copyright (C) 2011-2020 Red Hat Inc.
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

# Test that we do the right thing for filesystems where the fstrim
# operation is not supported.
#
# https://bugzilla.redhat.com/show_bug.cgi?id=1364347
#
# This test assumes that the kernel minix driver does not support
# fstrim.  It might become supported in a future kernel version in
# which case we could use a different filesystem for this test, or
# delete the test if we are confident that all common filesystems are
# supported.

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped
# UML does not support discard.
skip_if_backend uml
skip_unless_filesystem_available minix

img=test-virt-sparsify-in-place-fstrim-unsupported.img
log=test-virt-sparsify-in-place-fstrim-unsupported.log
rm -f $img $log

# Create a test filesystem with a single minix filesystem.
guestfish -N $img=fs:minix exit

# This should warn.
virt-sparsify --in-place $img |& tee $log

# Check the warning was emitted.
grep "warning:.*fstrim" $log

# This should ignore the filesystem and not warn.
virt-sparsify --in-place --ignore /dev/sda1 $img |& tee $log

if grep "warning:.*fstrim.*not supported" $log; then
    echo "$0: filesystem /dev/sda1 was not ignored"
    exit 1
fi

# Create a test filesystem with minix and ext4 filesystems.
guestfish -N $img=bootroot:minix:ext4 exit

# This should warn.
virt-sparsify --in-place $img |& tee $log

# Check the warning was emitted.
grep "warning:.*fstrim" $log

# This should ignore the filesystem and not warn.
virt-sparsify --in-place --ignore /dev/sda1 $img |& tee $log

if grep "warning:.*fstrim.*not supported" $log; then
    echo "$0: filesystem /dev/sda1 was not ignored"
    exit 1
fi

rm $img $log
