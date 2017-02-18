#!/bin/bash
# Copyright (C) 2014 Red Hat Inc.
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

# Test the disk-create API.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f disk*.img file:*.img

# XXX We should also test failure paths.

guestfish <<EOF
  disk-create disk1.img  raw   256K
  disk-create disk2.img  raw   256K preallocation:off
  disk-create disk2.img  raw   256K preallocation:sparse
  disk-create disk3.img  raw   256K preallocation:full
  disk-create disk4.img  qcow2 256K
  disk-create disk5.img  qcow2 256K preallocation:off
  disk-create disk5.img  qcow2 256K preallocation:sparse
  disk-create disk6.img  qcow2 256K preallocation:metadata
  disk-create disk6.img  qcow2 256K preallocation:full
  disk-create disk7.img  qcow2 256K compat:1.1
  disk-create disk8.img  qcow2 256K clustersize:128K
  disk-create disk9.img  qcow2 -1   backingfile:disk1.img compat:1.1
  disk-create disk10.img qcow2 -1   backingfile:disk2.img backingformat:raw
  disk-create disk11.img qcow2 -1   backingfile:disk4.img backingformat:qcow2

  # Some annoying corner-cases in qemu-img.
  disk-create disk:0.img qcow2 256K
  disk-create file:0.img qcow2 256K
  disk-create disk,0.img qcow2 256K
  disk-create disk,,0.img qcow2 256K
EOF

output="$(guestfish <<EOF
  disk-format disk1.img
  disk-format disk2.img
  disk-format disk3.img
  disk-format disk4.img
  disk-format disk5.img
  disk-format disk6.img
  disk-format disk7.img
  disk-format disk8.img
  disk-format disk9.img
  disk-format disk10.img
  disk-format disk11.img
  disk-format disk:0.img
  disk-format file:0.img
  disk-format disk,0.img
  disk-format disk,,0.img

  disk-has-backing-file disk1.img
  disk-has-backing-file disk2.img
  disk-has-backing-file disk3.img
  disk-has-backing-file disk4.img
  disk-has-backing-file disk5.img
  disk-has-backing-file disk6.img
  disk-has-backing-file disk7.img
  disk-has-backing-file disk8.img
  disk-has-backing-file disk9.img
  disk-has-backing-file disk10.img
  disk-has-backing-file disk11.img
  disk-has-backing-file disk:0.img
  disk-has-backing-file file:0.img
  disk-has-backing-file disk,0.img
  disk-has-backing-file disk,,0.img

  disk-virtual-size disk1.img
  disk-virtual-size disk2.img
  disk-virtual-size disk3.img
  disk-virtual-size disk4.img
  disk-virtual-size disk5.img
  disk-virtual-size disk6.img
  disk-virtual-size disk7.img
  disk-virtual-size disk8.img
  disk-virtual-size disk9.img
  disk-virtual-size disk10.img
  disk-virtual-size disk11.img
  disk-virtual-size disk:0.img
  disk-virtual-size file:0.img
  disk-virtual-size disk,0.img
  disk-virtual-size disk,,0.img
EOF
)"

if [ "$output" != "raw
raw
raw
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
qcow2
false
false
false
false
false
false
false
false
true
true
true
false
false
false
false
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144
262144" ]; then
    echo "$0: unexpected output:"
    echo "$output"
    exit 1
fi

rm disk*.img file:*.img
