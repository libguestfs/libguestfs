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

unset CDPATH
set -e

if [ -n "$SKIP_TEST_RSYNC_SH" ]; then
    echo "$0: test skipped because environment variable is set."
    exit 77
fi

# Check we have the rsync command.
if ! rsync --help >/dev/null 2>&1; then
    echo "$0: skipping test because local rsync command is not available"
    exit 77
fi

if [ "$(guestfish get-backend)" = "uml" ]; then
    echo "$0: skipping test because networking is not available in the UML backend"
    exit 77
fi

# If rsync is not available, bail.
if ! guestfish -a /dev/null run : available rsync; then
    echo "$0: skipping test because rsync is not available in the appliance"
    exit 77
fi

pwd="$(pwd)"
datadir="$(cd ../../test-data/files && pwd)"

rm -rf tmp
mkdir tmp

# rsync must listen on a port, but we want tests to be able to
# run in parallel.  Try to choose a random-ish port number (XXX).
port="$(awk 'BEGIN{srand(); print 65000+int(500*rand())}' </dev/null)"

# Write an rsync daemon config file.
cat > rsyncd.conf <<EOF
address = localhost
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

# XXX
ip=169.254.2.2
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
