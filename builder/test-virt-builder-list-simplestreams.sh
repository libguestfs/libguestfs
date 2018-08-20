#!/bin/bash -
# libguestfs virt-builder test script
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

export XDG_CONFIG_HOME=
export XDG_CONFIG_DIRS="$abs_builddir/test-simplestreams"

short_list=$($VG virt-builder --no-check-signature --no-cache --list)

if [ "$short_list" != "net.cirros-cloud:standard:0.3:powerpc powerpc    cirros-0.3.4-powerpc
net.cirros-cloud:standard:0.3:x86_64 x86_64     cirros-0.3.4-x86_64
net.cirros-cloud:standard:0.3:i386 i386       cirros-0.3.4-i386" ]; then
    echo "$0: unexpected --list output:"
    echo "$short_list"
    exit 1
fi

long_list=$(virt-builder --no-check-signature --no-cache --list --long)

if [ "$long_list" != "Source URI: file://$abs_builddir/test-simplestreams

os-version:              net.cirros-cloud:standard:0.3:powerpc
Full name:               cirros-0.3.4-powerpc
Architecture:            powerpc
Minimum/default size:    16.4M
Aliases:                 cirros-0.3.4-powerpc

os-version:              net.cirros-cloud:standard:0.3:x86_64
Full name:               cirros-0.3.4-x86_64
Architecture:            x86_64
Minimum/default size:    12.7M
Aliases:                 cirros-0.3.4-x86_64

os-version:              net.cirros-cloud:standard:0.3:i386
Full name:               cirros-0.3.4-i386
Architecture:            i386
Minimum/default size:    11.9M
Aliases:                 cirros-0.3.4-i386" ]; then
    echo "$0: unexpected --list --long output:"
    echo "$long_list"
    exit 1
fi

json_list=$(virt-builder --no-check-signature --no-cache --list --list-format json)

if [ "$json_list" != "{
  \"version\": 1,
  \"sources\": [
    {
      \"uri\": \"file://$abs_builddir/test-simplestreams\"
    }
  ],
  \"templates\": [
    {
      \"os-version\": \"net.cirros-cloud:standard:0.3:powerpc\",
      \"full-name\": \"cirros-0.3.4-powerpc\",
      \"arch\": \"powerpc\",
      \"size\": 17145856,
      \"aliases\": [
        \"cirros-0.3.4-powerpc\"
      ],
      \"hidden\": false
    },
    {
      \"os-version\": \"net.cirros-cloud:standard:0.3:x86_64\",
      \"full-name\": \"cirros-0.3.4-x86_64\",
      \"arch\": \"x86_64\",
      \"size\": 13287936,
      \"aliases\": [
        \"cirros-0.3.4-x86_64\"
      ],
      \"hidden\": false
    },
    {
      \"os-version\": \"net.cirros-cloud:standard:0.3:i386\",
      \"full-name\": \"cirros-0.3.4-i386\",
      \"arch\": \"i386\",
      \"size\": 12506112,
      \"aliases\": [
        \"cirros-0.3.4-i386\"
      ],
      \"hidden\": false
    }
  ]
}" ]; then
    echo "$0: unexpected --list --format json output:"
    echo "$json_list"
    exit 1
fi
