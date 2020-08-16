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

# Test guestfish -a URI.

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-add-uri.out
rm -f test-add-uri.img

$VG guestfish sparse test-add-uri.img 10M

function fail ()
{
    echo "Test failed.  Actual trace output was:"
    cat test-add-uri.out
    exit 1
}

# file:// URI should be handled exactly like a regular file.
$VG guestfish -x -a file://$abs_builddir/test-add-uri.img </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive ".*/test-add-uri.img"' test-add-uri.out || fail

# curl
$VG guestfish -x -a ftp://user@example.com/disk.img </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "/disk.img" "protocol:ftp" "server:tcp:example.com" "username:user"' test-add-uri.out || fail

# gluster
$VG guestfish -x -a gluster://example.com/disk </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "disk" "protocol:gluster" "server:tcp:example.com"' test-add-uri.out || fail

# NBD
$VG guestfish -x -a nbd://example.com </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "" "protocol:nbd" "server:tcp:example.com"' test-add-uri.out || fail

$VG guestfish -x -a nbd://example.com:3000 </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "" "protocol:nbd" "server:tcp:example.com:3000"' test-add-uri.out || fail

$VG guestfish -x -a 'nbd://?socket=/sk' </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "" "protocol:nbd" "server:unix:/sk"' test-add-uri.out || fail

$VG guestfish -x -a 'nbd:///export?socket=/sk' </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "export" "protocol:nbd" "server:unix:/sk"' test-add-uri.out || fail

# rbd
$VG guestfish -x -a rbd://example.com:6789/pool/disk </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "pool/disk" "protocol:rbd" "server:tcp:example.com:6789"' test-add-uri.out || fail
$VG guestfish -x -a rbd:///pool/disk </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "pool/disk" "protocol:rbd"' test-add-uri.out || fail

# sheepdog
$VG guestfish -x -a sheepdog:///volume/image </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "volume/image" "protocol:sheepdog"' test-add-uri.out || fail

$VG guestfish -x -a sheepdog://example.com:3000/volume/image </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "volume/image" "protocol:sheepdog" "server:tcp:example.com:3000"' test-add-uri.out || fail

# ssh
$VG guestfish -x -a ssh://example.com/disk.img </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "/disk.img" "protocol:ssh" "server:tcp:example.com"' test-add-uri.out || fail

$VG guestfish -x -a ssh://user@example.com/disk.img </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "/disk.img" "protocol:ssh" "server:tcp:example.com" "username:user"' test-add-uri.out || fail

$VG guestfish -x -a ssh://user@example.com:2000/disk.img </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "/disk.img" "protocol:ssh" "server:tcp:example.com:2000" "username:user"' test-add-uri.out || fail

# iSCSI
$VG guestfish -x -a iscsi://example.com/iqn.2015-12.com.libguestfs:test1/0 </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "iqn.2015-12.com.libguestfs:test1/0" "protocol:iscsi" "server:tcp:example.com"' test-add-uri.out || fail

$VG guestfish -x -a iscsi://user:password@example.com/iqn.2015-12.com.libguestfs:test2/0 </dev/null >test-add-uri.out 2>&1
grep -sq 'add_drive "iqn.2015-12.com.libguestfs:test2/0" "protocol:iscsi" "server:tcp:example.com" "username:user" "secret:password"' test-add-uri.out || fail

rm test-add-uri.out
rm test-add-uri.img
