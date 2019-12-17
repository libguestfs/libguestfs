#!/bin/bash -
# libguestfs
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

$top_srcdir/podcheck.pl "$srcdir/virt-cat.pod" virt-cat \
                        --path $top_srcdir/common/options
$top_srcdir/podcheck.pl "$srcdir/virt-filesystems.pod" virt-filesystems \
                        --path $top_srcdir/common/options
$top_srcdir/podcheck.pl "$srcdir/virt-log.pod" virt-log \
                        --path $top_srcdir/common/options
$top_srcdir/podcheck.pl "$srcdir/virt-ls.pod" virt-ls \
                        --path $top_srcdir/common/options \
                        --ignore=--checksums,--extra-stat,--time,--uid
$top_srcdir/podcheck.pl "$srcdir/virt-tail.pod" virt-tail \
                        --path $top_srcdir/common/options
