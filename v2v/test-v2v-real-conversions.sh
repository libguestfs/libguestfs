#!/bin/bash -
# libguestfs virt-v2v test script
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

# Test virt-v2v on some real guests.
#
# The phony Fedora guest isn't sufficient for testing.  The
# Makefile.am builds some real guests using virt-builder and we just
# run virt-v2v on those (to make sure it doesn't crash / assert).

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_V2V_REAL_CONVERSIONS_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

d=test-v2v-real-conversions.d
rm -rf $d
mkdir $d

for file in *.img; do
    if test -f $file && test -s $file ; then
        n=`basename $file .img`

        # Create some minimal test metadata.
        cat > $d/$n-input.xml <<EOF
<domain type='test'>
  <name>$n</name>
  <memory>1048576</memory>
  <os>
    <type arch='$(uname -m)'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='$(pwd)/$file'/>
      <target dev='vda' bus='virtio'/>
    </disk>
  </devices>
</domain>
EOF

      ./virt-v2v --debug-gc \
          -i libvirtxml $d/$n-input.xml \
          -o local -os $d

      # Test the libvirt XML metadata and a disk was created.
      test -f $d/$n.xml
      test -f $d/$n-sda
    fi
done

rm -r $d
