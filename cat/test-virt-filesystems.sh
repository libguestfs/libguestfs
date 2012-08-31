#!/bin/bash -
# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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

output="$(./virt-filesystems -a ../tests/guests/fedora.img | sort)"
expected="/dev/VG/LV1
/dev/VG/LV2
/dev/VG/LV3
/dev/VG/Root
/dev/sda1"

if [ "$output" != "$expected" ]; then
    echo "$0: error: mismatch in test 1"
    echo "$output"
    exit 1
fi

output="$(./virt-filesystems -a ../tests/guests/fedora.img --all --long --uuid -h --no-title | awk '{print $1}' | sort -u)"
expected="/dev/VG
/dev/VG/LV1
/dev/VG/LV2
/dev/VG/LV3
/dev/VG/Root
/dev/sda
/dev/sda1
/dev/sda2"

if [ "$output" != "$expected" ]; then
    echo "$0: error: mismatch in test 2"
    echo "$output"
    exit 1
fi
