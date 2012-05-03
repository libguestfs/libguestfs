#!/bin/bash -
# libguestfs
# Copyright (C) 2010-2012 Red Hat Inc.
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

# Engage in some montecarlo testing of virt-make-fs.

export LANG=C
set -e

# Check which filesystems are supported by the appliance.
eval $(
perl -MSys::Guestfs '-MSys::Guestfs::Lib qw(feature_available)' -e '
  $g = Sys::Guestfs->new();
  $g->add_drive ("/dev/null");
  $g->launch ();
  feature_available ($g, "ntfs3g") and print "ntfs3g_available=yes\n";
  feature_available ($g, "ntfsprogs") and print "ntfsprogs_available=yes\n";
  feature_available ($g, "btrfs") and print "btrfs_available=yes\n";
')

declare -a choices

# Return a random element from the array 'choices'.
function random_choice
{
    echo "${choices[$((RANDOM % ${#choices[*]}))]}"
}

# Can't test vfat because we cannot create a tar archive
# where files are owned by UID:GID 0:0.  As a result, tar
# in the appliance fails when trying to change the UID of
# the files to some non-zero value (not supported by FAT).
choices=(--type=ext2 --type=ext3 --type=ext4)
if [ "$ntfs3g_available" = "yes" -a "$ntfsprogs_available" = "yes" ]; then
    choices[${#choices[*]}]="--type=ntfs"
fi
if [ "$btrfs_available" = "yes" ]; then
    choices[${#choices[*]}]="--type=btrfs"
fi
type=`random_choice`

choices=(--format=raw --format=qcow2)
format=`random_choice`

choices=(--partition --partition=gpt)
partition=`random_choice`

choices=("" --size=+1M)
size=`random_choice`

if [ -n "$LIBGUESTFS_DEBUG" ]; then debug=--debug; fi

params="$type $format $partition $size $debug"
echo "test-virt-make-fs: parameters: $params"

rm -f test.file test.tar output.img

tarsize=$((RANDOM & 8191))
echo "test-virt-make-fs: size of test file: $tarsize KB"
dd if=/dev/zero of=test.file bs=1024 count=$tarsize
tar -c -f test.tar test.file
rm test.file

./virt-make-fs $params -- test.tar output.img

rm test.tar output.img
