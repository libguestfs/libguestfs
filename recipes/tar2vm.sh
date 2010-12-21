#!/bin/sh -

guestfish <<EOF
  alloc $2 $3
  run
  part-disk /dev/sda mbr
  mkfs ext3 /dev/sda1
  mount /dev/sda1 /
  tgz-in $1 /
  umount-all
EOF
