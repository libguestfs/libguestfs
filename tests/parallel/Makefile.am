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

TESTS = $(SLOW_TESTS)
TESTS_ENVIRONMENT = $(top_builddir)/run --test

SLOW_TESTS = test-parallel

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
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

#check-valgrind:
#	$(MAKE) VG="@VG@" TESTS="test-parallel" check

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1
