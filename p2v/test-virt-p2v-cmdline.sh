#!/bin/bash -
# libguestfs virt-p2v test script
# Copyright (C) 2015 Red Hat Inc.
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

# Test virt-p2v command line parsing in non-GUI mode.

unset CDPATH
export LANG=C
set -e

if [ -n "$SKIP_TEST_VIRT_P2V_CMDLINE_SH" ]; then
    echo "$0: test skipped because environment variable is set"
    exit 77
fi

out=test-virt-p2v-cmdline.out
rm -f $out

# The Linux kernel command line.
virt-p2v --cmdline='p2v.server=localhost p2v.port=123 p2v.username=user p2v.password=secret p2v.skip_test_connection p2v.name=test p2v.vcpus=4 p2v.memory=1G p2v.disks=sda,sdb,sdc p2v.removable=sdd p2v.interfaces=eth0,eth1 p2v.o=local p2v.oa=sparse p2v.oc=qemu:///session p2v.of=raw p2v.os=/var/tmp p2v.network=em1:wired,other p2v.dump_config_and_exit' > $out

# For debugging purposes.
cat $out

# Check the output contains what we expect.
grep "^conversion server.*localhost" $out
grep "^port.*123" $out
grep "^username.*user" $out
grep "^sudo.*false" $out
grep "^guest name.*test" $out
grep "^vcpus.*4" $out
grep "^memory.*"$((1024*1024*1024)) $out
grep "^disks.*sda sdb sdc" $out
grep "^removable.*sdd" $out
grep "^interfaces.*eth0 eth1" $out
grep "^network map.*em1:wired other" $out
grep "^output.*local" $out
grep "^output alloc.*sparse" $out
grep "^output conn.*qemu:///session" $out
grep "^output format.*raw" $out
grep "^output storage.*/var/tmp" $out

rm $out
