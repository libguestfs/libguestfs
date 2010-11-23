# libguestfs virt-df
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
	README \
	run-df-locally \
	test-virt-df.sh \
	virt-df.pod

CLEANFILES = stamp-virt-df.pod

bin_PROGRAMS = virt-df

SHARED_SOURCE_FILES = \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_df_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-df.h \
	domains.c \
	df.c \
	main.c \
	output.c

virt_df_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_df_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la -lm

# Manual pages and HTML files for the website.
man_MANS = virt-df.1
noinst_DATA = $(top_builddir)/html/virt-df.1.html

virt-df.1 $(top_builddir)/html/virt-df.1.html: stamp-virt-df.pod

stamp-virt-df.pod: virt-df.pod
	$(top_srcdir)/podwrapper.sh \
	  --man virt-df.1 \
	  --html $(top_builddir)/html/virt-df.1.html \
	  $<
	touch $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance

TESTS = test-virt-df.sh

# Build a partly-static binary (for the binary distribution).

virt-df.static$(EXEEXT): $(virt_df_OBJECTS) $(virt_df_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_df_LINK) $(virt_df_OBJECTS) -static $(virt_df_LDADD) $(virt_df_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm
