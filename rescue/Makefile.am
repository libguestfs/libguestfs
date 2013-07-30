# libguestfs virt-rescue
# Copyright (C) 2010-2012 Red Hat Inc.
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
	test-virt-rescue.pl \
	virt-rescue.pod

CLEANFILES = stamp-virt-rescue.pod

bin_PROGRAMS = virt-rescue

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/domain.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/uri.h \
	../fish/uri.c

virt_rescue_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-rescue.c

virt_rescue_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_rescue_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(GPROF_CFLAGS) $(GCOV_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBXML2_CFLAGS)

virt_rescue_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-rescue.1
noinst_DATA = $(top_builddir)/html/virt-rescue.1.html

virt-rescue.1 $(top_builddir)/html/virt-rescue.1.html: stamp-virt-rescue.pod

stamp-virt-rescue.pod: virt-rescue.pod
	$(PODWRAPPER) \
	  --man virt-rescue.1 \
	  --html $(top_builddir)/html/virt-rescue.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = test-virt-rescue.pl
endif ENABLE_APPLIANCE
