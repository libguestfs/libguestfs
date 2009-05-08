#!/bin/sh -

#vm=/tmp/vm.img
vm=/mnt/share/tmp/vm.img

modules="--group-install Core -i kernel -i grub"

# Choose one:
#febootstrap $modules fedora-10 local
febootstrap $modules fedora-11 local
#febootstrap $modules centos-5 local http://mirror.centos.org/centos-5/5.3/os/i386/

tar zcf local.tar.gz local
#rm -rf local

guestfish <<EOF
#alloc $vm 8GB
add $vm
run
sfdisk /dev/sda 0 0 0 ',100 ,'
echo Size of /dev/sda1:
blockdev-getsize64 /dev/sda1
echo Size of /dev/sda2:
blockdev-getsize64 /dev/sda2
lvm-remove-all
pvcreate /dev/sda2
vgcreate VG /dev/sda2
lvcreate Root VG 6000
lvcreate Swap VG 500
mkfs ext3 /dev/sda1
mkfs ext3 /dev/VG/Root
mount /dev/VG/Root /
mkdir /boot
mount /dev/sda1 /boot
tgz-in local.tar.gz /
grub-install / /dev/sda
EOF

#rm local.tar.gz
