#!/bin/bash -
# libguestfs
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

if [ ! -f ../test-data/phony-guests/fedora.img ]; then
    echo "$0: test skipped because there is no phony fedora test image"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because backend is UML"
    exit 77
fi

rm -f fedora.qcow2

# Modify a copy of the image.
guestfish -- \
  disk-create fedora.qcow2 qcow2 -1 \
    backingfile:../test-data/phony-guests/fedora.img backingformat:raw

guestfish --format=qcow2 -a fedora.qcow2 -i <<EOF
touch /diff
write-append /etc/motd "Testing virt-diff\n"
EOF

output="$($VG virt-diff --format=raw -a ../test-data/phony-guests/fedora.img --format=qcow2 -A fedora.qcow2)"

expected="\
+ - 0644          0 /diff
= - 0644         37 /etc/motd
@@ -1 +1,2 @@
 Welcome to Fedora release 14 (Phony)
+Testing virt-diff
@@ End of diff @@"

if [ "$output" != "$expected" ]; then
    echo "$0: error: unexpected output from virt-diff"
    echo "---- output: ------------------------------------------"
    echo "$output"
    echo "---- expected: ----------------------------------------"
    echo "$expected"
    echo "-------------------------------------------------------"
    exit 1
fi

rm fedora.qcow2
