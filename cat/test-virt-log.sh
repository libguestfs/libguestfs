#!/bin/bash -
# libguestfs
# Copyright (C) 2009-2016 Red Hat Inc.
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

export LANG=C
set -e

can_handle ()
{
    fn=$(basename $1)
    case "$fn" in
    fedora.img)
        guestfish -a /dev/null run : available journal
        ;;
    *)
        return 0
        ;;
    esac
}

tmpfile=`mktemp`

# Read out the log files from the image using virt-log.
for f in ../test-data/phony-guests/{fedora,debian,ubuntu}.img; do
    echo "Trying $f ..."
    if [ ! -s "$f" ]; then
        echo "SKIP: empty file"
        echo
        continue
    fi
    if ! can_handle "$f"; then
        echo "SKIP: cannot handle $f"
        echo
        continue
    fi
    $VG virt-log --format=raw -a "$f" &> $tmpfile
    cat $tmpfile
    echo
done

rm -f $tmpfile
