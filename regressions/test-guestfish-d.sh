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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Test guestfish -d option.

set -e

rm -f test.img test.xml test.out

cwd="$(pwd)"

truncate -s 10M test.img

# Libvirt test XML, see libvirt.git/examples/xml/test/testnode.xml
cat > test.xml <<EOF
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
        <source file="$cwd/test.img"/>
        <target dev="hda"/>
      </disk>
    </devices>
  </domain>
</node>
EOF

../fish/guestfish -c "test://$cwd/test.xml" --ro -d guest -x \
  </dev/null >test.out 2>&1
grep -sq '^add_drive_ro.*test.img' test.out

rm -f test.img test.xml test.out
