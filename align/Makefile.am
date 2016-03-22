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
	test-virt-alignment-scan-guests.sh \
	virt-alignment-scan.pod

CLEANFILES = \
	stamp-virt-alignment-scan.pod \
	virt-alignment-scan.1

bin_PROGRAMS = virt-alignment-scan

SHARED_SOURCE_FILES = \
	../df/domains.c \
	../df/domains.h \
	../df/estimate-max-threads.c \
	../df/estimate-max-threads.h \
	../df/parallel.c \
	../df/parallel.h \
	../fish/config.c \
	../fish/domain.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/uri.h \
	../fish/uri.c

virt_alignment_scan_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	scan.c

virt_alignment_scan_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/df \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\"

virt_alignment_scan_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBVIRT_CFLAGS)

virt_alignment_scan_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
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

TESTS =

if ENABLE_APPLIANCE
TESTS += \
	test-virt-alignment-scan.sh \
	test-virt-alignment-scan-guests.sh
endif

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check
