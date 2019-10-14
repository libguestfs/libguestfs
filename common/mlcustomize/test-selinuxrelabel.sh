#!/bin/bash -
# Test SELinux relabel functionality.
# Copyright (C) 2018 Red Hat Inc.
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

# This slow test checks that SELinux relabel works.

set -e

$TEST_FUNCTIONS
slow_test

guestname="fedora-27"

disk="selinuxrelabel.img"
disk_overlay="selinuxrelabel-overlay.qcow2"
rm -f "$disk"

skip_unless_virt_builder_guest "$guestname"

# Build a guest (using virt-builder).
virt-builder "$guestname" --quiet -o "$disk"

# Test #1: relabel with the default configuration works.
rm -f  "$disk_overlay"
guestfish -- disk-create "$disk_overlay" qcow2 -1 backingfile:"$disk"
virt-customize -a "$disk" --selinux-relabel

# Test #2: relabel with no SELINUXTYPE in the configuration.
rm -f  "$disk_overlay"
guestfish -- disk-create "$disk_overlay" qcow2 -1 backingfile:"$disk"
virt-customize -a "$disk" \
  --edit /etc/selinux/config:"s,^SELINUXTYPE=,#&,g" \
  --selinux-relabel

rm "$disk" "$disk_overlay"
