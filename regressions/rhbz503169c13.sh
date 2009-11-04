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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=503169#c13
#
# The unmount-all command will give this error:
# libguestfs: error: umount: /sysroot/dev: umount: /sysroot/dev: device is busy.
#         (In some cases useful info about processes that use
#          the device is found by lsof(8) or fuser(1))

set -e

rm -f test1.img
dd if=/dev/zero of=test1.img bs=1024k count=10

../fish/guestfish -a test1.img <<EOF
run
part-disk /dev/sda mbr
mkfs ext2 /dev/sda1
mount /dev/sda1 /
mkdir /dev
-command /ignore-this-error
unmount-all
EOF

rm test1.img
