#!/bin/bash -
# libguestfs virt-customize test script
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

export LANG=C
set -e
set -x

if [ -n "$SKIP_TEST_VIRT_CUSTOMIZE_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

f=../test-data/phony-guests/fedora.img
if [ ! -s $f ]; then
    echo "$0: test skipped because there is no fedora.img"
    exit 77
fi

fq=test-virt-customize-img.qcow
out=test-virt-customize.out
rm -f $fq $out
qemu-img create -f qcow2 -b $f $fq

# Add --no-network so UML works.
$VG virt-customize --format qcow2 -a $fq --no-network \
    --write /etc/motd:MOTD \
    --write /etc/motd2:MOTD2 \
    --write /etc/motd3:MOTD3 \
    --delete /etc/motd3

# Verify that the changes were made.
guestfish --ro -a $fq -i <<EOF >$out
!echo -n "motd: "
cat /etc/motd
!echo -n "motd2: "
cat /etc/motd2
is-file /etc/motd3
EOF

grep -sq '^motd: MOTD' $out
grep -sq '^motd2: MOTD2' $out
grep -sq false $out

rm $fq $out
