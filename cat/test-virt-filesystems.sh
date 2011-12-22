#!/bin/bash -

export LANG=C
set -e

output="$(./virt-filesystems -a ../tests/guests/fedora.img | sort)"
expected="/dev/VG/LV1
/dev/VG/LV2
/dev/VG/LV3
/dev/VG/Root
/dev/sda1"

if [ "$output" != "$expected" ]; then
    echo "$0: error: mismatch in test 1"
    echo "$output"
    exit 1
fi

output="$(./virt-filesystems -a ../tests/guests/fedora.img --all --long --uuid -h --no-title | awk '{print $1}' | sort -u)"
expected="/dev/VG
/dev/VG/LV1
/dev/VG/LV2
/dev/VG/LV3
/dev/VG/Root
/dev/sda
/dev/sda1
/dev/sda2"

if [ "$output" != "$expected" ]; then
    echo "$0: error: mismatch in test 2"
    echo "$output"
    exit 1
fi
