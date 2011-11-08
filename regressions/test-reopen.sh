#!/bin/bash -
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Test reopening the handle in the same process.  This used to fail
# but was corrected in 03e1f74ee08dc71bc09cc7655bf4732685f80b43.

set -e

rm -f test.img

../fish/guestfish <<'EOF'
reopen
reopen
reopen

alloc test.img 5M
run
reopen

alloc test.img 5M
run
reopen

EOF

rm -f test.img
