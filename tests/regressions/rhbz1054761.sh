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
# https://bugzilla.redhat.com/show_bug.cgi?id=1054761
# Handle broken/missing PVs gracefully.

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ1054761_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

rm -f rhbz1054761-[ab].img

guestfish -N rhbz1054761-a.img=disk -N rhbz1054761-b.img=disk <<EOF
pvcreate /dev/sda
pvcreate /dev/sdb
vgcreate VG "/dev/sda /dev/sdb"
EOF

output="$(
    guestfish --format=raw -a rhbz1054761-a.img run : pvs |
        sed -r 's,^/dev/[abce-ln-z]+d,/dev/sd,'
)"
if [ "$output" != "/dev/sda" ]; then
    echo "$0: unexpected output from test:"
    echo "$output"
    exit 1
fi

rm rhbz1054761-[ab].img
