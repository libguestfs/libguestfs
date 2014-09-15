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

# In future we could make this test much more comprehensive,
# especially testing that the network in fact works.  For now just
# test that the network device can be added.

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ690819_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

backend="$(guestfish get-backend)"
if [[ "$backend" =~ ^uml ]]; then
    echo "$0: test skipped because backend ($backend) is 'uml'."
    exit 77
fi

guestfish --network -a /dev/null run
