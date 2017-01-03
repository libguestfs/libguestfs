#!/bin/bash -
# libguestfs virt-p2v test script
# Copyright (C) 2014-2018 Red Hat Inc.
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

# Test virt-p2v in non-GUI mode with something resembling the
# PXE boot code path.  This tests:
# * virt-p2v-make-disk
# * systemd p2v.service
# * launch-virt-p2v
# * networking
# * virt-p2v in kernel command-line mode

set -e

$TEST_FUNCTIONS
slow_test
skip_if_skipped
skip_if_backend uml
skip_unless_arch x86_64

qemu=qemu-system-x86_64
skip_unless $qemu -help

img="test-virt-p2v-pxe.img"
if ! test -f $img; then
    echo "$0: test skipped because $img was not created"
    exit 77
fi

skip_unless_phony_guest windows.img
f="$top_builddir/test-data/phony-guests/windows.img"

virt_tools_data_dir=${VIRT_TOOLS_DATA_DIR:-/usr/share/virt-tools}
if ! test -r $virt_tools_data_dir/rhsrvany.exe; then
    echo "$0: test skipped because rhsrvany.exe is not installed"
    exit 77
fi

d=test-virt-p2v-pxe.d
rm -rf $d
mkdir $d

# Start the ssh server.  Kill it if the script exits for any reason.
# Note you must use an absolute path to exec sshd.
`which sshd` -f test-virt-p2v-pxe.sshd_config -D -e &
sshd_pid=$!
cleanup ()
{
    kill $sshd_pid
}
trap cleanup INT QUIT TERM EXIT ERR

# Get the randomly assigned sshd port number.
port="$(grep ^Port test-virt-p2v-pxe.sshd_config | awk '{print $2}')"

# Connect as the local user.
username="$(id -un)"

# Output storage path.
os="$(cd $d; pwd)"

# The Linux kernel command line.
cmdline="root=/dev/sda3 ro console=ttyS0 printk.time=1 p2v.server=10.0.2.2 p2v.port=$port p2v.username=$username p2v.identity=file:///var/tmp/id_rsa p2v.name=windows p2v.o=local p2v.os=$os"

# Run virt-p2v inside qemu.
$qemu \
    -nodefconfig \
    -display none \
    -machine accel=kvm:tcg \
    -m 2048 \
    -kernel test-virt-p2v-pxe.vmlinuz \
    -initrd test-virt-p2v-pxe.initramfs \
    -append "$cmdline" \
    -boot c \
    -device virtio-scsi-pci,id=scsi \
    -drive file=$img,format=raw,snapshot=on,if=none,index=0,id=hd0 \
    -device scsi-hd,drive=hd0 \
    -drive file=$f,format=raw,snapshot=on,if=none,index=1,id=hd1 \
    -device scsi-hd,drive=hd1 \
    -netdev user,id=usernet \
    -device virtio-net-pci,netdev=usernet \
    -serial stdio

# Test the libvirt XML metadata and a disk was created.
test -f $d/windows.xml
test -f $d/windows-sda

rm -r $d
