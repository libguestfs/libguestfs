#!/bin/bash -

export LANG=C
set -e

# Run virt-df.
output=$(./virt-df ../tests/guests/fedora.img)

# Check title is the first line.
if [[ ! $output =~ ^Filesystem.* ]]; then
    echo "$0: error: no title line"
    exit 1
fi

# Check 6 lines (title line + 5 * filesystems).
if [ $(echo "$output" | wc -l) -ne 6 ]; then
    echo "$0: error: not all filesystems were found"
    exit 1
fi

# Check /dev/VG/LV[1-3] and /dev/VG/Root were found.
if [[ ! $output =~ fedora.img:/dev/VG/LV1 ]]; then
    echo "$0: error: filesystem /dev/VG/LV1 was not found"
    exit 1
fi
if [[ ! $output =~ fedora.img:/dev/VG/LV2 ]]; then
    echo "$0: error: filesystem /dev/VG/LV2 was not found"
    exit 1
fi
if [[ ! $output =~ fedora.img:/dev/VG/LV3 ]]; then
    echo "$0: error: filesystem /dev/VG/LV3 was not found"
    exit 1
fi
if [[ ! $output =~ fedora.img:/dev/VG/Root ]]; then
    echo "$0: error: filesystem /dev/VG/Root was not found"
    exit 1
fi

# Check /dev/sda1 was found.  Might be called /dev/vda1.
if [[ ! $output =~ fedora.img:/dev/[hsv]da1 ]]; then
    echo "$0: error: filesystem /dev/VG/sda1 was not found"
    exit 1
fi

# This is what df itself prints for these filesystems (determined
# by running the test image under virt-rescue):
#
# ><rescue> df -h
# Filesystem            Size  Used Avail Use% Mounted on
# /dev/dm-1              31M   28K   30M   1% /sysroot/lv1
# /dev/dm-2              31M  395K   29M   2% /sysroot/lv2
# /dev/dm-3              62M  144K   59M   1% /sysroot/lv3
# ><rescue> df -i
# Filesystem            Inodes   IUsed   IFree IUse% Mounted on
# /dev/dm-1               8192      11    8181    1% /sysroot/lv1
# /dev/dm-2               8192      11    8181    1% /sysroot/lv2
# /dev/dm-3              16384      11   16373    1% /sysroot/lv3
# ><rescue> df
# Filesystem           1K-blocks      Used Available Use% Mounted on
# /dev/dm-1                31728        28     30064   1% /sysroot/lv1
# /dev/dm-2                31729       395     29696   2% /sysroot/lv2
# /dev/dm-3                63472       144     60052   1% /sysroot/lv3
#
# This test is disabled (XXX).  See:
# https://www.redhat.com/archives/libguestfs/2011-November/msg00051.html

#if [ "$(echo "$output" | sort | awk '/VG.LV[123]/ { print $2 " " $3 " " $4 " " $5 }')" != \
#"31728 28 30064 1%
#31729 395 29696 2%
#63472 144 60052 1%" ]; then
#    echo "$0: error: output of virt-df did not match expected (df) output"
#    echo "$output"
#    exit 1
#fi
