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

# Test --print-source option.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest windows.img

d=test-v2v-print-source.d
rm -rf $d
mkdir $d

$VG virt-v2v --debug-gc \
    -i libvirtxml test-v2v-print-source.xml \
    -o local -os $d \
    --print-source > $d/output

mv $d/output $d/output.orig
< $d/output.orig \
grep -v 'Opening the source' |
grep -v 'Source guest information' |
sed -e 's,/.*/windows.img,windows.img,' |
grep -v '^$' \
> $d/output

diff -u test-v2v-print-source.expected $d/output

rm -r $d
