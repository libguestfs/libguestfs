#!/bin/bash -
# libguestfs
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# https://bugzilla.redhat.com/show_bug.cgi?id=727178
# Check that all binaries that we ship in the appliance contain
# corresponding libraries.

set -e
export LANG=C

guestfish=../../fish/guestfish
output=rhbz727178.output

rm -f binaries.tmp $output

eval `$guestfish -a /dev/null --listen`

$guestfish --remote -- run
$guestfish --remote -- debug binaries "" |
    grep -E '^/(bin|sbin|usr/bin|usr/sbin|usr/libexec)/' > binaries.tmp

while read ex; do
    echo ldd $ex
    $guestfish --remote -- -debug ldd $ex
done < binaries.tmp > $output

if grep -E '\bnot found\b|undefined symbol' $output; then
    echo "Error: some libraries are missing from the appliance."
    echo "See" $(pwd)/$output
    echo "for the complete output."
    exit 1
fi

rm binaries.tmp $output
