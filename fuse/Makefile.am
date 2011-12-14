# libguestfs
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

EXTRA_DIST = guestmount.pod test-fuse.sh

CLEANFILES = stamp-guestmount.pod

if HAVE_FUSE

bin_PROGRAMS = guestmount

# These source files (all related to option parsing) are shared
# between guestfish and guestmount.
SHARED_SOURCE_FILES = \
	../fish/config.c \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

guestmount_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	guestmount.c \
	guestmount.h

guestmount_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(FUSE_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

guestmount_LDADD = \
	$(FUSE_LIBS) -lulockmgr \
	$(LIBCONFIG_LIBS) \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

# Documentation.

man_MANS = guestmount.1
noinst_DATA = $(top_builddir)/html/guestmount.1.html

guestmount.1 $(top_builddir)/html/guestmount.1.html: stamp-guestmount.pod

stamp-guestmount.pod: guestmount.pod
	$(top_builddir)/podwrapper.sh \
	  --man guestmount.1 \
	  --html $(top_builddir)/html/guestmount.1.html \
	  $<
	touch $@

# Tests.

if ENABLE_APPLIANCE
TESTS = test-fuse.sh
endif ENABLE_APPLIANCE
TESTS_ENVIRONMENT = \
	top_builddir=..

endif HAVE_FUSE
