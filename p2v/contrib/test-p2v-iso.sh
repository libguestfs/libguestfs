#!/bin/bash -
# Test virt-p2v ISO for RHEL 5/6/7.
# Copyright (C) 2017 Red Hat Inc.
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

# Once you have built a virt-p2v ISO (see build-p2v-iso.sh), you
# can interactively test it using this script.

set -e

usage ()
{
    echo './test-p2v-iso.sh virt-p2v-livecd-....iso'
    exit 0
}

if [ $# -ne 1 ]; then
    usage
fi

tmpdir="$(mktemp -d)"
cleanup ()
{
    rm -rf "$tmpdir"
}
trap cleanup INT QUIT TERM EXIT ERR

iso=$1
if [ ! -f "$iso" ]; then
    echo "$iso: file not found"
    exit 1
fi

# Build a temporary guest to test.
disk=$tmpdir/guest.img
virt-builder rhel-6.8 --output $disk

# Boot the guest as if running with virt-p2v ISO in the CD drive.
qemu-system-x86_64 -no-user-config -nodefaults \
                   -no-reboot \
                   -machine accel=kvm:tcg \
                   -cpu host \
                   -m 4096 \
                   -display gtk \
                   -vga std \
                   -drive file=$disk,format=raw,if=ide \
                   -cdrom $iso \
                   -netdev user,id=usernet,net=169.254.0.0/16 \
                   -device rtl8139,netdev=usernet \
                   -boot d
