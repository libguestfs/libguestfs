#!/bin/bash -
# libguestfs virt-sysprep test script
# Copyright (C) 2013 Red Hat Inc.
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

# Test all the combinations of password options.

set -e

$TEST_FUNCTIONS
skip_if_skipped
# UML backend does not support qcow2.
skip_if_backend uml
skip_unless_phony_guest fedora.img

f=$top_builddir/test-data/phony-guests/fedora.img

# For this test to work, we need a guest with several user accounts,
# so we fake that now.

rm -f passwords.qcow2 password
guestfish -- \
    disk-create passwords.qcow2 qcow2 -1 \
      backingfile:$f backingformat:raw

guestfish -a passwords.qcow2 -i <<'EOF'
write-append /etc/shadow "test01::15677:0:99999:7:::\n"
write-append /etc/shadow "test02::15677:0:99999:7:::\n"
write-append /etc/shadow "test03::15677:0:99999:7:::\n"
write-append /etc/shadow "test04::15677:0:99999:7:::\n"
write-append /etc/shadow "test05::15677:0:99999:7:::\n"
write-append /etc/shadow "test06::15677:0:99999:7:::\n"
write-append /etc/shadow "test07::15677:0:99999:7:::\n"
write-append /etc/shadow "test08::15677:0:99999:7:::\n"
write-append /etc/shadow "test09::15677:0:99999:7:::\n"
write-append /etc/shadow "test10::15677:0:99999:7:::\n"
write-append /etc/shadow "test11::15677:0:99999:7:::\n"
EOF

echo 123456 > password

# Run virt-sysprep password operation.

virt-sysprep \
    --format qcow2 \
    -a passwords.qcow2 \
    --enable customize \
    --password test01:password:123456 \
    --password test02:password:123456:7890 \
    --password test03:file:./password \
    --password test04:random \
    --password test05:disabled \
    --password test06:locked:password:123456 \
    --password test07:locked:password:123456:7890 \
    --password test08:locked:file:./password \
    --password test09:locked:random \
    --password test10:locked:disabled \
    --password test11:locked

rm passwords.qcow2 password
