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

# Test guestfish glob command.

set -e

rm -f test.img test.out

./guestfish > test.out <<EOF

sparse test.img 1G
run

pvcreate /dev/sda
# Because glob doesn't do device name translation, we cannot test
# matching on /dev/sd* paths, only on LVs.  So choose a volume group
# name that cannot possibly be a device name.
vgcreate abc /dev/sda
lvcreate lv1 abc 64
lvcreate lv2 abc 64
lvcreate lv3 abc 64

glob mkfs ext2 /dev/abc/*
mount /dev/abc/lv1 /

mkdir /foo
touch /abc
touch /foo/bar1
touch /foo/bar2

# Regular file globbing.
echo files
glob echo /f*
glob echo /foo/*
glob echo /foo/not*
glob echo /foo/b??1
glob echo /abc

# Device globbing.
echo devices
glob echo /dev/a*
glob echo /dev/a*/*
glob echo /dev/a*/not*
glob echo /dev/a*/lv?
glob echo /dev/a*/lv
glob echo /dev/a*/*3
glob echo /dev/a*/* /dev/a*
glob echo /dev/a*/* /dev/a*/*

echo end
EOF

if [ "$(cat test.out)" != "files
/foo/
/foo/bar1
/foo/bar2
/foo/not*
/foo/bar1
/abc
devices
/dev/a*
/dev/abc/lv1
/dev/abc/lv2
/dev/abc/lv3
/dev/a*/not*
/dev/abc/lv1
/dev/abc/lv2
/dev/abc/lv3
/dev/a*/lv
/dev/abc/lv3
/dev/abc/lv1 /dev/a*
/dev/abc/lv2 /dev/a*
/dev/abc/lv3 /dev/a*
/dev/abc/lv1 /dev/abc/lv1
/dev/abc/lv1 /dev/abc/lv2
/dev/abc/lv1 /dev/abc/lv3
/dev/abc/lv2 /dev/abc/lv1
/dev/abc/lv2 /dev/abc/lv2
/dev/abc/lv2 /dev/abc/lv3
/dev/abc/lv3 /dev/abc/lv1
/dev/abc/lv3 /dev/abc/lv2
/dev/abc/lv3 /dev/abc/lv3
end" ]; then
    echo "$0: error: unexpected output from glob command"
    cat test.out
    exit 1
fi

rm -f test.img test.out
