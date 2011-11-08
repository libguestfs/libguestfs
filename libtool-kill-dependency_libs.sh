#!/bin/bash -
# libtool-kill-dependency_libs.sh
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

# Run libtool as normal, then kill the dependency_libs line in the .la
# file.  Otherwise libtool will add DT_NEEDED entries for dependencies
# of libguestfs to all the other binaries, which is NOT helpful
# behaviour.

set -e

# Find the -o option.  The precise name of this option is full of
# magic for libtool so we cannot change it here, which is what we'd
# like to do.  Unfortunately this introduces a short race for parallel
# makes but there's not much we can do about that.
declare -a args
i=0

while [ $# -gt 0 ]; do
    case "$1" in
        -o)
            output="$2"
            args[$i]="$1"
            ((++i))
            args[$i]="$2"
            ((++i))
            shift 2;;
        *)
            args[$i]="$1";
            ((++i))
            shift;;
    esac
done

# Run libtool as normal.
#echo "${args[@]}"
"${args[@]}"

if [ -n "$output" ]; then
    mv "$output" "$output.tmp"

    # Remove dependency_libs from output.
    sed "s/^dependency_libs=.*/dependency_libs=''/" < "$output.tmp" > "$output"
    chmod --reference="$output.tmp" "$output"
    rm "$output.tmp"
fi
