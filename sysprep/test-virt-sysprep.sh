#!/bin/bash -
# libguestfs virt-sysprep test script
# Copyright (C) 2011-2012 Red Hat Inc.
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

export LANG=C
set -e

if [ ! -w /dev/fuse ]; then
    echo "$0: SKIPPING test, because there is no /dev/fuse."
    exit 0
fi

# virt-sysprep with the -n option doesn't modify the guest.  It ought
# to be able to sysprep any of our test guests.

for f in ../tests/guests/{debian,fedora,ubuntu,windows}.img; do
    ./virt-sysprep -q -n -a $f
done
