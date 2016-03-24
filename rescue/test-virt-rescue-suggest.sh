#!/bin/bash -
# test virt-rescue --suggest
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

export LANG=C
set -e

guest=../test-data/phony-guests/fedora.img

if [ ! -s "$guest" ]; then
    echo "$0: test skipped because $guest does not exist or is an empty file"
    exit 77
fi

rm -f virt-rescue-suggest.out

$VG virt-rescue --suggest --format=raw -a "$guest" |
  grep '^mount ' |
  sed -r 's,/dev/[abce-ln-z]+d,/dev/sd,' > virt-rescue-suggest.out

if [ "$(cat virt-rescue-suggest.out)" != "mount /dev/VG/Root /sysroot/
mount /dev/sda1 /sysroot/boot
mount --rbind /dev /sysroot/dev
mount --rbind /proc /sysroot/proc
mount --rbind /sys /sysroot/sys" ]; then
    echo "$0: unexpected output from virt-rescue --suggest command:"
    cat virt-rescue-suggest.out
    exit 1
fi

rm virt-rescue-suggest.out
