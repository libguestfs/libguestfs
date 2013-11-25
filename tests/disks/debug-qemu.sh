#!/bin/bash
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

# A fake debugging qemu which just dumps out the parameters to a known
# file.

if [ -z "$DEBUG_QEMU_FILE" ]; then
    echo "$0: \$DEBUG_QEMU_FILE environment variable must be set."
    exit 1
fi

echo "$@" > "$DEBUG_QEMU_FILE"

# Real qemu would connect back to the daemon socket with a working
# daemon.  We don't do that, so the libguestfs parent process will
# always get an error.
exit 0
