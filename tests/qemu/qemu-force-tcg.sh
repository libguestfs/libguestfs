#!/bin/bash -
# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Check force_tcg really forces TCG mode.

$TEST_FUNCTIONS
skip_if_skipped

set -e

rm -f qemu-force-tcg.out

guestfish -a /dev/null <<EOF
set-backend-setting force_tcg 1
run
debug sh "cat /sys/devices/system/clocksource/clocksource0/current_clocksource" | cat > qemu-force-tcg.out
EOF

# The output file should *not* contain kvm-clock.
if [ "$(cat qemu-force-tcg.out)" = "kvm-clock" ]; then
    echo "$0: force_tcg setting did not force TCG mode"
    cat qemu-force-tcg.out
    exit 1
fi

rm qemu-force-tcg.out
