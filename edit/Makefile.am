# libguestfs virt-edit
# Copyright (C) 2009-2011 Red Hat Inc.
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
	test-virt-edit.sh \
	virt-edit.pod

CLEANFILES = stamp-virt-edit.pod

bin_PROGRAMS = virt-edit

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_edit_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-edit.c

virt_edit_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(LIBCONFIG_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_edit_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-edit.1
noinst_DATA = $(top_builddir)/html/virt-edit.1.html

virt-edit.1 $(top_builddir)/html/virt-edit.1.html: stamp-virt-edit.pod

stamp-virt-edit.pod: virt-edit.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-edit.1 \
	  --html $(top_builddir)/html/virt-edit.1.html \
	  $<
	touch $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir)

TESTS = test-virt-edit.sh
