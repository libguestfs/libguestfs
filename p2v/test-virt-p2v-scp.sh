#!/bin/bash -
# Copyright (C) 2014-2016 Red Hat Inc.
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

# This is an scp substitute used by test-virt-p2v.sh.

TEMP=`getopt \
        -o 'o:P:' \
        -- "$@"`
if [ $? != 0 ]; then
    echo "$0: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        # Regular arguments that we can just ignore.
        -o|-P)
            shift 2
            ;;

        --)
            shift
	    break
            ;;
        *)
            echo "$0: internal error ($1)"
            exit 1
            ;;
    esac
done

# Hopefully there are two arguments left, the source (local) file
# and a remote file of the form user@server:remote.
if [ $# -ne 2 ]; then
    echo "$0: incorrect number of arguments found:" "$@"
    exit 1
fi

local="$1"
remote="$(echo $2 | awk -F: '{print $2}')"

# Use the copy command.
exec cp "$local" "$remote"
