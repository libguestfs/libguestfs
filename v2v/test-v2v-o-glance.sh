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

# Test -o glance.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
f=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

# We don't want to upload to the real glance, so introduce a fake
# glance binary.
ln -sf "$(which echo)" glance

$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o glance -on test

rm glance
