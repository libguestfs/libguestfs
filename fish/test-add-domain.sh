#!/bin/bash -
# libguestfs
# Copyright (C) 2010 Red Hat Inc.
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

# Test add-domain command.

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-add-domain-{1,2,3,4}.img
rm -f test-add-domain.xml test-add-domain.out

$VG guestfish sparse test-add-domain-1.img 1M
$VG guestfish sparse test-add-domain-2.img 1M
$VG guestfish disk-create test-add-domain-3.img qcow2 1M
$VG guestfish sparse test-add-domain-4.img 1M

# Libvirt test XML, see libvirt.git/examples/xml/test/testnode.xml
cat > test-add-domain.xml <<EOF
<node>
  <domain type="test">
    <name>guest</name>
    <os>
      <type>hvm</type>
      <boot dev='hd'/>
    </os>
    <memory>524288</memory>
    <devices>
      <disk type="file">
        <source file="$abs_builddir/test-add-domain-1.img"/>
        <target dev="hda"/>
      </disk>
      <disk type="file">
        <driver name="qemu" type="raw"/>
        <source file="$abs_builddir/test-add-domain-2.img"/>
        <target dev="hdb"/>
      </disk>
      <disk type="file">
        <driver name="qemu" type="qcow2"/>
        <source file="$abs_builddir/test-add-domain-3.img"/>
        <target dev="hdc"/>
      </disk>
      <disk type="file">
        <driver name="qemu" type="raw"/>
        <source file="$abs_builddir/test-add-domain-4.img"/>
        <target dev="hdd"/>
        <readonly/>
      </disk>
    </devices>
  </domain>
</node>
EOF

$VG guestfish >test-add-domain.out <<EOF
  domain guest libvirturi:test://$abs_builddir/test-add-domain.xml readonly:true
  debug-drives
EOF
grep -sq "test-add-domain-1.img readonly" test-add-domain.out
! grep -sq "test-add-domain-1.img.*format" test-add-domain.out
grep -sq "test-add-domain-2.img readonly format=raw" test-add-domain.out
grep -sq "test-add-domain-3.img readonly format=qcow2" test-add-domain.out

# Test readonlydisk = "ignore".
$VG guestfish >test-add-domain.out <<EOF
  -domain guest libvirturi:test://$abs_builddir/test-add-domain.xml readonly:true readonlydisk:ignore
  debug-drives
EOF
grep -sq "test-add-domain-1.img" test-add-domain.out
grep -sq "test-add-domain-2.img" test-add-domain.out
grep -sq "test-add-domain-3.img" test-add-domain.out
! grep -sq "test-add-domain-4.img" test-add-domain.out

# Test atomicity.
rm test-add-domain-3.img

$VG guestfish >test-add-domain.out <<EOF
  -domain guest libvirturi:test://$abs_builddir/test-add-domain.xml readonly:true
  debug-drives
EOF
! grep -sq "test-add-domain-1.img" test-add-domain.out
! grep -sq "test-add-domain-2.img" test-add-domain.out
! grep -sq "test-add-domain-3.img" test-add-domain.out
! grep -sq "test-add-domain-4.img" test-add-domain.out

rm test-add-domain-{1,2,4}.img
rm test-add-domain.xml test-add-domain.out
