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

# Test -o rhv-upload.
#
# These uses a test harness (see
# v2v/test-v2v-o-rhv-upload-module/ovirtsdk4) to fake responses from
# oVirt.

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
f=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"
export VIRTIO_WIN="$top_srcdir/test-data/fake-virtio-win"
export PYTHONPATH=$srcdir/test-v2v-o-rhv-upload-module:$PYTHONPATH

# Run virt-v2v -o rhv-upload.
#
# The fake ovirtsdk4 module doesn't care about most of the options
# like -oc, -oo rhv-cafile, -op etc.  Any values may be used.
$VG virt-v2v --debug-gc -v -x \
    -i libvirt -ic "$libvirt_uri" windows \
    -o rhv-upload \
    -oc https://example.com/ovirt-engine/api \
    -oo rhv-cafile=/dev/null \
    -oo rhv-direct \
    -op /dev/null \
    -os .
