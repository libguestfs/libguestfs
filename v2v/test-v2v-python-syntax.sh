#!/bin/bash -
# libguestfs
# Copyright (C) 2018 Red Hat Inc.
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

# Files to check.
files="rhv-upload-createvm.py rhv-upload-plugin.py rhv-upload-precheck.py"

# Base version of Python.
python=python

# Checks the files are syntactically correct, but not very much else.
for f in $files; do
    $python -m py_compile $f
done

# Checks the files correspond to PEP8 coding style.
# https://www.python.org/dev/peps/pep-0008/
if $python-pep8 --version >/dev/null 2>&1; then
    for f in $files; do
        # Ignore:
        # E226 missing whitespace around arithmetic operator
        # E251 unexpected spaces around keyword / parameter equals
        # E302 expected 2 blank lines, found 1
        $python-pep8 --ignore=E226,E251,E302 $f
    done
fi
