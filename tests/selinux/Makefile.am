# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

# Test extended attributes and SELinux labelling, both using the API
# directly, and over FUSE.

include $(top_srcdir)/subdir-rules.mk

TESTS = \
	test-xattrs-direct.sh \
	test-selinux-direct.sh

if HAVE_FUSE
TESTS += \
	test-xattrs-fuse.sh \
	test-selinux-fuse.sh
endif

TESTS_ENVIRONMENT = $(top_builddir)/run --test

EXTRA_DIST = \
	run-test.pl \
	test-xattrs-direct.sh \
	test-xattrs-fuse.sh \
	test-selinux-direct.sh \
	test-selinux-fuse.sh
