#!/bin/bash -
# libguestfs
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

# Regression test for:
# https://bugzilla.redhat.com/show_bug.cgi?id=578407
# prefix '-' in sub-command isn't handled by guestfish in remote control mode
# Reported by Qixiang Wan.

set -e

guestfish=../fish/guestfish

# Start remote guestfish.
eval `$guestfish --listen 2>/dev/null`

# This should succeed.
$guestfish --remote version > /dev/null

# This command will fail (because appliance not launched), but
# prefixing with '-' should make remote guestfish ignore the failure.
$guestfish --remote -- -lvs

# Remote guestfish should still be running.
$guestfish --remote version > /dev/null
$guestfish --remote exit

# Try some other command line argument tests which are related the fix.
$guestfish -- version : -lvs : version > /dev/null 2>&1
