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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=975797
# Ensure the appliance doesn't hang when using the 'iface' parameter.

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ690819_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

backend="$(../../fish/guestfish get-attach-method)"
if [[ "$backend" =~ ^libvirt ]]; then
    echo "$0: test skipped because attach-method ($backend) is 'libvirt'."
    exit 77
fi

rm -f test1.img test2.img test3.img

# The timeout utility was not available in RHEL 5.
if timeout --help >/dev/null 2>&1; then
    timeout="timeout 600"
fi

# Use real disk images here since the code for adding /dev/null may
# take shortcuts.
truncate -s 1G test1.img
truncate -s 1G test2.img
truncate -s 1G test3.img

$timeout ../../fish/guestfish <<EOF
add-drive test1.img iface:virtio
add-drive test2.img iface:ide
add-drive test3.img
run
EOF

rm test1.img test2.img test3.img
