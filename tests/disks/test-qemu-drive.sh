#!/bin/bash
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

# Test that disks map to the correct qemu -drive parameter.

set -e

$TEST_FUNCTIONS
skip_if_skipped

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_HV="$abs_srcdir/disks/debug-qemu.sh"
export DEBUG_QEMU_FILE="$abs_builddir/test-qemu-drive.out"

function check_output ()
{
    if [ ! -f "$DEBUG_QEMU_FILE" ]; then
        echo "$0: guestfish command failed, see previous error messages"
        exit 1
    fi
}

function fail ()
{
    echo "$0: Test failed.  Command line output was:"
    cat "$DEBUG_QEMU_FILE"
    exit 1
}

rm -f "$DEBUG_QEMU_FILE"

# Ceph (RBD).

guestfish <<EOF ||:
  add "abc-def/ghi-jkl" "format:raw" "protocol:rbd" \
    "server:1.2.3.4:1234 1.2.3.5:1235 1.2.3.6:1236"
  run
EOF
check_output
grep -sq -- '-drive file=rbd:abc-def/ghi-jkl:mon_host=1.2.3.4\\:1234\\;1.2.3.5\\:1235\\;1.2.3.6\\:1236:auth_supported=none,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

guestfish <<EOF ||:
  add "abc-def/ghi-jkl" "format:raw" "protocol:rbd"
  run
EOF
check_output
grep -sq -- '-drive file=rbd:abc-def/ghi-jkl:auth_supported=none,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# HTTP.

guestfish <<EOF ||:
  add "/disk.img" "format:raw" "protocol:http" "server:www.example.com"
  run
EOF
check_output
grep -sq -- '-drive file=http://www.example.com/disk.img,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# Gluster.

guestfish <<EOF ||:
  add "volname/image" "format:raw" "protocol:gluster" "server:www.example.com:24007"
  run
EOF
check_output
grep -sq -- '-drive file=gluster://www.example.com:24007/volname/image,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# iSCSI.

guestfish <<EOF ||:
  add "target-iqn-name/lun" "format:raw" "protocol:iscsi" "server:www.example.com:3000"
  run
EOF
check_output
grep -sq -- '-drive file=iscsi://www.example.com:3000/target-iqn-name/lun,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

guestfish <<EOF ||:
  add "target-iqn-name/lun" "format:raw" "protocol:iscsi" "server:www.example.com:3000" \
    "username:user" "secret:pass"
  run
EOF
check_output
grep -sq -- '-drive file=iscsi://user%pass@www.example.com:3000/target-iqn-name/lun,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# NBD.

guestfish <<EOF ||:
  add "" "format:raw" "protocol:nbd" "server:1.2.3.4:1234"
  run
EOF
check_output
grep -sq -- '-drive file=nbd:1.2.3.4:1234,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

guestfish <<EOF ||:
  add "" "format:raw" "protocol:nbd" "server:unix:/socket"
  run
EOF
check_output
grep -sq -- '-drive file=nbd:unix:/socket,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# Sheepdog.

guestfish <<EOF ||:
  add "volume" "format:raw" "protocol:sheepdog"
  run
EOF
check_output
grep -sq -- '-drive file=sheepdog:volume,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"

# SSH.

guestfish <<EOF ||:
  add "/disk.img" "format:raw" "protocol:ssh" "server:example.com" \
    "username:rich"
  run
EOF
check_output
grep -sq -- '-drive file=ssh://rich@example.com/disk.img,' "$DEBUG_QEMU_FILE" || fail
rm "$DEBUG_QEMU_FILE"
