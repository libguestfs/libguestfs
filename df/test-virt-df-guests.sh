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

# Run virt-df on the test guests.

export LANG=C
set -e

if [ -n "$SKIP_TEST_VIRT_DF_GUESTS_SH" ]; then
    echo "$0: skipping test because SKIP_TEST_DF_GUESTS_SH is set."
    exit 77
fi

guestsdir="$(cd ../tests/guests && pwd)"
libvirt_uri="test://$guestsdir/guests.xml"

$VG virt-df -c "$libvirt_uri"
