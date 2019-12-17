#!/bin/bash -
# libguestfs virt-inspector test script
# Copyright (C) 2012-2019 Red Hat Inc.
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

# Test that virt-inspector can work on encrypted images when the
# right password is supplied.
#
# Regression test for https://bugzilla.redhat.com/show_bug.cgi?id=1602353

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

f=../test-data/phony-guests/fedora-luks.img

# Ignore zero-sized file.
if [ -s "$f" ]; then
    b=$(basename "$f")
    echo FEDORA |
    $VG virt-inspector --keys-from-stdin --format=raw -a "$f" > "actual-$b.xml"
    # Check the generated output validate the schema.
    $XMLLINT --noout --relaxng "$srcdir/virt-inspector.rng" "actual-$b.xml"
    # This 'diff' command will fail (because of -e option) if there
    # are any differences.
    diff -ur $diff_ignore "$srcdir/expected-$b.xml" "actual-$b.xml"
fi
