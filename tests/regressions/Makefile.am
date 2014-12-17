# libguestfs
# Copyright (C) 2009-2014 Red Hat Inc.
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
	rhbz1044014.sh \
	rhbz1044014.in \
	rhbz1044014.xml \
	rhbz1054761.sh \
	rhbz1091803.sh \
	rhbz1175196.sh \
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
	rhbz1175196.sh \
	test-noexec-stack.pl

if HAVE_LIBVIRT
TESTS += rhbz1044014.sh
endif

tests_not_run = \
	rhbz727178.sh \
	rhbz909624.sh

TESTS_ENVIRONMENT = \
	NOEXEC_CHECK="$(top_builddir)/src/.libs/libguestfs.so $(top_builddir)/daemon/guestfsd" \
	$(top_builddir)/run --test

check_PROGRAMS = \
	rhbz501893 \
	rhbz790721 \
	rhbz914931 \
	rhbz1055452

rhbz501893_SOURCES = rhbz501893.c
rhbz501893_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
rhbz501893_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz501893_LDADD = \
	$(top_builddir)/src/libguestfs.la

rhbz790721_SOURCES = rhbz790721.c
rhbz790721_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
rhbz790721_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz790721_LDADD = \
	$(top_builddir)/src/libguestfs.la

rhbz914931_SOURCES = rhbz914931.c
rhbz914931_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-DGUESTFS_PRIVATE=1
rhbz914931_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz914931_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la

rhbz1055452_SOURCES = rhbz1055452.c
rhbz1055452_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-DGUESTFS_PRIVATE=1
rhbz1055452_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz1055452_LDADD = \
	$(top_builddir)/src/libguestfs.la

check-slow:
	$(MAKE) TESTS="rhbz909624.sh" check
