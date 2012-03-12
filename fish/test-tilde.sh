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

# Test guestfish tilde expansion.
# RHBZ#617440 guestfish: fails to tilde expand '~' when the $HOME env is unset
# RHBZ#511372 guestfish doesn't understand '~' in filenames
# and multiple other fixes to tilde handling.

set -e

# Don't rely on $HOME being set when this script is called.
HOME=$(pwd)
export HOME

if [ `echo 'echo ~' | ./guestfish` != "$HOME" ]; then
    echo "$0: failed: did not expand ~ correctly"
    exit 1
fi

if [ `echo 'echo ~/foo' | ./guestfish` != "$HOME/foo" ]; then
    echo "$0: failed: did not expand ~/foo correctly"
    exit 1
fi

# We can be reasonably sure that the root user will always exist and
# should have a home directory.
root="$(echo ~root)"

if [ `echo 'echo ~root' | ./guestfish` != "$root" ]; then
    echo "$0: failed: did not expand ~root correctly"
    exit 1
fi

if [ `echo 'echo ~root/foo' | ./guestfish` != "$root/foo" ]; then
    echo "$0: failed: did not expand ~root/foo correctly"
    exit 1
fi

# RHBZ#617440
unset HOME
home="$(echo ~)"

if [ `echo 'echo ~' | ./guestfish` != "$home" ]; then
    echo "$0: failed: did not expand ~ correctly when \$HOME unset"
    exit 1
fi

if [ `echo 'echo ~/foo' | ./guestfish` != "$home/foo" ]; then
    echo "$0: failed: did not expand ~/foo correctly when \$HOME unset"
    exit 1
fi

# Setting $HOME to pwd above causes guestfish to create a history
# file.  Remove it.
rm -f .guestfish
