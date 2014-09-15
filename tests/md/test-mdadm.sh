#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Test guestfish md-create and md-detail commands.

set -e

if [ -n "$SKIP_TEST_MDADM_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

rm -f mdadm-{1,2,3,4}.img

guestfish <<EOF
# Add four empty disks
sparse mdadm-1.img 100M
sparse mdadm-2.img 100M
sparse mdadm-3.img 100M
sparse mdadm-4.img 100M
run

# Create lots of test partitions.
part-init /dev/sda mbr
part-add /dev/sda p 4096 8191
part-add /dev/sda p 8192 12287
part-add /dev/sda p 12288 16383
part-add /dev/sda p 16384 20479
part-init /dev/sdb mbr
part-add /dev/sdb p 4096 8191
part-add /dev/sdb p 8192 12287
part-add /dev/sdb p 12288 16383
part-add /dev/sdb p 16384 20479
part-init /dev/sdc mbr
part-add /dev/sdc p 4096 8191
part-add /dev/sdc p 8192 12287
part-add /dev/sdc p 12288 16383
part-add /dev/sdc p 16384 20479
part-init /dev/sdd mbr
part-add /dev/sdd p 4096 8191
part-add /dev/sdd p 8192 12287
part-add /dev/sdd p 12288 16383
part-add /dev/sdd p 16384 20479

# RAID 1.
md-create r1t1 "/dev/sda1 /dev/sdb1"
md-create r1t2 "/dev/sdc1 /dev/sdd1" chunk:65536

# RAID 5.
md-create r5t1 "/dev/sda2 /dev/sdb2 /dev/sdc2 /dev/sdd2" \
  missingbitmap:0x10 nrdevices:4 spare:1 level:5

md-create r5t2 "/dev/sda3 /dev/sdb3" missingbitmap:0x1 level:5

md-create r5t3 "/dev/sdc3 /dev/sdd3" \
  missingbitmap:0x6 nrdevices:2 spare:2 level:5

# Make some filesystems and put some content on the
# new RAID devices to see if they work.
mkfs ext2 /dev/md/r1t1
mkfs ext2 /dev/md/r1t2
mkfs ext2 /dev/md/r5t1
mkfs ext2 /dev/md/r5t2
mkfs ext2 /dev/md/r5t3

mkmountpoint /r1t1
mount /dev/md/r1t1 /r1t1
mkmountpoint /r1t2
mount /dev/md/r1t2 /r1t2
mkmountpoint /r5t1
mount /dev/md/r5t1 /r5t1
mkmountpoint /r5t2
mount /dev/md/r5t2 /r5t2
mkmountpoint /r5t3
mount /dev/md/r5t3 /r5t3

touch /r1t1/foo
mkdir /r1t2/bar
write /r5t1/foo "hello"
write /r5t2/bar "goodbye"
write /r5t3/baz "testing"

EOF

eval `guestfish --listen`
guestfish --remote add-ro mdadm-1.img
guestfish --remote add-ro mdadm-2.img
guestfish --remote add-ro mdadm-3.img
guestfish --remote add-ro mdadm-4.img
guestfish --remote run

for md in `guestfish --remote list-md-devices`; do
  guestfish --remote md-detail "$md" > md-detail.out

  sed 's/:\s*/=/' md-detail.out > md-detail.out.sh
  . md-detail.out.sh
  rm -f md-detail.out.sh

  error=0
  case "$name" in
    *:r1t1)
      [ "$level" = "raid1" ] || error=1
      [ "$devices" -eq 2 ] || error=1
      ;;

    *:r1t2)
      [ "$level" = "raid1" ] || error=1
      [ "$devices" -eq 2 ] || error=1
      ;;

    *:r5t1)
      [ "$level" = "raid5" ] || error=1
      [ "$devices" -eq 4 ] || error=1
      ;;

    *:r5t2)
      [ "$level" = "raid5" ] || error=1
      [ "$devices" -eq 3 ] || error=1
      ;;

    *:r5t3)
      [ "$level" = "raid5" ] || error=1
      [ "$devices" -eq 2 ] || error=1
      ;;

    *)
      error=1
  esac

  [[ "$uuid" =~ ([0-9a-f]{8}:){3}[0-9a-f]{8} ]] || error=1
  [ ! -z "$metadata" ] || error=1

  if [ "$error" -eq 1 ]; then
    echo "$0: Unexpected output from md-detail for device $md"
    cat md-detail.out
    guestfish --remote exit
    exit 1
  fi
done

guestfish --remote exit

eval `guestfish --listen`
guestfish --remote add-ro mdadm-1.img
guestfish --remote add-ro mdadm-2.img
guestfish --remote add-ro mdadm-3.img
guestfish --remote add-ro mdadm-4.img
guestfish --remote run

for md in `guestfish --remote list-md-devices`; do
  guestfish --remote md-stop "$md"
done

guestfish --remote exit

rm md-detail.out mdadm-1.img mdadm-2.img mdadm-3.img mdadm-4.img
