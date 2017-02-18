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

# Test if we can handle qemu death in the middle of a command.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_backend direct

rm -f qemudie-midcommand.pid

guestfish <<'EOF'
scratch 100M
run
# Kill the subprocess after a short wait.
pid | cat > qemudie-midcommand.pid
! sleep 2 ; kill $(cat qemudie-midcommand.pid) &

-sleep 1000

# We should now be able to rerun the subprocess.
scratch 100M
run
ping-daemon
EOF

rm qemudie-midcommand.pid
