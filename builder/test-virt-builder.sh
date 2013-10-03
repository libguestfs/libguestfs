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

abs_srcdir=$(cd $srcdir && pwd)

export VIRT_BUILDER_SOURCE=file://$abs_srcdir/test-index

if [ ! -f fedora.xz ]; then
    echo "$0: test skipped because there is no fedora.xz in the build directory"
    exit 77
fi

rm -f phony-fedora.qcow2

# Test as many options as we can!
#
# Note we cannot test --install, --run since the phony Fedora doesn't
# have a real OS inside just some configuration files.  Just about
# every other option is fair game.
./virt-builder phony-fedora \
    --no-cache --no-check-signature \
    --size 2G --format qcow2 \
    --hostname test.example.com \
    --root-password password:123456 \
    --upload Makefile:/Makefile \
    --firstboot Makefile --firstboot-command 'echo "hello"' \
    --firstboot-install "minicom,inkscape"

# XXX Test that the modifications were made.

rm phony-fedora.qcow2
