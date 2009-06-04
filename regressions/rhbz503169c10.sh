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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=503169#c10

set -e

rm -f test1.img
dd if=/dev/zero of=test1.img bs=1024k count=10

export LIBGUESTFS_PATH=../appliance

../fish/guestfish -a test1.img <<EOF
launch
ll /../dev/console
ll /../dev/full
ll /../dev/mapper/
ll /../dev/null
ll /../dev/ptmx
ll /../dev/pts/
ll /../dev/random
ll /../dev/shm/
ll /../dev/stderr
ll /../dev/stdin
ll /../dev/stdout
ll /../dev/tty
ll /../dev/urandom
ll /../dev/zero
EOF

rm test1.img
