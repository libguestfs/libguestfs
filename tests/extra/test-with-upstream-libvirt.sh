#!/bin/sh -
# Copyright (C) 2012 Red Hat Inc.
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

set -e
#set -x

method="$(../../fish/guestfish get-attach-method)"
if [ "$method" != "libvirt" ]; then
    echo "$0: test skipped because attach-method is not 'libvirt'"
    exit 77
fi

if [ ! -d "$LIBVIRTDIR" ]; then
    echo "$0: \$LIBVIRTDIR not a directory, tests against upstream libvirt skipped"
    exit 77
fi

libvirt_run="$LIBVIRTDIR/run"
if [ ! -x "$libvirt_run" ]; then
    echo "$0: $libvirt_run not executable, tests against upstream libvirt skipped"
    exit 77
fi

exec "$libvirt_run" $MAKE extra-tests-non-recursive
