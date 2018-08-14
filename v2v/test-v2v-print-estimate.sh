#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2018 Red Hat Inc.
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

# Test --print-estimate option.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest windows.img
skip_unless jq --version

f=test-v2v-print-estimate.out
rm -f $f

echo "Actual:"
du -s -B 1 ../test-data/phony-guests/windows.img

$VG virt-v2v --debug-gc \
    -i libvirtxml test-v2v-print-source.xml \
    -o local -os $(pwd) \
    --print-estimate \
    --machine-readable=file:$f

echo -n "Estimate: "
cat $f

# Check the total field exists and is numeric.
jq '.total' $f | grep -Esq '^[[:digit:]]+$'

rm -f $f
