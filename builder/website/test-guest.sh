#!/bin/bash -
# virt-builder
# Copyright (C) 2013 Red Hat Inc.
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

# This is not part of the automated test suite.  It's a manual test
# run by the maintainer which must be run on each new guest to ensure
# that all the virt-builder features work on the new guest.
#
# Usage:
# ./run builder/website/test-guest.sh os-version [extra virt-builder args]
# Then read the instructions ...

export LANG=C
set -e

if ! virt-builder --help >/dev/null 2>&1 || [ ! -f builder/virt-builder.pod ]; then
    echo "$0: running the test from the wrong directory, or libguestfs has not been built"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "$0: missing os-version"
    echo "try: ./run virt-builder -l"
    exit 1
fi

osversion="$1"
shift
output="$osversion.img"

virt-builder "$osversion" \
    --no-cache -v \
    --size 10G \
    --root-password password:123456 \
    --hostname test.example.com \
    --install scrub \
    --edit '/etc/issue: s/(.*)/$lineno: $1/' \
    --upload builder/virt-builder.pod:/virt-builder.pod \
    --run-command 'echo RUN COMMAND 1 >> /run-command.log' \
    --run-command 'echo RUN COMMAND 2 >> /run-command.log' \
    --run-command 'echo RUN COMMAND 3 >> /run-command.log' \
    --firstboot-command 'useradd -m -p "" rjones ; chage -d 0 rjones' \
    --firstboot-command 'echo FIRSTBOOT COMMAND 1' \
    --firstboot-command 'echo FIRSTBOOT COMMAND 2' \
    --firstboot-command 'echo FIRSTBOOT COMMAND 3' \
    "$@" |& tee "$osversion.log"

# Boot the guest.
qemu-system-x86_64 \
    -m 1024 \
    -drive "file=$output,format=raw,snapshot=on,if=ide" &

cat <<EOF

          ========================================
The "$osversion" guest is being booted.
The trace file is here: "$osversion.log"

Checklist:

 1: Root password is 123456
 2: Hostname is test.example.com
 3: scrub package is installed
 4: /etc/issue has line numbers
 5: /virt-builder.pod exists and looks reasonable
 6: /run-command.log exists and has 3 lines in correct order
 7: /root/virt-sysprep-firstboot.log exists and has 3 entries in correct order
 8: rjones account exists, with no password
 9: rjones password must be changed at first login
10: /home/rjones exists and is populated
11: random-seed file was created or modified
          ========================================

EOF

#rm $output
