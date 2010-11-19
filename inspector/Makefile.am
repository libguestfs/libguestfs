# libguestfs virt-inspector
# Copyright (C) 2009-2010 Red Hat Inc.
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

EXAMPLE_XML = \
	example-debian.xml \
	example-fedora.xml \
	example-ubuntu.xml \
	example-windows.xml

EXTRA_DIST = \
	run-inspector-locally \
	virt-inspector.pod

docdir = @docdir@
dist_doc_DATA = \
	virt-inspector.rng \
	$(EXAMPLE_XML)

if HAVE_LIBXML2

bin_PROGRAMS = virt-inspector

SHARED_SOURCE_FILES = \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_inspector_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-inspector.c

virt_inspector_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(LIBXML2_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_inspector_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-inspector.1

noinst_DATA = \
	$(top_builddir)/html/virt-inspector.1.html

virt-inspector.1: virt-inspector.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-inspector.1.html: virt-inspector
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --title 'virt-inspector, display OS version, kernel, drivers, mount points, applications, etc. in a virtual machine' \
	  --htmldir html \
	  --outfile html/virt-inspector.1.html \
	  inspector/$<

if HAVE_XMLLINT

TESTS = $(EXAMPLE_XML)
TESTS_ENVIRONMENT = $(XMLLINT) --noout --relaxng virt-inspector.rng

endif

endif

# These rules require virt-inspector so there is no good time that we
# can run them.  Instead you can run them by hand.

example-debian.xml:
	./run-inspector-locally ../images/debian.img > $@
example-fedora.xml:
	./run-inspector-locally ../images/fedora.img > $@
example-ubuntu.xml:
	./run-inspector-locally ../images/ubuntu.img > $@
example-windows.xml:
	./run-inspector-locally ../images/windows.img | fgrep -v '<uuid>' > $@

# Build a partly-static library (for the binary distribution).

virt-inspector.static$(EXEEXT): $(virt_inspector_OBJECTS) $(virt_inspector_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_inspector_LINK) $(virt_inspector_OBJECTS) -static $(virt_inspector_LDADD) $(virt_inspector_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm
