#!/bin/bash -
# libguestfs
# Copyright (C) 2017 SUSE Inc.
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

set -e

$TEST_FUNCTIONS
slow_test
skip_if_skipped "$script"

test_data=repository-testdata
rm -rf $test_data
mkdir $test_data

# Make a copy of the Fedora image
cp ../test-data/phony-guests/fedora.img $test_data

# Create minimal index file
cat > $test_data/index << EOF
[fedora]
file=fedora.img
EOF

# Run virt-builder-repository (no compression, interactive)
echo 'x86_64
Fedora Test Image
fedora14
/dev/sda1
/dev/VG/Root
' | virt-builder-repository -v -x --no-compression -i $test_data

assert_config () {
    item=$1
    regex=$2

    sed -n -e "/\[$item]/,/^$/p" $test_data/index | grep "$regex"
}

# Check the generated index file
assert_config 'fedora' 'revision=1'
assert_config 'fedora' 'arch=x86_64'
assert_config 'fedora' 'name=Fedora Test Image'
assert_config 'fedora' 'osinfo=fedora14'
assert_config 'fedora' 'checksum'
assert_config 'fedora' 'format=raw'
assert_config 'fedora' '^size='
assert_config 'fedora' 'compressed_size='
assert_config 'fedora' 'expand=/dev/'


# Copy the debian image and add the minimal piece to index
cp ../test-data/phony-guests/debian.img $test_data

cat >> $test_data/index << EOF

[debian]
file=debian.img
EOF

# Run virt-builder-repository again
echo 'x86_64
Debian Test Image
debian9

' | virt-builder-repository --no-compression -i $test_data

# Check that the new image is complete and the first one hasn't changed
assert_config 'fedora' 'revision=1'

assert_config 'debian' 'revision=1'
assert_config 'debian' 'checksum'

# Modify the fedora image
export EDITOR='echo newline >>'
virt-edit -a $test_data/fedora.img /etc/test3

# Rerun the tool (with compression)
virt-builder-repository -i $test_data

# Check that the revision, file and size have been updated
assert_config 'fedora' 'revision=2'
assert_config 'fedora' 'file=fedora.img.xz'
test -e $test_data/fedora.img.xz
! test -e $test_data/fedora.img

rm -rf $test_data
