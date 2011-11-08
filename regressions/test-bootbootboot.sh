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

# Some versions of qemu can be flakey and can hang occasionally
# during boot (particularly KVM if the BIOS is the qemu version
# which doesn't have the required KVM patches).  Test repeatedly
# booting.

set -e

rm -f test1.img

n=10
if [ -n "$1" ]; then n=$1; fi

export LIBGUESTFS_DEBUG=1

for i in $(seq 1 $n); do
  echo Test boot $i of $n ...
  ../fish/guestfish -N disk </dev/null
done

rm test1.img

echo Test boot completed after $n iterations.
