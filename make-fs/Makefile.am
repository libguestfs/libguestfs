# libguestfs virt-diff
# Copyright (C) 2010-2019 Red Hat Inc.
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
	test-virt-make-fs.sh \
	test-virt-make-fs-docs.sh \
	virt-make-fs.pod

bin_PROGRAMS = virt-make-fs

virt_make_fs_SOURCES = \
	make-fs.c

virt_make_fs_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_make_fs_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

virt_make_fs_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-make-fs.1

noinst_DATA = \
	$(top_builddir)/website/virt-make-fs.1.html

virt-make-fs.1 $(top_builddir)/website/virt-make-fs.1.html: stamp-virt-make-fs.pod

stamp-virt-make-fs.pod: virt-make-fs.pod
	$(PODWRAPPER) \
	  --man virt-make-fs.1 \
	  --html $(top_builddir)/website/virt-make-fs.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-make-fs-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-make-fs.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) VG="@VG@" check
