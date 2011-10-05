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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	virt-alignment-scan.pod

CLEANFILES = stamp-virt-alignment-scan.pod

bin_PROGRAMS = virt-alignment-scan

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_alignment_scan_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	scan.c

virt_alignment_scan_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBVIRT_CFLAGS)

virt_alignment_scan_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la \
	$(LIBVIRT_LIBS) \
	-lm

# Manual pages and HTML files for the website.
man_MANS = virt-alignment-scan.1
noinst_DATA = $(top_builddir)/html/virt-alignment-scan.1.html

virt-alignment-scan.1 $(top_builddir)/html/virt-alignment-scan.1.html: stamp-virt-alignment-scan.pod

stamp-virt-alignment-scan.pod: virt-alignment-scan.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-alignment-scan.1 \
	  --html $(top_builddir)/html/virt-alignment-scan.1.html \
	  $<
	touch $@

# Tests.

# random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

# TESTS_ENVIRONMENT = \
# 	MALLOC_PERTURB_=$(random_val) \
# 	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
# 	LIBGUESTFS_PATH=$(top_builddir)/appliance \
# 	TMPDIR=$(top_builddir)

# TESTS = test-virt-alignment-scan.sh
