#!/bin/bash -
# libguestfs
# Copyright (C) 2011 Red Hat Inc.
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

# If you used the guestfish command 'upload' and accidentally set the
# target to a directory instead of the full filename, then previously
# libguestfs would hang.  It should return an error instead.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_test_iso

rm -f test-upload-to-dir.img test-upload-to-dir.out

if $VG guestfish \
       -N test-upload-to-dir.img=fs \
       -m /dev/sda1 \
       upload $top_builddir/test-data/test.iso / 2>test-upload-to-dir.out
then
  echo "$0: expecting guestfish to return an error"
  exit 1
fi

if ! grep -q "upload: /: Is a directory" test-upload-to-dir.out; then
  echo "$0: unexpected error message from guestfish"
  cat test-upload-to-dir.out
  exit 1
fi

rm test-upload-to-dir.img test-upload-to-dir.out
