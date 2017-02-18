#!/bin/bash -
# libguestfs virt-v2v test script
# Copyright (C) 2016 Red Hat Inc.
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

# Test detection of duplicate --network and --bridge parameters.

set -e
set -x

$TEST_FUNCTIONS
skip_if_skipped

# We expect all of these to print an error.  NB: LANG=C is set.

virt-v2v -i disk -b b1 -b b1 |& grep "duplicate -b"
virt-v2v -i disk -n n1 -n n1 |& grep "duplicate -n"
virt-v2v -i disk -b b1 -n b1 -b b1 |& grep "duplicate -b"
virt-v2v -i disk -b b1 -n b1 -n b2 |& grep "duplicate -n"

virt-v2v -i disk -b b1:r1 -b b1:r2 |& grep "duplicate -b"
virt-v2v -i disk -n n1:r1 -n n1:r2 |& grep "duplicate -n"

# The -b and -n parameters are OK in these tests, but because we
# didn't specify a disk image name on the command line it will give
# a different error.

virt-v2v -i disk |& grep "expecting a disk image"
virt-v2v -i disk -b b1 |& grep "expecting a disk image"
virt-v2v -i disk -n n1 |& grep "expecting a disk image"
virt-v2v -i disk -b b1 -n n1 |& grep "expecting a disk image"
virt-v2v -i disk -b b1:r1 -b b2 -n n1:r1 -n n2 |& grep "expecting a disk image"
