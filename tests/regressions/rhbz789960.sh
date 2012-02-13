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

# https://bugzilla.redhat.com/show_bug.cgi?id=789960
# Test the mount command error paths.

set -e
export LANG=C

rm -f test.out

../../fish/guestfish -a ../guests/fedora.img --ro > test.out <<EOF
run

# Not a device at all, should fail.
-mount /foo /

# Not a block device.
-mount /dev/null /

# Should fail even though the device exists.
-mount /dev/sda /

# In some configurations, this is the febootstrap appliance.  This
# should fail.
-mount /dev/vdb /

# Check device name translation.  These are all expected to fail.
-mount /dev/vda /
-mount /dev/hda /

# Not a mount point.
-mount /dev/sda1 /foo

# Nothing should be mounted here.
mountpoints

# This should succeed.
mount /dev/sda1 /

# Daemon should be up.
ping-daemon
echo done

EOF

if [ "$(cat test.out)" != "done" ]; then
    echo "$0: unexpected output:"
    cat test.out
    exit 1
fi

rm -f test.out
