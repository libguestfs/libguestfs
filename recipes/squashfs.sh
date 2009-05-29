#!/bin/sh -

datadir=/usr/share/man/man8
/sbin/mksquashfs $datadir test.sqsh

guestfish <<EOF
alloc test.img 10M
add test.sqsh
run
mount /dev/sdb /
ll /
EOF
