#!/bin/sh -

guestfish <<EOF
alloc test.img 130M
run
# You can uncomment the following to see the
# geometry (CHS), which is needed to repartition.
#sfdisk-disk-geometry /dev/sda
sfdisk /dev/sda 0 0 0 ,
pvcreate /dev/sda1
vgcreate VG /dev/sda1
lvcreate LV1 VG 32M
lvcreate LV2 VG 32M
lvcreate LV3 VG 32M
sync
EOF

truncate --size=260M test.img

guestfish -a test.img <<EOF
run
# Turn off the VGs before we can repartition.
vg-activate-all false
sfdisk-N /dev/sda 1 32 255 63 0,31
vg-activate-all true

pvresize /dev/sda1

# The following command would fail if the
# partition or PV hadn't been resized:
lvcreate LV4 VG 64M

echo New LV list:
lvs
EOF