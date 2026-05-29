#!/bin/bash -
# libguestfs
# Copyright (C) 2026 Red Hat Inc.
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

# Test immutable /etc/resolv.conf which prevented commands
# from being run.

source ./functions.sh
set -e
set -x

skip_if_skipped
skip_unless_phony_guest fedora.img

b=c-api/test-command
skip_unless bash -c "ldd $b |& grep -sq 'not a dynamic executable'"

f=command/immutable.img
rm -f $f
cp $top_builddir/test-data/phony-guests/fedora.img $f

out=command/ls.out
rm -f $out

guestfish -vx --network -a $f -i <<EOF
# Upload the static binary.
upload $b /bin/test-command
chmod 0755 /bin/test-command

# No /etc/resolv.conf
rm-f /etc/resolv.conf

# Run the command, this should succeed.
command "/bin/test-command 1"

# /etc/resolv.conf must still not exist.
# XXX This is tested below.
ls /etc | cat > $out

# Touch /etc/resolv.conf and run the command again.
touch /etc/resolv.conf
command "/bin/test-command 1"
is-file /etc/resolv.conf

# Make /etc/resolv.conf exist and be immutable.
set-e2attrs /etc/resolv.conf i

# Run the command again.
# This used to fail with:
#   libguestfs: error: command: rename: /sysroot/etc/resolv.conf to /sysroot/etc/kccdyoys: Operation not permitted
command "/bin/test-command 1"

EOF

if grep resolv.conf $out; then
    echo "FAIL: /etc/resolv.conf was created by accident"
    exit 1
fi

rm $f $out
