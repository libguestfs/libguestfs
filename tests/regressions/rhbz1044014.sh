#!/bin/bash -
# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=1044014

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_backend libvirt
skip_unless_libvirt_minimum_version 1 2 1

# Set the backend to the test driver.
export LIBGUESTFS_BACKEND="libvirt:test://$abs_srcdir/regressions/rhbz1044014.xml"

dir=$srcdir/regressions
rm -f $dir/rhbz1044014.out

guestfish -- -run < $dir/rhbz1044014.in > $dir/rhbz1044014.out 2>&1 || {
    r=$?
    if [ $r -ne 0 ]; then
        cat $dir/rhbz1044014.out
        exit $r
    fi
}

# We are expecting this message to be printed (see commit which fixed
# RHBZ#1044014).
grep "libvirt needs authentication to connect to libvirt URI" $dir/rhbz1044014.out || {
    echo "$0: expecting to see message from commit which fixed RHBZ#1044014"
    echo
    echo "actual output was:"
    echo
    cat $dir/rhbz1044014.out
    exit 1
}

# This is the error we are expecting to see.  If we see it then it
# indicates that authentication was successful.
grep "error: libvirt hypervisor doesn’t support qemu or KVM" $dir/rhbz1044014.out || {
    echo "$0: unexpected output:"
    echo
    cat $dir/rhbz1044014.out
    exit 1
}

rm $dir/rhbz1044014.out
