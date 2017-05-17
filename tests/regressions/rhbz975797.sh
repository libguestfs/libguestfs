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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=975797
# Ensure the appliance doesn't hang when using the 'iface' parameter.

set -e

$TEST_FUNCTIONS
skip_if_skipped
# These architectures don't support the 'ide' interface.
skip_if_arch arm
skip_if_arch aarch64
skip_if_arch ppc64
skip_if_arch ppc64le
skip_if_arch s390x
skip_if_backend libvirt
# UML doesn't support the 'iface' parameter.
skip_if_backend uml

rm -f rhbz975797-*.img

timeout="timeout 600"

# Use real disk images here since the code for adding /dev/null may
# take shortcuts.
guestfish sparse rhbz975797-1.img 1G
guestfish sparse rhbz975797-2.img 1G
guestfish sparse rhbz975797-3.img 1G

$timeout guestfish <<EOF
add-drive rhbz975797-1.img iface:virtio format:raw
add-drive rhbz975797-2.img iface:ide format:raw
add-drive rhbz975797-3.img format:raw
run
EOF

rm rhbz975797-*.img
