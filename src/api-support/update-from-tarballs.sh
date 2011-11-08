#!/bin/bash -
# libguestfs
# Copyright (C) 2010 Red Hat Inc.
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

if [ ! -f BUGS ]; then
    echo "You should run this script from the top source directory."
    exit 1
fi

set -e

cd src/api-support

tmpdir=$(mktemp -d)

website=$HOME/d/redhat/websites/libguestfs
tarballs="$website/download/1.*-*/libguestfs-*.tar.gz"

for t in $tarballs; do
    # libguestfs-x.y.z
    p=$(basename $t .tar.gz)
    # x.y.z
    v=$(echo $p | sed 's/^libguestfs-//')

    if [ $v != "1.2.0" -a $v != "1.3.0" -a ! -f $v ]; then
        rm -rf "$tmpdir/*"
        tar -C "$tmpdir" \
            -zxf $t $p/src/guestfs-actions.c $p/src/actions.c \
            $p/src/guestfs.c \
            2>/dev/null ||:

        f="$tmpdir/$p/src/guestfs-actions.c"
        if [ ! -f "$f" ]; then
            f="$tmpdir/$p/src/actions.c"
            if [ ! -f "$f" ]; then
                echo "$t does not contain actions file"
                exit 1
            fi
        fi

        grep -Eoh 'guestfs_[a-z0-9][_A-Za-z0-9]+' \
                "$f" $tmpdir/$p/src/guestfs.c |
            sort -u |
            grep -v '_ret$' |
            grep -v '_args$' |
            grep -v '^guestfs_free_' |
            grep -v '^guestfs_test0' |
            grep -v '^guestfs_message_error$' |
            grep -v '^guestfs_message_header$' > $v
    fi
done

rm -rf "$tmpdir"

# GNU ls sorts properly by version with the -v option and backwards by
# version with -vr.
rev_versions=$(ls -vr [01]*)
latest=$(ls -v [01]* | tail -1)

exec 5>added

# Get all the symbols from the latest version.
# We are implicitly assuming that symbols are not removed.  ABI
# guarantee should prevent that from happening.
symbols=$(<$latest)

previous=$latest
for v in $rev_versions; do
    next_symbols=
    for sym in $symbols; do
        # If symbol is missing from the file, that indicates it
        # was added in the previous file we checked ($previous).
        if ! egrep -sq \\b$sym\\b $v; then
            echo $sym $previous >&5
        else
            next_symbols="$next_symbols $sym"
        fi
    done
    symbols="$next_symbols"
    previous=$v
done

# Any remaining were added in the very first version.
for sym in $symbols; do
    echo $sym $previous >&5
done

# Close and sort the output by symbol name.
exec 5>&-
sort -o added added
