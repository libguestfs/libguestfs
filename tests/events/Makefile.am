# libguestfs
# Copyright (C) 2013-2017 Red Hat Inc.
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
	test-console-debug.pl \
	libvirt-auth.xml

TESTS_ENVIRONMENT = $(top_builddir)/run --test

check_PROGRAMS =

TESTS = test-console-debug.pl

if HAVE_LIBVIRT
TESTS += test-libvirt-auth-callbacks
check_PROGRAMS += test-libvirt-auth-callbacks

test_libvirt_auth_callbacks_SOURCES = test-libvirt-auth-callbacks.c
test_libvirt_auth_callbacks_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_libvirt_auth_callbacks_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS)
test_libvirt_auth_callbacks_LDADD = \
        $(top_builddir)/src/libutils.la \
        $(top_builddir)/src/libguestfs.la \
        $(LIBVIRT_LIBS) \
        $(LIBXML2_LIBS) \
        $(LTLIBINTL) \
        $(top_builddir)/gnulib/lib/libgnu.la
endif
