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

# https://bugzilla.redhat.com/show_bug.cgi?id=811649
# Test filenames containing a variety of characters.

set -e

$TEST_FUNCTIONS
skip_if_skipped

declare -a filenames
filenames[0]=' '
filenames[1]=','
filenames[2]='='
filenames[3]='水'
filenames[4]='-'
filenames[5]='-hda'
filenames[6]=':'
filenames[7]='http:'
filenames[8]='file:'
filenames[9]='raw:'

rm -f -- rhbz811649.img "${filenames[@]}"

guestfish sparse rhbz811649.img 10M

for f in "${filenames[@]}"; do
    ln -- rhbz811649.img "$f"
    guestfish <<EOF
add "$f" format:raw
run
EOF
done

rm -- rhbz811649.img "${filenames[@]}"
