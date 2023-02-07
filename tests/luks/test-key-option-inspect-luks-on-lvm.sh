#!/bin/bash -
# libguestfs
# Copyright (C) 2019-2023 Red Hat Inc.
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
skip_unless_phony_guest fedora-luks-on-lvm.img

# Start a background guestfish instance to check key specification by Logical
# Volume names.
guestfish=(guestfish --listen --ro --inspector
           --add ../test-data/phony-guests/fedora-luks-on-lvm.img)
keys_by_lvname=(--key /dev/VG/Root:key:FEDORA-Root
                --key /dev/VG/LV1:key:FEDORA-LV1
                --key /dev/VG/LV2:key:FEDORA-LV2
                --key /dev/VG/LV3:key:FEDORA-LV3)

# The variable assignment below will fail, and abort the script, if guestfish
# refuses to start up.
fish_ref=$("${guestfish[@]}" "${keys_by_lvname[@]}")

# Set GUESTFISH_PID as necessary for the remote access.
eval "$fish_ref"

# From this point on, if any remote guestfish command fails, that will cause
# *both* the guestfish server *and* this script to exit, with an error.
# However, we also want the background guestfish process to exit if (a) this
# script exits cleanly, or (b) this script exits with a failure due to a reason
# that's different from a failed remote command.
function cleanup_guestfish
{
  if [ -n "$GUESTFISH_PID" ]; then
    guestfish --remote -- exit >/dev/null 2>&1 || :
  fi
}
trap cleanup_guestfish EXIT

# Get the UUIDs of the LUKS devices.
uuid_root=$(guestfish --remote -- luks-uuid /dev/VG/Root)
uuid_lv1=$( guestfish --remote -- luks-uuid /dev/VG/LV1)
uuid_lv2=$( guestfish --remote -- luks-uuid /dev/VG/LV2)
uuid_lv3=$( guestfish --remote -- luks-uuid /dev/VG/LV3)

# The actual test.
function check_filesystems
{
  local decrypted_root decrypted_lv1 decrypted_lv2 decrypted_lv3 exists

  # Get the names of the decrypted LUKS block devices that host the filesystems
  # with the labels listed below.
  decrypted_root=$(guestfish --remote -- findfs-label ROOT)
  decrypted_lv1=$( guestfish --remote -- findfs-label LV1)
  decrypted_lv2=$( guestfish --remote -- findfs-label LV2)
  decrypted_lv3=$( guestfish --remote -- findfs-label LV3)

  # Verify the device names. These come from decrypt_mountables() in
  # "common/options/decrypt.c".
  test /dev/mapper/luks-"$uuid_root" = "$decrypted_root"
  test /dev/mapper/luks-"$uuid_lv1"  = "$decrypted_lv1"
  test /dev/mapper/luks-"$uuid_lv2"  = "$decrypted_lv2"
  test /dev/mapper/luks-"$uuid_lv3"  = "$decrypted_lv3"

  # Check "/etc/fedora-release" on the root fs.
  exists=$(guestfish --remote -- exists /etc/fedora-release)
  test true = "$exists"
}
check_filesystems

# Exit the current guestfish background process.
guestfish --remote -- exit
GUESTFISH_PID=

# Start up a similar guestfish background process, but specify the keys by
# UUID.
keys_by_uuid=(--key "$uuid_root":key:FEDORA-Root
              --key "$uuid_lv1":key:FEDORA-LV1
              --key "$uuid_lv2":key:FEDORA-LV2
              --key "$uuid_lv3":key:FEDORA-LV3)
fish_ref=$("${guestfish[@]}" "${keys_by_uuid[@]}")
eval "$fish_ref"

# Repeat the test.
check_filesystems
