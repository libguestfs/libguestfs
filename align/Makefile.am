# libguestfs virt alignment tools
# Copyright (C) 2011 Red Hat Inc.
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
	test-virt-alignment-scan.sh \
	test-virt-alignment-scan-docs.sh \
	test-virt-alignment-scan-guests.sh \
	virt-alignment-scan.pod

bin_PROGRAMS = virt-alignment-scan

virt_alignment_scan_SOURCES = \
	scan.c

virt_alignment_scan_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/parallel -I$(top_builddir)/common/parallel \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\"

virt_alignment_scan_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBVIRT_CFLAGS)

virt_alignment_scan_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/parallel/libparallel.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la \
	-lm

# Manual pages and HTML files for the website.
man_MANS = virt-alignment-scan.1
noinst_DATA = $(top_builddir)/website/virt-alignment-scan.1.html

virt-alignment-scan.1 $(top_builddir)/website/virt-alignment-scan.1.html: stamp-virt-alignment-scan.pod

stamp-virt-alignment-scan.pod: virt-alignment-scan.pod
	$(PODWRAPPER) \
	  --man virt-alignment-scan.1 \
	  --html $(top_builddir)/website/virt-alignment-scan.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-alignment-scan-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-alignment-scan.sh

if HAVE_LIBVIRT
TESTS += \
	test-virt-alignment-scan-guests.sh
endif
endif

check-valgrind:
	$(MAKE) VG="@VG@" check
