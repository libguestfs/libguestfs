#!/bin/bash -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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

# Test remote control of guestfish.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-remote.img

eval `guestfish --listen`

$VG guestfish --remote alloc test-remote.img 10M
$VG guestfish --remote run
$VG guestfish --remote part-disk /dev/sda mbr
$VG guestfish --remote mkfs ext2 /dev/sda1
$VG guestfish --remote mount /dev/sda1 /

# Failure of the above commands will cause the guestfish listener to exit.
# Incorrect return from echo_daemon will not, so need to ensure the listener
# exits in any case, while still reporting an error.
error=0
echo=$($VG guestfish --remote echo_daemon "This is a test")
if [ "$echo" != "This is a test" ]; then
    error=1;
fi

$VG guestfish --remote exit

rm test-remote.img

exit $error
