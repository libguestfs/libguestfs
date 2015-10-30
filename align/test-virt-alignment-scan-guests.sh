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

if [ -n "$SKIP_TEST_VIRT_ALIGNMENT_SCAN_GUESTS_SH" ]; then
    echo "$0: skipping test because SKIP_TEST_VIRT_ALIGNMENT_SCAN_GUESTS_SH is set."
    exit 77
fi

guestsdir="$(cd ../test-data/phony-guests && pwd)"
libvirt_uri="test://$guestsdir/guests-all-good.xml"

$VG virt-alignment-scan -c "$libvirt_uri"
r=$?

# 0, 2 and 3 are reasonable non-error exit codes.  Others are errors.
if [ $r -ne 0 -a $r -ne 2 -a $r -ne 3 ]; then
    exit $r
fi
