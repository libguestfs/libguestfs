#!/bin/sh -

datadir=/usr/share/man/man8
rm -f test.sqsh
/sbin/mksquashfs $datadir test.sqsh

guestfish -N fs -a test.sqsh <<'EOF'
  mkmountpoint /output
  mkmountpoint /squash
  mount-options "" /dev/sda1 /output
  mount-options "" /dev/sdb /squash
  cp-a /squash /output/man8
  umount /squash
  df-h
  umount /output
EOF

rm test.sqsh
