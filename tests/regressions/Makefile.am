# libguestfs
# Copyright (C) 2009-2018 Red Hat Inc.
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
	rhbz503169c13.sh \
	rhbz557655.sh \
	rhbz557655-expected.stdout \
	rhbz557655-expected.stderr \
	rhbz563450.sh \
	rhbz563450b.sh \
	rhbz576879.sh \
	rhbz578407.sh \
	rhbz580246.sh \
	rhbz602997.sh \
	rhbz690819.sh \
	rhbz727178.sh \
	rhbz789960.sh \
	rhbz811649.sh \
	rhbz895904.sh \
	rhbz909624.sh \
	rhbz957772.sh \
	rhbz975797.sh \
	rhbz1001875.sh \
	rhbz1011907-1165785.sh \
	rhbz1044014.sh \
	rhbz1044014.in \
	rhbz1044014.xml \
	rhbz1054761.sh \
	rhbz1091803.sh \
	rhbz1174551.sh \
	rhbz1175196.sh \
	rhbz1232192.sh \
	rhbz1232192.xml \
	rhbz1285847.sh \
	rhbz1370424.sh \
	rhbz1370424.xml \
	rhbz1477623.sh \
	test-noexec-stack.pl

TESTS = \
	rhbz501893 \
	rhbz503169c13.sh \
	rhbz557655.sh \
	rhbz563450.sh \
	rhbz563450b.sh \
	rhbz576879.sh \
	rhbz578407.sh \
	rhbz580246.sh \
	rhbz602997.sh \
	rhbz690819.sh \
	rhbz789960.sh \
	rhbz790721 \
	rhbz811649.sh \
	rhbz895904.sh \
	rhbz914931 \
	rhbz957772.sh \
	rhbz975797.sh \
	rhbz1001875.sh \
	rhbz1054761.sh \
	rhbz1055452 \
	rhbz1091803.sh \
	rhbz1011907-1165785.sh \
	rhbz1174551.sh \
	rhbz1175196.sh \
	rhbz1232192.sh \
	rhbz1285847.sh \
	rhbz1370424.sh \
	rhbz1477623.sh \
	test-big-heap \
	test-noexec-stack.pl \
	$(SLOW_TESTS)

if HAVE_LIBVIRT
TESTS += rhbz1044014.sh
endif

tests_not_run = \
	rhbz727178.sh

TESTS_ENVIRONMENT = \
	NOEXEC_CHECK="$(top_builddir)/lib/.libs/libguestfs.so $(top_builddir)/daemon/guestfsd" \
	$(top_builddir)/run --test

check_PROGRAMS = \
	rhbz501893 \
	rhbz790721 \
	rhbz914931 \
	rhbz1055452 \
	test-big-heap

rhbz501893_SOURCES = rhbz501893.c
rhbz501893_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
rhbz501893_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz501893_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

rhbz790721_SOURCES = rhbz790721.c
rhbz790721_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
rhbz790721_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz790721_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

rhbz914931_SOURCES = rhbz914931.c
rhbz914931_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-DGUESTFS_PRIVATE=1
rhbz914931_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz914931_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(LTLIBINTL) \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

rhbz1055452_SOURCES = rhbz1055452.c
rhbz1055452_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
rhbz1055452_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz1055452_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

test_big_heap_SOURCES = test-big-heap.c
test_big_heap_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
test_big_heap_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_big_heap_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

SLOW_TESTS = \
	rhbz909624.sh

check-slow:
	$(MAKE) check TESTS="$(CHECK_SLOW)" SLOW=1
