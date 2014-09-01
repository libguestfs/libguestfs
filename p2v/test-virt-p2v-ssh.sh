#!/bin/bash -
# Copyright (C) 2014 Red Hat Inc.
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

# This is an ssh substitute used by test-virt-p2v.sh.

TEMP=`getopt \
        -o 'l:No:p:R:' \
        -- "$@"`
if [ $? != 0 ]; then
    echo "$0: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        # Regular arguments that we can just ignore.
        -N)
            shift
            ;;
        -l|-o|-p)
            shift 2
            ;;

        # ssh -R 0:localhost:<port> (port forwarding).  Don't actually
        # port forward, just return the original port number here so that
        # the conversion process connects directly to qemu-nbd.
        -R)
            arg="$2"
            port="$(echo $arg | awk -F: '{print $3}')"
            echo "Allocated port" $port "for remote forward"
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

# Now run the interactive shell.
exec bash
