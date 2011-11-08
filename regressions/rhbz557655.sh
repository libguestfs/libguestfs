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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=557655
# "guestfish number parsing should not use atoi, should support '0...' for octal and '0x...' for hexadecimal"

set -e
rm -f test.out test.err
export LANG=C

../fish/guestfish >> test.out 2>> test.err <<EOF
# set-memsize is just a convenient non-daemon function that
# takes a single integer argument.
set-memsize 0
get-memsize
set-memsize 0x10
get-memsize
set-memsize 010
get-memsize
set-memsize -1073741824
get-memsize
set-memsize 1073741823
get-memsize

# the following should all provoke error messages:
-set-memsize -9000000000000000
-set-memsize 9000000000000000
-set-memsize 0x900000000000
-set-memsize 07777770000000000000
-set-memsize ABC
-set-memsize 09
-set-memsize 123L
EOF

../fish/guestfish -N fs -m /dev/sda1 >> test.out 2>> test.err <<EOF
touch /test

# truncate-size takes an Int64 argument
truncate-size /test 1234
filesize /test
truncate-size /test 0x4d2
filesize /test
truncate-size /test 02322
filesize /test

# should parse OK, but underlying filesystem will reject it:
-truncate-size /test 0x7fffffffffffffff

# larger than 64 bits, should be an error:
-truncate-size /test 0x10000000000000000

# these should all provoke parse errors:
-truncate-size /test ABC
-truncate-size /test 09
-truncate-size /test 123L
EOF

# If we are running with debugging enabled (or even if not), then
# other messages and warnings can end up in the test.err (stderr) log.
# Thus filter out only lines we expect.  'proc 200' is the procedure
# number of truncate_size.
mv test.err test.err~
grep -E 'set[-_]memsize|truncate[-_]size' test.err~ |
  grep -Ev 'libguestfs: trace:' |
  grep -Ev 'proc 200' > test.err
rm test.err~

diff -u rhbz557655-expected.stdout test.out
diff -u rhbz557655-expected.stderr test.err
rm test.out test.err test1.img
