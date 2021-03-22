#!/bin/bash -
# libguestfs
# Copyright (C) 2020 Red Hat Inc.
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

# Gather the list of Python sources.
# (-u is passed to to sort to avoid duplicates in case builddir==srcdir)
files="$(find "$srcdir" . -name '*.py' | sort -u)"

# Ignore E128 ("continuation line under-indented for visual indent") which
# was broken in
# commit 66a5913462a84399bd9790b736814620371a80f8 ("python: Add type hints")
# and is hard to fix.
$PYCODESTYLE --ignore=E128 $files
