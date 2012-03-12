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

# Test guestfish events.

set -e

rm -f test.out

./guestfish -a /dev/null <<'EOF' | grep -v get_verbose | grep -v get_trace | grep -v 'library .*0x' > test.out
trace true

event ev1 * "echo $EVENT $@"
event ev1 * "echo $EVENT $@"
event ev2 * "echo $EVENT $@"

list-events
delete-event ev1
list-events
reopen
list-events

event ev1 close,subprocess_quit "echo $EVENT $@"
event ev2 close,subprocess_quit "echo $EVENT $@"
event ev3 launch "echo $EVENT $@"

list-events
-delete-event ev4
list-events
delete-event ev1
list-events
delete-event ev3
list-events

EOF

if [ "$(cat test.out)" != '"ev1" (0): *: echo $EVENT $@
"ev1" (1): *: echo $EVENT $@
"ev2" (2): *: echo $EVENT $@
"ev2" (2): *: echo $EVENT $@
enter get_autosync
trace get_autosync
trace get_autosync = 1
enter get_path
trace get_path
trace get_path = "'$LIBGUESTFS_PATH'"
enter get_pgroup
trace get_pgroup
trace get_pgroup = 0
trace close
close
"ev1" (0): close,subprocess_quit: echo $EVENT $@
"ev2" (1): close,subprocess_quit: echo $EVENT $@
"ev3" (2): launch_done: echo $EVENT $@
"ev1" (0): close,subprocess_quit: echo $EVENT $@
"ev2" (1): close,subprocess_quit: echo $EVENT $@
"ev3" (2): launch_done: echo $EVENT $@
"ev2" (1): close,subprocess_quit: echo $EVENT $@
"ev3" (2): launch_done: echo $EVENT $@
"ev2" (1): close,subprocess_quit: echo $EVENT $@
close' ]; then
    echo "$0: unexpected output from guestfish events"
    cat test.out
    exit 1
fi

rm test.out
