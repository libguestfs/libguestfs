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

# Test remote control of guestfish.

set -e

rm -f test.img

eval `../fish/guestfish --listen`

error=0

function check_echo {
    test=$1
    expected=$2

    local echo

    echo=$(../fish/guestfish --remote echo_daemon "$test")
    if [ "$echo" != "$expected" ]; then
        echo "Expected \"$expected\", got \"$echo\""
        error=1
    fi
}

../fish/guestfish --remote alloc test.img 10M
../fish/guestfish --remote run

check_echo "' '"            " "
check_echo "\'"             "'"
check_echo "'\''"           "'"
check_echo "'\' '"          "' "
check_echo "'\'foo\''"      "'foo'"
check_echo "foo' 'bar"      "foo bar"
check_echo "foo'  'bar"     "foo  bar"
check_echo "'foo' 'bar'"    "foo bar"
check_echo "'foo' "         "foo"
check_echo " 'foo'"         "foo"

../fish/guestfish --remote exit

rm -f test.img

exit $error
