# libguestfs virt-edit
# Copyright (C) 2009-2018 Red Hat Inc.
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
	test-virt-edit.sh \
	test-virt-edit-docs.sh \
	virt-edit.pod

bin_PROGRAMS = virt-edit

virt_edit_SOURCES = \
	edit.c

virt_edit_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/common/edit -I$(top_builddir)/common/edit \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/windows -I$(top_builddir)/common/windows \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_edit_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

virt_edit_LDADD = \
	$(top_builddir)/common/edit/libedit.la \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/windows/libwindows.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-edit.1
noinst_DATA = $(top_builddir)/website/virt-edit.1.html

virt-edit.1 $(top_builddir)/website/virt-edit.1.html: stamp-virt-edit.pod

stamp-virt-edit.pod: virt-edit.pod
	$(PODWRAPPER) \
	  --man virt-edit.1 \
	  --html $(top_builddir)/website/virt-edit.1.html \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-edit-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-edit.sh
endif ENABLE_APPLIANCE
