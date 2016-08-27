#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2016 Red Hat Inc.
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

# Test that trimming doesn't regress.  Suggested by Ming Xie in
# https://bugzilla.redhat.com/show_bug.cgi?id=1264332

unset CDPATH
export LANG=C
set -e

if [ -z "$SLOW" ]; then
    echo "$0: use 'make check-slow' to run this test"
    exit 77
fi

# This test is expected to fail on NFS.
if [ -n "$SKIP_TEST_V2V_TRIM_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support discard"
    exit 77
fi

d=test-v2v-trim.d
rm -rf $d
mkdir $d

n=fedora-20

f="$(pwd)/$d/$n.img"
if ! virt-builder -l "$n"; then
    echo "$0: virt-builder $n image not found"
    exit 77
fi
virt-builder "$n" --quiet -o "$f"

qemu-img create -f qcow2 -b "$f" $d/fedora.qcow2

guestfish -a $d/fedora.qcow2 -i <<EOF
fill 1 500M /big
fill 1 100M /boot/big
sync
rm /big
rm /boot/big
umount-all
EOF

size_before=$(du -s "$f" | awk '{print $1}')
echo size_before=$size_before

if [ $size_before -lt 800000 ]; then
    echo "test virt-v2v trim: size_before ($size_before) too small"
    exit 1
fi

virt-v2v --debug-gc \
         -i disk $d/fedora.qcow2 \
         -o local -os $d

# Test the libvirt XML metadata and a disk was created.
test -f $d/fedora.xml
test -f $d/fedora-sda

size_after=$(du -s $d/fedora-sda | awk '{print $1}')
echo size_after=$size_after

# We're expecting the image to grow a bit because of the changes made
# by conversion (I observed growth of about 9MB).  That's OK.  If it
# grows by ~ 500 + 100 MB, then that's not OK.  So choose a threshold
# of 300 MB.

if [ $((size_after-size_before)) -gt 300000 ]; then
    echo "test virt-v2v trim: size_after ($size_after) too large"
    echo "trimming failed"
    exit 1
fi

rm -r $d
