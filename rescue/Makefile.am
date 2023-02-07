# libguestfs virt-rescue
# Copyright (C) 2010-2023 Red Hat Inc.
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
	test-virt-rescue-docs.sh \
	test-virt-rescue-suggest.sh \
	virt-rescue.pod

bin_PROGRAMS = virt-rescue

virt_rescue_SOURCES = \
	escape.c \
	rescue.c \
	rescue.h \
	suggest.c

virt_rescue_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DGUESTFS_PRIVATE=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/windows -I$(top_builddir)/common/windows \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_rescue_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

virt_rescue_LDADD = \
	$(top_builddir)/common/windows/libwindows.la \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBCONFIG_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-rescue.1
noinst_DATA = $(top_builddir)/website/virt-rescue.1.html

virt-rescue.1 $(top_builddir)/website/virt-rescue.1.html: stamp-virt-rescue.pod

stamp-virt-rescue.pod: virt-rescue.pod
	$(PODWRAPPER) \
	  --man virt-rescue.1 \
	  --html $(top_builddir)/website/virt-rescue.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning ro-option \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-rescue-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-rescue.pl \
	test-virt-rescue-suggest.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) TESTS="test-virt-rescue-suggest.sh" VG="@VG@" check
