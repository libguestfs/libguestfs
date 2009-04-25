#!/bin/sh -

guestfish <<EOF
alloc $2 $3
run
sfdisk /dev/sda 0 0 0 ,
mkfs ext3 /dev/sda1
mount /dev/sda1 /
tgz-in $1 /
umount-all
EOF
