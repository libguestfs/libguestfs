#!/bin/bash -
# libguestfs virt-builder test script
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

export LANG=C
set -e

abs_builddir=$(pwd)

export XDG_CONFIG_HOME=
export XDG_CONFIG_DIRS="$abs_builddir/test-config"

if [ -z "$SLOW" ]; then
    echo "$0: use 'make check-slow' to run this test"
    exit 77
fi

if [ -n "$SKIP_TEST_VIRT_BUILDER_PLANNER_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

if [ ! -f fedora.xz -o ! -f fedora.qcow2 -o ! -f fedora.qcow2.xz ]; then
    echo "$0: test skipped because there is no fedora.xz, fedora.qcow2 or fedora.qcow2.xz in the build directory"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: test skipped because backend is UML"
    exit 77
fi

rm -f planner-output

for input in phony-fedora phony-fedora-qcow2 phony-fedora-qcow2-uncompressed phony-fedora-no-format; do
    for size in none 1G 1.1G 2G; do
        for format in none raw qcow2; do
            args="--output planner-output --no-cache --no-check-signature"
            if [ "$size" != "none" ]; then args="$args --size $size"; fi
            if [ "$format" != "none" ]; then args="$args --format $format"; fi

            echo $VG virt-builder $input $args
            $VG virt-builder $input $args
        done
    done
done

rm planner-output
