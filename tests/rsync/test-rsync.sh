#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

# Test rsync by copying a local directory using an involved and
# unrealistic method.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless rsync --help
skip_unless_feature_available rsync

# Get host IP address.  XXX Bit of a hack.
backend="$(guestfish get-backend)"
case "$backend" in
    direct)
        ip=169.254.2.2
        listen_address=localhost
        ;;
    libvirt|libvirt:*)
        # This would work, except that the host firewall is effective
        # on virbr0, and that is likely to block the non-standard port
        # number that we listen on.
#        ip="$(ip -4 -o address show virbr0 |
#                  awk '{print $4}' |
#                  awk -F/ '{print $1}')"
#        listen_address="$ip"
        echo "$0: skipping test because host firewall will probably prevent this test from working"
        exit 77
        ;;
    *)
        echo "$0: don't know how to get IP address of backend $backend"
        exit 77
        ;;
esac

pwd="$(pwd)"
datadir="$(cd ../test-data/files && pwd)"

rm -rf tmp
mkdir tmp

# rsync must listen on a port, but we want tests to be able to
# run in parallel.  Try to choose a random-ish port number (XXX).
port="$(awk 'BEGIN{srand(); print 65000+int(500*rand())}' </dev/null)"

# Write an rsync daemon config file.
cat > rsyncd.conf <<EOF
address = $listen_address
port = $port
pid file = $pwd/rsyncd.pid
[src]
  path = $datadir
  comment = source
  use chroot = false
  read only = true
[dest]
  path = $pwd/tmp
  comment = destination
  use chroot = false
  read only = false
EOF

# Start a local rsync daemon.
rsync --daemon --config=rsyncd.conf

function cleanup ()
{
    kill `cat rsyncd.pid`
}
trap cleanup INT TERM QUIT EXIT

user="$(id -un)"

guestfish --network -N test-rsync.img=fs -m /dev/sda1 <<EOF
mkdir /dir1
rsync-in "rsync://$user@$ip:$port/src/" /dir1/ archive:true
mkdir /dir2
rsync /dir1/ /dir2/ archive:true
rsync-out /dir2/ "rsync://$user@$ip:$port/dest/" archive:true
EOF

# Compare test data to copied data.
# XXX Because we used the archive flag, dates must be preserved.
# XXX Note for separated builds: only generated files are copied.

if [ ! -f tmp/100kallnewlines ] || \
   [ ! -f tmp/hello.b64 ] || \
   [ ! -f tmp/initrd-x86_64.img.gz ] || \
   [ ! -f tmp/test-grep.txt.gz ]; then
    echo "$0: some files failed to copy"
    exit 1
fi

rm -r tmp
rm test-rsync.img
rm rsyncd.conf
