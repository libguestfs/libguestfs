#!/bin/bash -
# libguestfs virt-sysprep test script
# Copyright (C) 2016 Red Hat Inc.
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

# Test removal of editor backup files.

set -e

$TEST_FUNCTIONS
skip_if_skipped
# UML does not support qcow2.
skip_if_backend uml
skip_unless_phony_guest fedora.img

f=$top_builddir/test-data/phony-guests/fedora.img

rm -f test-backup-files.qcow2
rm -f test-backup-files-before
rm -f test-backup-files-after

# Add some backup files to the Fedora image.
guestfish -- \
          disk-create test-backup-files.qcow2 qcow2 -1 \
            backingfile:$f backingformat:raw
guestfish --format=qcow2 -a test-backup-files.qcow2 -i <<'EOF'
# /bin and /usr are not on the whitelist, so these files shouldn't be deleted.
touch /bin/test~
touch /usr/share/test~
find / | cat > test-backup-files-before
touch /etc/fstab.bak
touch /etc/resolv.conf~
EOF

# Run virt-sysprep backup-files operation only.

virt-sysprep -x --format qcow2 -a test-backup-files.qcow2 \
    --enable backup-files

# Check the file list is the same as above.
guestfish --format=qcow2 -a test-backup-files.qcow2 -i find / > test-backup-files-after

diff -u test-backup-files-before test-backup-files-after

rm test-backup-files.qcow2
rm test-backup-files-before
rm test-backup-files-after
