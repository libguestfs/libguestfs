# libguestfs virt-inspector
# Copyright (C) 2009-2012 Red Hat Inc.
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

EXAMPLE_XML = \
	example-debian.xml \
	example-fedora.xml \
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
	virt-inspector.pod

CLEANFILES = stamp-virt-inspector.pod

docdir = @docdir@
dist_doc_DATA = \
	virt-inspector.rng \
	$(EXAMPLE_XML)

if HAVE_LIBXML2

bin_PROGRAMS = virt-inspector

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_inspector_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-inspector.c

virt_inspector_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(LIBXML2_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_inspector_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-inspector.1
noinst_DATA = $(top_builddir)/html/virt-inspector.1.html

virt-inspector.1 $(top_builddir)/html/virt-inspector.1.html: stamp-virt-inspector.pod

stamp-virt-inspector.pod: virt-inspector.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-inspector.1 \
	  --html $(top_builddir)/html/virt-inspector.1.html \
	  $<
	touch $@

if HAVE_XMLLINT

TESTS = $(EXAMPLE_XML)
TESTS_ENVIRONMENT = $(XMLLINT) --noout --relaxng $(srcdir)/virt-inspector.rng

endif

endif

# These rules require virt-inspector so there is no good time that we
# can run them.  Instead you can run them by hand.

example-debian.xml:
	rm -f $@ $@-t
	../run $(builddir)/virt-inspector ../tests/guests/debian.img > $@-t
	mv $@-t $@
example-fedora.xml:
	rm -f $@ $@-t
	../run $(builddir)/virt-inspector ../tests/guests/fedora.img > $@-t
	mv $@-t $@
example-ubuntu.xml:
	rm -f $@ $@-t
	../run $(builddir)/virt-inspector ../tests/guests/ubuntu.img > $@-t
	mv $@-t $@
example-windows.xml:
	rm -f $@ $@-t
	../run $(builddir)/virt-inspector ../tests/guests/windows.img | \
	    fgrep -v '<uuid>' > $@-t
	mv $@-t $@
