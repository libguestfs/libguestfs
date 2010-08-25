#!/bin/bash -
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# Written by Richard W.M. Jones <rjones@redhat.com>
#
# Take a dynamically linked ELF binary and relink it, maximizing the
# use of static libraries.
#
# Example:
#   binary foo
#            ---> dynamically links to libbar.so.0
#            ---> dynamically links to libzab.so.3
# If libbar.a is available, but there is no libzab.a, then we would
# end up with:
#   binary foo.static with libbar.a statically inside it
#            ---> still dynamically linking with libzab.so.3
#
# We need to have access to the original link command.  This script
# works by post-processing it to find the '-lbar' arguments, which are
# replaced sometimes by direct static library names.
#
# Therefore to use this, you have to add this rule to your
# Makefile.am:
#
# foo.static$(EXEEXT): $(foo_OBJECTS) $(foo_DEPENDENCIES)
#   relink-static.sh \
#   $(foo_LINK) $(foo_OBJECTS) -static $(foo_LDADD) $(foo_LIBS)

declare -a args

i=0
for arg; do
    case "$arg" in
    -l*)    # get just the library name (eg. "xml2")
            lib=${arg:2}
            # does a static version exist?
            for d in /usr/local/lib{64,} /usr/lib{64,} /lib{64,}; do
                path="$d/lib$lib.a"
                if [ -f "$path" ]; then
                    arg="$path"
                    break
                fi
            done
            ;;
    *.la)   # hack around libtool mess
            d=$(dirname "$arg")
            b=$(basename "$arg")
            b=${b:0:${#b}-3}
            if [ -f "$d/.libs/$b.a" ]; then
                arg="$d/.libs/$b.a"
            fi
            ;;
    *) ;;
    esac
    args[$i]="$arg"
    i=$(($i+1))
done

# Run the final command.
echo "${args[@]}"
"${args[@]}"
