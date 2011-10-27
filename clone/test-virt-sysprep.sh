#!/bin/bash -
# libguestfs virt-sysprep test script
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

export LANG=C
set -e

if [ ! -w /dev/fuse ]; then
    echo "SKIPPING virt-sysprep test, because there is no /dev/fuse."
    exit 0
fi

if ! xmlstarlet --help >/dev/null 2>&1; then
    echo "SKIPPING virt-sysprep test, because xmlstarlet is not installed."
    exit 0
fi

rm -f test.img guestfish

qemu-img create -f qcow2 -o backing_file=../images/fedora.img test.img

# Provide alternate 'virt-inspector' and 'guestmount' binaries
# that run the just-built programs.

cat <<'EOF' > virt-inspector
#!/bin/sh -
../run ../inspector/virt-inspector "$@"
EOF
chmod +x virt-inspector
cat <<'EOF' > guestmount
#!/bin/sh -
../run ../fuse/guestmount "$@"
EOF
chmod +x guestmount

PATH=.:$PATH

./virt-sysprep -a test.img

rm -f test.img virt-inspector guestmount
