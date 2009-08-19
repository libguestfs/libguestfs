#!/bin/sh -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Test download where the library cancels.
#
#

set -e

rm -f test.img

../fish/guestfish <<'EOF'
add ../images/test.iso
run

mount-ro /dev/sda /

# Download a file to /dev/full.
echo "Expect: write: /dev/full: No space left on device"
-download /100krandom /dev/full

ping-daemon
EOF

rm -f test.img
