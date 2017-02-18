#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

# Test the ntfsclone-in/-out commands.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available ntfs3g
skip_unless_phony_guest windows.img

rm -f test-ntfsclone.img ntfsclone-backup1 ntfsclone-backup2

# Export the filesystems to the backup file.
guestfish \
    --ro --format=raw -a $top_builddir/test-data/phony-guests/windows.img <<EOF
run
ntfsclone-out /dev/sda1 ntfsclone-backup1 preservetimestamps:true force:true
ntfsclone-out /dev/sda2 ntfsclone-backup2 metadataonly:true ignorefscheck:true
EOF

# Restore to another disk image.
output=$(guestfish -N test-ntfsclone.img=part:300M <<EOF
ntfsclone-in ntfsclone-backup1 /dev/sda1
vfs-type /dev/sda1
EOF
)

if [ "$output" != "ntfs" ]; then
    echo "$0: unexpected filesystem type after restore: $output"
    exit 1
fi

#ls -lh ntfsclone-backup[12]

rm test-ntfsclone.img ntfsclone-backup1 ntfsclone-backup2
