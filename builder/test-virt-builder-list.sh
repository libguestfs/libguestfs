#!/bin/bash -
# libguestfs virt-builder test script
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

# Test the virt-builder --list [--long] options.

export LANG=C
set -e

abs_builddir=$(pwd)

export XDG_CONFIG_HOME=
export XDG_CONFIG_DIRS="$abs_builddir/test-config"

short_list=$($VG virt-builder --no-check-signature --no-cache --list)

if [ "$short_list" != "phony-debian             x86_64     Phony Debian
phony-fedora             x86_64     Phony Fedora
phony-fedora-qcow2       x86_64     Phony Fedora qcow2
phony-fedora-qcow2-uncompressed x86_64     Phony Fedora qcow2 uncompressed
phony-fedora-no-format   x86_64     Phony Fedora
phony-ubuntu             x86_64     Phony Ubuntu
phony-windows            x86_64     Phony Windows" ]; then
    echo "$0: unexpected --list output:"
    echo "$short_list"
    exit 1
fi

long_list=$(virt-builder --no-check-signature --no-cache --list --long)

if [ "$long_list" != "Source URI: file://$abs_builddir/test-index

os-version:              phony-debian
Full name:               Phony Debian
Architecture:            x86_64
Minimum/default size:    512.0M

Notes:

Phony Debian look-alike used for testing.

os-version:              phony-fedora
Full name:               Phony Fedora
Architecture:            x86_64
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-qcow2
Full name:               Phony Fedora qcow2
Architecture:            x86_64
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-qcow2-uncompressed
Full name:               Phony Fedora qcow2 uncompressed
Architecture:            x86_64
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-no-format
Full name:               Phony Fedora
Architecture:            x86_64
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-ubuntu
Full name:               Phony Ubuntu
Architecture:            x86_64
Minimum/default size:    512.0M

Notes:

Phony Ubuntu look-alike used for testing.

os-version:              phony-windows
Full name:               Phony Windows
Architecture:            x86_64
Minimum/default size:    512.0M

Notes:

Phony Windows look-alike used for testing." ]; then
    echo "$0: unexpected --list --long output:"
    echo "$long_list"
    exit 1
fi

json_list=$(virt-builder --no-check-signature --no-cache --list --list-format json)

if [ "$json_list" != "{
  \"version\": 1,
  \"sources\": [
    {
      \"uri\": \"file://$abs_builddir/test-index\"
    }
  ],
  \"templates\": [
    {
      \"os-version\": \"phony-debian\",
      \"full-name\": \"Phony Debian\",
      \"arch\": \"x86_64\",
      \"size\": 536870912,
      \"notes\": {
        \"C\": \"Phony Debian look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-fedora\",
      \"full-name\": \"Phony Fedora\",
      \"arch\": \"x86_64\",
      \"size\": 1073741824,
      \"notes\": {
        \"C\": \"Phony Fedora look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-fedora-qcow2\",
      \"full-name\": \"Phony Fedora qcow2\",
      \"arch\": \"x86_64\",
      \"size\": 1073741824,
      \"notes\": {
        \"C\": \"Phony Fedora look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-fedora-qcow2-uncompressed\",
      \"full-name\": \"Phony Fedora qcow2 uncompressed\",
      \"arch\": \"x86_64\",
      \"size\": 1073741824,
      \"notes\": {
        \"C\": \"Phony Fedora look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-fedora-no-format\",
      \"full-name\": \"Phony Fedora\",
      \"arch\": \"x86_64\",
      \"size\": 1073741824,
      \"notes\": {
        \"C\": \"Phony Fedora look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-ubuntu\",
      \"full-name\": \"Phony Ubuntu\",
      \"arch\": \"x86_64\",
      \"size\": 536870912,
      \"notes\": {
        \"C\": \"Phony Ubuntu look-alike used for testing.\"
      },
      \"hidden\": false
    },
    {
      \"os-version\": \"phony-windows\",
      \"full-name\": \"Phony Windows\",
      \"arch\": \"x86_64\",
      \"size\": 536870912,
      \"notes\": {
        \"C\": \"Phony Windows look-alike used for testing.\"
      },
      \"hidden\": false
    }
  ]
}" ]; then
    echo "$0: unexpected --list --format json output:"
    echo "$json_list"
    exit 1
fi
