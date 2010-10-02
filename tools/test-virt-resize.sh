#!/bin/bash -

# virt-resize does not work on 32 bit because of limitations in Perl
# so short-circuit this test on a 32 bit host.
perl -e 'exit 1 if ~1 == 4294967294' || {
    echo "$0: Skipping this test on 32 bit."
    exit 0
}

export LANG=C
set -e

# Test expanding.
#
# This exercises a number of interesting codepaths including resizing
# LV content, handling GPT, and using qcow2 as a target.

../fish/guestfish -N bootrootlv:/dev/VG/LV:ext2:ext4:400M:32M:gpt </dev/null

qemu-img create -f qcow2 test2.img 500M
./virt-resize -d --expand /dev/sda2 --lv-expand /dev/VG/LV test1.img test2.img

# Test shrinking in a semi-realistic scenario.  Although the disk
# image created above contains no data, we will nevertheless use
# similar operations to ones that might be used by a real admin.

../fish/guestfish -a test1.img <<EOF
run
resize2fs-size /dev/VG/LV 190M
lvresize /dev/VG/LV 190
pvresize-size /dev/sda2 200M
fsck ext4 /dev/VG/LV
EOF

rm -f test2.img; truncate -s 300M test2.img
./virt-resize -d --shrink /dev/sda2 test1.img test2.img

rm -f test1.img test2.img
