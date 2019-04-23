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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	test-mountable-inspect.sh

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS=test-internal-parse-mountable test-mountable-inspect.sh
check_PROGRAMS = test-internal-parse-mountable

test_internal_parse_mountable_SOURCES = test-internal-parse-mountable.c
test_internal_parse_mountable_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
test_internal_parse_mountable_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_internal_parse_mountable_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la
