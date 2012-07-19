# libguestfs virt-df
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
	README \
	test-virt-df.sh \
	virt-df.pod

CLEANFILES = stamp-virt-df.pod

bin_PROGRAMS = virt-df

SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/domain.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c

virt_df_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-df.h \
	domains.c \
	df.c \
	main.c \
	output.c

virt_df_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBVIRT_CFLAGS)

virt_df_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la \
	$(LIBVIRT_LIBS) \
	-lm

# Manual pages and HTML files for the website.
man_MANS = virt-df.1
noinst_DATA = $(top_builddir)/html/virt-df.1.html

virt-df.1 $(top_builddir)/html/virt-df.1.html: stamp-virt-df.pod

stamp-virt-df.pod: virt-df.pod
	$(PODWRAPPER) \
	  --man virt-df.1 \
	  --html $(top_builddir)/html/virt-df.1.html \
	  $<
	touch $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	$(top_builddir)/run

if ENABLE_APPLIANCE
TESTS = test-virt-df.sh
endif ENABLE_APPLIANCE
