#!/bin/bash -
# libguestfs
# Copyright (C) 2017-2023 Red Hat Inc.
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=1930996#c1
#
# Actually a bug/change in LVM, previously we failed to create an LV
# if the underlying disk contained a filesystem signature.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest fedora.img

f=rhbz1930996.img
rm -f $f

guestfish -N $f=lvfs vgremove VG : vgcreate VG /dev/sda1 : lvcreate LV2 VG 100

rm $f
