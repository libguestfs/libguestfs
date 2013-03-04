#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

# https://bugzilla.redhat.com/show_bug.cgi?id=916780
# Test that guestunmount returns the correct error code if
# there is no mounted FUSE filesystem.

unset CDPATH
#set -e
#set -v

if [ -n "$SKIP_TEST_GUESTUNMOUNT_NOT_MOUNTED_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

if [ ! -w /dev/fuse ]; then
    echo "SKIPPING guestunmount test, because there is no /dev/fuse."
    exit 77
fi

# Not expecting cwd to be a FUSE mountpoint.
./guestunmount --quiet $(pwd)
r=$?
case $r in
    0)
        echo "$0: failed: guestunmount should return exit code 2" ;;
    1)
        echo "$0: failed: guestunmount failed to run, see errors above" ;;
    2)
        # OK
        ;;
    *)
        echo "$0: failed: guestunmount returned unknown error code $r" ;;
esac
