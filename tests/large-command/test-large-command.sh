#!/bin/bash -
# libguestfs
# Copyright (C) 2025 Red Hat Inc.
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

# Test command-out.  We can't easily test sh-out without having a
# shell (which requires a full guest), however the code path for both
# is essentially identical.

set -e

$TEST_FUNCTIONS

skip_if_skipped

skip_unless stat --version

# Binary must exist and must be linked statically.
bin=large-command/test-large-command
skip_unless test -x $bin
skip_unless bash -c " ldd $bin |& grep -sq 'not a dynamic executable' "

disk=large-command/test.img
rm -f $disk

out1=large-command/test.out1
out2=large-command/test.out2
out3=large-command/test.out3
out4=large-command/test.out4

# Must be larger than protocol size, currently 4MB.
size=$((10 * 1024 * 1024))

guestfish -x -N $disk=fs -m /dev/sda1 <<EOF
upload $bin /test-large-command
chmod 0755 /test-large-command
command-out "/test-large-command $size" $out1
# Check smaller sizes work as well.
command-out "/test-large-command 0" $out2
command-out "/test-large-command 1" $out3
command-out "/test-large-command 80" $out4
EOF

ls -l $out1 $out2 $out3 $out4

cat $out2
cat $out3
cat $out4

# Check the sizes are correct.
test "$( stat -c '%s' $out1 )" -eq $size
test "$( stat -c '%s' $out2 )" -eq 0
test "$( stat -c '%s' $out3 )" -eq 1
test "$( stat -c '%s' $out4 )" -eq 80

# Check the content is correct, for the smaller files.
test `cat $out3` = "x"
test `cat $out4` = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

rm $disk $out1 $out2 $out3 $out4
