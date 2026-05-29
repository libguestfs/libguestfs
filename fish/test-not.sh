#!/bin/bash -
# libguestfs
# Copyright (C) 2011-2026 Red Hat Inc.
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

# Test guestfish 'not' command.

source ../tests/functions.sh
set -e
set -x

skip_if_skipped

# This would normally be an error, but should now succeed.
$VG guestfish -x not unknown-command

# This would normally be OK, but should now be an error.
if $VG guestfish -x not add /dev/null ; then
    echo "FAIL: expected 'not add' to fail, but it succeeded"
    exit 1
fi

# 'not not' cancels out.
$VG guestfish -x not not add /dev/null
