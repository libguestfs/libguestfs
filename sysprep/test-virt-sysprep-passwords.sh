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

export LANG=C
set -e

# Test all the combinations of password options.

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because uml backend does not support qcow2"
    exit 77
fi

if [ ! -s ../test-data/phony-guests/fedora.img ]; then
    echo "$0: skipping test because there is no phony Fedora test image"
    exit 77
fi

# For this test to work, we need a guest with several user accounts,
# so we fake that now.

rm -f passwords.qcow2 password
guestfish -- \
    disk-create passwords.qcow2 qcow2 -1 \
      backingfile:../test-data/phony-guests/fedora.img backingformat:raw

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
