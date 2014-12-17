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

# Don't run this test by default.  However we have to have an empty
# TESTS rule otherwise you can't run the test from the command line
# using 'make TESTS=test-parallel check'
TESTS =
TESTS_ENVIRONMENT = $(top_builddir)/run --test

check_PROGRAMS = test-parallel

test_parallel_SOURCES = test-parallel.c
test_parallel_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_parallel_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_parallel_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

#check-valgrind:
#	$(MAKE) VG="$(top_builddir)/run @VG@" TESTS="test-parallel" check

check-slow:
	$(MAKE) TESTS="test-parallel" check
