#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# https://bugzilla.redhat.com/show_bug.cgi?id=690819
# mkfs fails creating a filesytem on a disk device when using a disk
# with 'ide' interface

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

rm -f rhbz690819.img

guestfish sparse rhbz690819.img 100M

guestfish <<EOF
add rhbz690819.img iface:ide format:raw
run
mkfs ext3 /dev/sda
mount /dev/sda /
EOF

rm rhbz690819.img
