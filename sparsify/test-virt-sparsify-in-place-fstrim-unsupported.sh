#!/bin/bash -
# libguestfs virt-sparsify --in-place test script
# Copyright (C) 2011-2016 Red Hat Inc.
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
# This test assumes that the kernel vfat driver does not support
# fstrim.  It might become supported in a future kernel version in
# which case we could use a different filesystem for this test, or
# delete the test if we are confident that all common filesystems are
# supported.
#
# The reason why vfat is significant is because UEFI guests use it.

export LANG=C
set -e
set -x

if [ -n "$SKIP_TEST_VIRT_SPARSIFY_IN_PLACE_FSTRIM_UNSUPPORTED_SH" ]; then
    echo "$0: skipping test (environment variable set)"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support discard"
    exit 77
fi

img=test-virt-sparsify-in-place-fstrim-unsupported.img
log=test-virt-sparsify-in-place-fstrim-unsupported.log
rm -f $img $log

# Create a test filesystem with a single vfat filesystem.
guestfish -N $img=fs:vfat exit

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

# Create a test filesystem with vfat and ext4 filesystems.
guestfish -N $img=bootroot:vfat:ext4 exit

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
