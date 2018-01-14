#!/bin/bash -
# libguestfs
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

# To test virt-tail, we run a guestfish instance which creates a disk
# and a file in that disk.  We then run virt-tail in parallel.  Back
# in the guestfish instance we append to the file, and we check that
# the addenda are displayed by virt-tail.

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

# Libvirt screws with the SELinux labels, preventing guestfish from
# continuing to write to the original disk.  Therefore only run this
# test when using direct access.
skip_unless_backend direct

out=test-virt-tail.out
disk=test-virt-tail.disk

rm -f $out $disk

tailpid=0

eval `guestfish --listen`

# Clean up if the script is killed or exits early.
cleanup ()
{
    status=$?
    set +e
    guestfish --remote exit
    if [ "$tailpid" -gt 0 ]; then kill "$tailpid"; fi

    # Don't delete the output files if non-zero exit.
    if [ "$status" -eq 0 ]; then rm -f $disk $out; fi

    exit $status
}
trap cleanup INT QUIT TERM EXIT ERR

# Create the output disk.
guestfish --remote sparse $disk 10M
guestfish --remote run
guestfish --remote part-disk /dev/sda mbr
guestfish --remote mkfs ext2 /dev/sda1
guestfish --remote mount /dev/sda1 /

# Create the file to be tailed with a single full line of content.
guestfish --remote write /tail 'line 1
'
guestfish --remote sync

# Run virt-tail in the background
$VG virt-tail -a $disk -m /dev/sda1 /tail > $out &
tailpid=$!

# Wait for the first line of the tailed file to appear.
# Note we can wait up to 10 minutes here to deal with slow machines.
for retry in `seq 0 60`; do
    if grep -sq "line 1" $out; then break; fi
    sleep 10;
done
if [ "$retry" -ge 60 ]; then
    echo "$0: error: initial line of output did not appear"
    exit 1
fi

# Write some more lines to the file.
guestfish --remote write-append /tail 'line 2
line 3
'
guestfish --remote sync

# Wait for new content to appear.
for retry in `seq 0 60`; do
    if grep -sq "line 3" $out; then break; fi
    sleep 10;
done
if [ "$retry" -ge 60 ]; then
    echo "$0: error: continued output did not appear"
    exit 1
fi

# Delete the file.  This should cause virt-tail to exit gracefully.
guestfish --remote rm /tail
guestfish --remote sync

# Wait for virt-tail to finish and check the status.
wait "$tailpid"
tailstatus=$?
tailpid=0
if [ "$tailstatus" -ne 0 ]; then
    echo "$0: error: non-zero exit status from virt-tail: $tailstatus"
    exit 1
fi

# cleanup() is called implicitly which cleans up everything.
exit 0
