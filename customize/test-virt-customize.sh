#!/bin/bash -
# libguestfs virt-customize test script
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

# virt-customize with the -n option doesn't modify the guest.  It ought
# to be able to customize any of our Linux-like test guests.

for f in ../test-data/phony-guests/{debian,fedora,ubuntu}.img; do
    # Ignore zero-sized windows.img if ntfs-3g is not installed.
    if [ -s "$f" ]; then
        # Add --no-network so UML works.
	$VG virt-customize -n --format raw -a $f \
            --no-network \
            --write /etc/motd:HELLO \
            --chmod 0600:/etc/motd \
            --delete /etc/motd
    fi
done
