# libguestfs virt-cat, virt-filesystems and virt-ls.
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
	test-virt-cat.sh \
	virt-cat.pod \
	test-virt-filesystems.sh \
	virt-filesystems.pod \
	test-virt-ls.sh \
	virt-ls.pod

CLEANFILES = stamp-virt-cat.pod stamp-virt-ls.pod stamp-virt-filesystems.pod

bin_PROGRAMS = virt-cat virt-filesystems virt-ls

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_cat_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-cat.c

virt_cat_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS)

virt_cat_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

virt_filesystems_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-filesystems.c

virt_filesystems_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS)

virt_filesystems_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

virt_ls_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-ls.c

virt_ls_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS)

virt_ls_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-cat.1 virt-filesystems.1 virt-ls.1

noinst_DATA = \
	$(top_builddir)/html/virt-cat.1.html \
	$(top_builddir)/html/virt-filesystems.1.html \
	$(top_builddir)/html/virt-ls.1.html

virt-cat.1 $(top_builddir)/html/virt-cat.1.html: stamp-virt-cat.pod

stamp-virt-cat.pod: virt-cat.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-cat.1 \
	  --html $(top_builddir)/html/virt-cat.1.html \
	  $<
	touch $@

virt-ls.1 $(top_builddir)/html/virt-ls.1.html: stamp-virt-ls.pod

stamp-virt-ls.pod: virt-ls.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-ls.1 \
	  --html $(top_builddir)/html/virt-ls.1.html \
	  $<
	touch $@

virt-filesystems.1 $(top_builddir)/html/virt-filesystems.1.html: stamp-virt-filesystems.pod

stamp-virt-filesystems.pod: virt-filesystems.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-filesystems.1 \
	  --html $(top_builddir)/html/virt-filesystems.1.html \
	  $<
	touch $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	$(top_builddir)/run

if ENABLE_APPLIANCE
TESTS = test-virt-cat.sh test-virt-filesystems.sh test-virt-ls.sh
endif ENABLE_APPLIANCE
