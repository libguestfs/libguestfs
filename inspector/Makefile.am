# libguestfs virt-inspector
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

example_xml = \
	example-debian.xml \
	example-fedora.xml \
	example-rhel-6.xml \
	example-ubuntu.xml \
	example-windows.xml

EXTRA_DIST = \
	expected-debian.img.xml \
	expected-fedora.img.xml \
	expected-fedora-luks.img.xml \
	expected-ubuntu.img.xml \
	expected-archlinux.img.xml \
	expected-coreos.img.xml \
	expected-windows.img.xml \
	test-virt-inspector.sh \
	test-virt-inspector-luks.sh \
	test-virt-inspector-docs.sh \
	test-xmllint.sh.in \
	virt-inspector.pod

docdir = @docdir@
dist_doc_DATA = \
	virt-inspector.rng \
	$(example_xml)

bin_PROGRAMS = virt-inspector

virt_inspector_SOURCES = \
	inspector.c

virt_inspector_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_inspector_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

virt_inspector_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-inspector.1
noinst_DATA = $(top_builddir)/website/virt-inspector.1.html

virt-inspector.1 $(top_builddir)/website/virt-inspector.1.html: stamp-virt-inspector.pod

stamp-virt-inspector.pod: virt-inspector.pod
	$(PODWRAPPER) \
	  --man virt-inspector.1 \
	  --html $(top_builddir)/website/virt-inspector.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-inspector-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-inspector.sh \
	test-virt-inspector-luks.sh
endif ENABLE_APPLIANCE
if HAVE_XMLLINT
TESTS += test-xmllint.sh
endif

check-valgrind:
	$(MAKE) TESTS="test-virt-inspector.sh test-virt-inspector-luks.sh" VG="@VG@" check

check-valgrind-local-guests:
	for g in $(GUESTS); do \
	  $(top_builddir)/run --test @VG@ virt-inspector -c "$(libvirt_ro_uri)" -d "$$g" || exit $$?; \
	done
