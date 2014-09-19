#!/bin/bash -
# libguestfs
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f backing*
rm -f overlay*
rm -f link*
rm -rf dir1

# Set up a set of disk images involving relative paths.
mkdir -p dir1/dir2

# Regular overlay files.

qemu-img create -f qcow2 backing1 10M
qemu-img create -f qcow2 -b $(pwd)/backing1 -F qcow2 overlay1

qemu-img create -f qcow2 backing2 10M
qemu-img create -f qcow2 -b backing2 -F qcow2 overlay2

qemu-img create -f qcow2 backing3 10M
qemu-img create -f qcow2 -b ./backing3 -F qcow2 overlay3

qemu-img create -f qcow2 backing4 10M
qemu-img create -f qcow2 -b ../tests/backing4 -F qcow2 overlay4

qemu-img create -f qcow2 backing5 10M
pushd dir1
qemu-img create -f qcow2 -b ../backing5 -F qcow2 overlay5
popd

qemu-img create -f qcow2 backing6 10M
pushd dir1/dir2
qemu-img create -f qcow2 -b ../../backing6 -F qcow2 overlay6
popd

qemu-img create -f qcow2 dir1/backing7 10M
qemu-img create -f qcow2 -b dir1/backing7 -F qcow2 overlay7

qemu-img create -f qcow2 dir1/dir2/backing8 10M
qemu-img create -f qcow2 -b dir1/dir2/backing8 -F qcow2 overlay8

qemu-img create -f qcow2 dir1/dir2/backing9 10M
pushd dir1
qemu-img create -f qcow2 -b dir2/backing9 -F qcow2 overlay9
popd

qemu-img create -f qcow2 dir1/backing10 10M
pushd dir1/dir2
qemu-img create -f qcow2 -b ../backing10 -F qcow2 overlay10
popd

qemu-img create -f qcow2 dir1/backing11 10M
pushd dir1
qemu-img create -f qcow2 -b backing11 -F qcow2 overlay11
popd

# Symbolic links.

qemu-img create -f qcow2 backing12 10M
qemu-img create -f qcow2 -b backing12 -F qcow2 overlay12
ln -s overlay12 link12

qemu-img create -f qcow2 dir1/backing13 10M
pushd dir1
qemu-img create -f qcow2 -b backing13 -F qcow2 overlay13
popd
ln -s dir1/overlay13 link13

qemu-img create -f qcow2 dir1/dir2/backing14 10M
pushd dir1
qemu-img create -f qcow2 -b dir2/backing14 -F qcow2 overlay14
popd
pushd dir1/dir2
ln -s ../overlay14 link14
popd

qemu-img create -f qcow2 dir1/backing15 10M
pushd dir1/dir2
qemu-img create -f qcow2 -b ../backing15 -F qcow2 overlay15
popd
pushd dir1
ln -s dir2/overlay15 link15
popd

# Note that add-drive readonly/readwrite are substantially different
# codepaths in most backends, so we should test each separately.
for ro in readonly:true readonly:false; do
    for prefix in "./" "" "$(pwd)/"; do
        $VG guestfish <<EOF
            add-drive ${prefix}overlay1            $ro format:qcow2
            add-drive ${prefix}overlay2            $ro format:qcow2
            add-drive ${prefix}overlay3            $ro format:qcow2
            add-drive ${prefix}overlay4            $ro format:qcow2
            add-drive ${prefix}dir1/overlay5       $ro format:qcow2
            add-drive ${prefix}dir1/dir2/overlay6  $ro format:qcow2
            add-drive ${prefix}overlay7            $ro format:qcow2
            add-drive ${prefix}overlay8            $ro format:qcow2
            add-drive ${prefix}dir1/overlay9       $ro format:qcow2
            add-drive ${prefix}dir1/dir2/overlay10 $ro format:qcow2
            add-drive ${prefix}dir1/overlay11      $ro format:qcow2
            add-drive ${prefix}link12              $ro format:qcow2
            add-drive ${prefix}link13              $ro format:qcow2
            add-drive ${prefix}dir1/dir2/link14    $ro format:qcow2
            add-drive ${prefix}dir1/link15         $ro format:qcow2
            run
            # Just forces the drives to be opened.
            <! for n in a b c d e f g h i j k l m n o; do echo blockdev-getsize64 /dev/sd\$n; done
EOF
    done
done

rm -r dir1
rm backing*
rm overlay*
rm link*
