#!/bin/bash -
# libguestfs virt-p2v test script
# Copyright (C) 2014-2016 Red Hat Inc.
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

unset CDPATH
export LANG=C
set -e

if [ -z "$SLOW" ]; then
    echo "$0: use 'make check-slow' to run this test"
    exit 77
fi

if [ -n "$SKIP_TEST_VIRT_P2V_PXE_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "$0: test skipped because !x86_64"
    exit 77
fi

qemu=qemu-system-x86_64
if ! $qemu -help >/dev/null 2>&1; then
    echo "$0: test skipped because $qemu not found"
    exit 77
fi

img="test-virt-p2v-pxe.img"
if ! test -f $img; then
    echo "$0: test skipped because $img was not created"
    exit 77
fi

guestsdir="$(cd ../test-data/phony-guests && pwd)"
f="$guestsdir/windows.img"
if ! test -f $f; then
    echo "$0: test skipped because phony Windows image was not created"
    exit 77
fi

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
`which sshd` -f test-virt-p2v-pxe.sshd_config -D &
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
