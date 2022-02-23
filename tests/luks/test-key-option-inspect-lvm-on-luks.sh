#!/bin/bash -
# libguestfs
# Copyright (C) 2019 Red Hat Inc.
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

# Test the --key option.  It is handled by common code so we only need
# to test one tool (guestfish).

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available luks
skip_unless_phony_guest fedora-lvm-on-luks.img

disk=../test-data/phony-guests/fedora-lvm-on-luks.img
device=/dev/sda2

# Get the UUID of the LUKS device.
uuid="$(guestfish --ro -a $disk run : luks-uuid $device)"

# Try to decrypt the disk in different ways:
# - pass a wrong key via stdin to check the --key value is actually used only
# - check for /etc/fedora-release as a way to know the LUKS device was
#   decrypted correctly

# Specify the libguestfs device name of the LUKS device.
echo wrongkey | guestfish --ro -a $disk -i --keys-from-stdin \
          --key "$device:key:FEDORA" \
          exists /etc/fedora-release

# Specify the UUID of the LUKS device.
echo wrongkey | guestfish --ro -a $disk -i --keys-from-stdin \
          --key "$uuid:key:FEDORA" \
          exists /etc/fedora-release
