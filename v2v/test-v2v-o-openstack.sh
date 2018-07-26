#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2018 Red Hat Inc.
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

# Test -o openstack.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_if_backend uml
skip_unless_phony_guest windows.img

libvirt_uri="test://$abs_top_builddir/test-data/phony-guests/guests.xml"
windows=$top_builddir/test-data/phony-guests/windows.img

export VIRT_TOOLS_DATA_DIR="$top_srcdir/test-data/fake-virt-tools"

d=test-v2v-o-openstack.d
rm -rf $d
mkdir $d

# We don't want to upload to the real openstack, so introduce a fake
# openstack binary which just logs the command line and provides
# JSON output where required.
cat > $d/openstack <<'EOF'
#!/bin/bash -
echo "$@" >> test-v2v-o-openstack.d/log
echo "$@" | grep -sq -- "-f json" && \
  echo '{ "id": "dummy-vol-id", "status": "available" }'
exit 0
EOF
chmod +x $d/openstack
export PATH=$(pwd)/$d:$PATH

# Create the dummy output volume which virt-v2v will write to.
touch $d/dummy-vol-id

# Run virt-v2v -o openstack.
$VG virt-v2v --debug-gc \
    -i libvirt -ic "$libvirt_uri" windows \
    -o openstack -on test \
    -oo server-id=test \
    -oo guest-id=guestid \
    -oo dev-disk-by-id=$d

# Check the log of openstack commands to make sure they look reasonable.
grep 'token issue' $d/log
grep 'volume create.*size 1.*temporary volume.*test-sda' $d/log
grep 'server add volume' $d/log
grep 'volume set.*--bootable.*dummy-vol-id' $d/log
grep 'volume set.*--property.*virt_v2v_guest_id=guestid' $d/log
grep 'server remove volume' $d/log

rm -r $d
