# libguestfs virt-inspector
# Copyright (C) 2009-2016 Red Hat Inc.
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
	example-windows.xml \
	example-debian-netinst-cd.xml \
	example-fedora-dvd.xml \
	example-fedora-netinst-cd.xml \
	example-rhel-6-dvd.xml \
	example-rhel-6-netinst-cd.xml \
	example-ubuntu-live-cd.xml \
	example-windows-2003-x64-cd.xml \
	example-windows-2003-x86-cd.xml \
	example-windows-xp-cd.xml

EXTRA_DIST = \
	expected-debian.img.xml \
	expected-fedora.img.xml \
	expected-ubuntu.img.xml \
	expected-archlinux.img.xml \
	expected-coreos.img.xml \
	expected-windows.img.xml \
	test-virt-inspector.sh \
	test-virt-inspector-docs.sh \
	test-xmllint.sh.in \
	virt-inspector.pod

CLEANFILES = \
	stamp-virt-inspector.pod \
	virt-inspector.1

docdir = @docdir@
dist_doc_DATA = \
	virt-inspector.rng \
	$(example_xml)

bin_PROGRAMS = virt-inspector

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/domain.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/uri.h \
	../fish/uri.c

virt_inspector_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	inspector.c

virt_inspector_CPPFLAGS = \
	-DCOMPILING_VIRT_INSPECTOR=1 \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_inspector_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBCONFIG_CFLAGS)

virt_inspector_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
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
	test-virt-inspector.sh
endif ENABLE_APPLIANCE
if HAVE_XMLLINT
TESTS += test-xmllint.sh
endif

check-valgrind:
	$(MAKE) TESTS="test-virt-inspector.sh" VG="$(top_builddir)/run @VG@" check

check-valgrind-local-guests:
	for g in $(GUESTS); do \
	  $(top_builddir)/run --test @VG@ virt-inspector -c "$(libvirt_ro_uri)" -d "$$g" || exit $$?; \
	done
