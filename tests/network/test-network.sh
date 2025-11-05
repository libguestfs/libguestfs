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

source ./functions.sh
set -e
set -x

skip_if_skipped

rm -f network.output

guestfish --network -a /dev/null <<EOF > network.output
run
debug sh 'ip a'
EOF

# Check if output contains libguestfs hardcoded IP
cat network.output
if ! grep -qE '169\.254\.2\.15' network.output; then
    echo "Network IP address not found in output!"
    rm -f network.output
    exit 1
fi

rm -f network.output
