#!/bin/bash -
# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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

# Regression test for virt-v2v handling of blank disks:
# https://bugzilla.redhat.com/show_bug.cgi?id=1232192

set -e
export LANG=C

if [ -n "$SKIP_TEST_RHBZ1232192_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

if ! ../../v2v/virt-v2v --help >/dev/null 2>&1; then
    echo "$0: test skipped because virt-v2v was not built"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because UML backend does not support network"
    exit 77
fi

if [ ! -f ../guests/windows.img ] || [ ! -s ../guests/windows.img ]; then
    echo "$0: test skipped because tests/guests/windows.img was not built"
    exit 77
fi

if [ ! -f ../guests/blank-disk.img ]; then
    echo "$0: test skipped because tests/guests/blank-disk.img was not built"
    exit 77
fi

virt_tools_data_dir=${VIRT_TOOLS_DATA_DIR:-/usr/share/virt-tools}
if ! test -r $virt_tools_data_dir/rhsrvany.exe; then
    echo "$0: test skipped because rhsrvany.exe is not installed"
    exit 77
fi

../../v2v/virt-v2v -i libvirtxml rhbz1232192.xml -o null --no-copy
