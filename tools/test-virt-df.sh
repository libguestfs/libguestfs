#!/bin/bash -

export LANG=C
set -e

# Run virt-df.
output=$(./virt-df test.img -h)

# The output will be slightly different from one machine to another.
# So just do some tests to make sure it looks reasonable.

# Check title is the first line.
if [[ ! $output =~ ^Filesystem[[:space:]]+Size[[:space:]]+Used[[:space:]]+Available[[:space:]]+Use% ]]; then
    echo "$0: error: no title line"
    exit 1
fi

# Check 6 lines (title line + 5 * filesystems).
if [ $(echo "$output" | wc -l) -ne 6 ]; then
    echo "$0: error: not all filesystems were found"
    exit 1
fi

# Check /dev/VG/LV[1-3] and /dev/VG/Root were found.
if [[ ! $output =~ test.img:/dev/VG/LV1 ]]; then
    echo "$0: error: filesystem /dev/VG/LV1 was not found"
    exit 1
fi
if [[ ! $output =~ test.img:/dev/VG/LV2 ]]; then
    echo "$0: error: filesystem /dev/VG/LV2 was not found"
    exit 1
fi
if [[ ! $output =~ test.img:/dev/VG/LV3 ]]; then
    echo "$0: error: filesystem /dev/VG/LV3 was not found"
    exit 1
fi
if [[ ! $output =~ test.img:/dev/VG/Root ]]; then
    echo "$0: error: filesystem /dev/VG/Root was not found"
    exit 1
fi

# Check /dev/sda1 was found.  Might be called /dev/vda1.
if [[ ! $output =~ test.img:/dev/[hsv]da1 ]]; then
    echo "$0: error: filesystem /dev/VG/sda1 was not found"
    exit 1
fi
