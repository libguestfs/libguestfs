#!/bin/bash -
# libguestfs
# Copyright (C) 2017 Red Hat Inc.
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
# https://bugzilla.redhat.com/show_bug.cgi?id=1477623
# Check that the 'file' API doesn't break on some chardevs.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_phony_guest fedora.img

d=rhbz1477623.img
rm -f $d

guestfish -- \
          disk-create $d qcow2 -1 \
          backingfile:$top_builddir/test-data/phony-guests/fedora.img \
          backingformat:raw

guestfish -a $d -i <<EOF
  mkdir /dev
  mknod-c 0777 5 1 /dev/console
  mknod-c 0777 10 175 /dev/agpgart

  # This used to hang.
  file /dev/console

  # This used to print "No such file or directory"
  file /dev/agpgart
EOF

rm $d
