#!/bin/bash -
# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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
#
# Rebuild the autotools environment.

set -e
set -v

# Ensure that whenever we pull in a gnulib update or otherwise change to a
# different version (i.e., when switching branches), we also rerun ./bootstrap.
curr_status=.git-module-status
t=$(git submodule status|sed 's/^[ +-]//;s/ .*//')
if test "$t" = "$(cat $curr_status 2>/dev/null)"; then
    : # good, it's up to date
else
    echo running bootstrap...
    ./bootstrap && echo "$t" > $curr_status
fi

CONFIGUREDIR=.

# Run configure in BUILDDIR if it's set
if [ ! -z "$BUILDDIR" ]; then
    mkdir -p $BUILDDIR
    cd $BUILDDIR

    CONFIGUREDIR=..
fi

# If no arguments were specified and configure has run before, use the previous
# arguments
if test $# == 0 && test -x ./config.status; then
    ./config.status --recheck
else
    $CONFIGUREDIR/configure "$@"
fi
