#!/bin/bash -

export LANG=C
set -e

# Run virt-list-filesystems.
# Only columns 1 & 2 are guaranteed, we may add more in future.
if [ "$(./virt-list-filesystems -l ../tests/guests/fedora.img |
        sort | awk '{print $1 $2}')" \
    != \
"/dev/VG/LV1ext2
/dev/VG/LV2ext2
/dev/VG/LV3ext2
/dev/VG/Rootext2
/dev/sda1ext2" ]; then
    echo "$0: error: unexpected output from virt-list-filesystems"
    exit 1
fi
