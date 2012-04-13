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
export LANG=C

declare -a filenames
filenames[0]=' '
filenames[1]=','
filenames[2]='='
filenames[3]='水'
filenames[4]='-'
filenames[5]='-hda'
#filenames[6]=':'     # a future version of qemu may allow colon
#filenames[7]='http:'
#filenames[8]='file:'
#filenames[9]='raw:'

rm -f -- test1.img "${filenames[@]}"

truncate -s 10M test1.img

for f in "${filenames[@]}"; do
    ln -- test1.img "$f"
    ../../fish/guestfish <<EOF
add "$f"
run
EOF
done

rm -f -- test1.img "${filenames[@]}"
