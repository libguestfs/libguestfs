#!/bin/bash -
# libguestfs virt-p2v test script
# Copyright (C) 2014-2019 Red Hat Inc.
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

# Test virt-p2v in non-GUI mode using nbdkit instead of qemu-nbd.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless nbdkit file --version
skip_unless test -f fedora.img
skip_unless test -f blank-part.img

f1="$abs_builddir/fedora.img"
f2="$abs_builddir/blank-part.img"

d=test-virt-p2v-nbdkit.d
rm -rf $d
mkdir $d

# We don't want the program under test to run real 'ssh' or 'scp'.
# They won't work.  Therefore create dummy 'ssh' and 'scp' binaries.
pushd $d
ln -sf "$abs_srcdir/test-virt-p2v-ssh.sh" ssh
ln -sf "$abs_srcdir/test-virt-p2v-scp.sh" scp
popd
export PATH=$d:$PATH

# Note that the PATH already contains the local virt-p2v & virt-v2v
# binaries under test (because of the ./run script).

# The Linux kernel command line.
cmdline="p2v.server=localhost p2v.name=fedora p2v.disks=$f1,$f2 p2v.o=local p2v.os=$(pwd)/$d p2v.network=em1:wired,other p2v.post="

# Only use nbdkit, disable qemu-nbd.
$VG virt-p2v --cmdline="$cmdline" --nbd=nbdkit,nbdkit-no-sa

# Test the libvirt XML metadata and a disk was created.
test -f $d/fedora.xml
test -f $d/fedora-sda
test -f $d/fedora-sdb

rm -r $d
