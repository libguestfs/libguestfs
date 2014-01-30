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

export VIRT_BUILDER_SOURCE=file://$abs_builddir/test-index

short_list=$($VG ./virt-builder --no-check-signature --no-cache --list)

if [ "$short_list" != "phony-debian             Phony Debian
phony-fedora             Phony Fedora
phony-fedora-qcow2       Phony Fedora qcow2
phony-fedora-qcow2-uncompressed Phony Fedora qcow2 uncompressed
phony-fedora-no-format   Phony Fedora
phony-ubuntu             Phony Ubuntu
phony-windows            Phony Windows" ]; then
    echo "$0: unexpected --list output:"
    echo "$short_list"
    exit 1
fi

long_list=$(./virt-builder --no-check-signature --no-cache --list --long)

if [ "$long_list" != "Source URI: $VIRT_BUILDER_SOURCE
Fingerprint: F777 4FB1 AD07 4A7E 8C87 67EA 9173 8F73 E1B7 68A0

os-version:              phony-debian
Full name:               Phony Debian
Minimum/default size:    512.0M

Notes:

Phony Debian look-alike used for testing.

os-version:              phony-fedora
Full name:               Phony Fedora
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-qcow2
Full name:               Phony Fedora qcow2
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-qcow2-uncompressed
Full name:               Phony Fedora qcow2 uncompressed
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-fedora-no-format
Full name:               Phony Fedora
Minimum/default size:    1.0G

Notes:

Phony Fedora look-alike used for testing.

os-version:              phony-ubuntu
Full name:               Phony Ubuntu
Minimum/default size:    512.0M

Notes:

Phony Ubuntu look-alike used for testing.

os-version:              phony-windows
Full name:               Phony Windows
Minimum/default size:    512.0M

Notes:

Phony Windows look-alike used for testing." ]; then
    echo "$0: unexpected --list --long output:"
    echo "$long_list"
    exit 1
fi

json_list=$(./virt-builder --no-check-signature --no-cache --list --list-format json)

if [ "$json_list" != "{
  \"version\": 1,
  \"sources\": [
  {
    \"uri\": \"$VIRT_BUILDER_SOURCE\",
    \"fingerprint\": \"F777 4FB1 AD07 4A7E 8C87 67EA 9173 8F73 E1B7 68A0\"
  }
  ],
  \"templates\": [
  {
    \"os-version\": \"phony-debian\",
    \"full-name\": \"Phony Debian\",
    \"size\": 536870912,
    \"notes\": {
      \"C\": \"Phony Debian look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-fedora\",
    \"full-name\": \"Phony Fedora\",
    \"size\": 1073741824,
    \"notes\": {
      \"C\": \"Phony Fedora look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-fedora-qcow2\",
    \"full-name\": \"Phony Fedora qcow2\",
    \"size\": 1073741824,
    \"notes\": {
      \"C\": \"Phony Fedora look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-fedora-qcow2-uncompressed\",
    \"full-name\": \"Phony Fedora qcow2 uncompressed\",
    \"size\": 1073741824,
    \"notes\": {
      \"C\": \"Phony Fedora look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-fedora-no-format\",
    \"full-name\": \"Phony Fedora\",
    \"size\": 1073741824,
    \"notes\": {
      \"C\": \"Phony Fedora look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-ubuntu\",
    \"full-name\": \"Phony Ubuntu\",
    \"size\": 536870912,
    \"notes\": {
      \"C\": \"Phony Ubuntu look-alike used for testing.\"
    },
    \"hidden\": false
  },
  {
    \"os-version\": \"phony-windows\",
    \"full-name\": \"Phony Windows\",
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
