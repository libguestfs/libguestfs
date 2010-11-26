# libguestfs virt-rescue
# Copyright (C) 2010 Red Hat Inc.
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
	run-rescue-locally \
	virt-rescue.pod

CLEANFILES = stamp-virt-rescue.pod

bin_PROGRAMS = virt-rescue

SHARED_SOURCE_FILES = \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_rescue_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-rescue.c

virt_rescue_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_rescue_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-rescue.1
noinst_DATA = $(top_builddir)/html/virt-rescue.1.html

virt-rescue.1 $(top_builddir)/html/virt-rescue.1.html: stamp-virt-rescue.pod

stamp-virt-rescue.pod: virt-rescue.pod
	$(top_srcdir)/podwrapper.sh \
	  --man virt-rescue.1 \
	  --html $(top_builddir)/html/virt-rescue.1.html \
	  $<
	touch $@

# Build a partly-static binary (for the binary distribution).

virt-rescue.static$(EXEEXT): $(virt_rescue_OBJECTS) $(virt_rescue_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_rescue_LINK) $(virt_rescue_OBJECTS) -static $(virt_rescue_LDADD) $(virt_rescue_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm
