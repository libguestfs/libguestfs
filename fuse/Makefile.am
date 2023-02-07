# libguestfs
# Copyright (C) 2009-2023 Red Hat Inc.
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
	guestmount.pod \
	guestunmount.pod \
	test-docs.sh \
	test-fuse-umount-race.sh \
	test-guestunmount-not-mounted.sh

if HAVE_FUSE

bin_PROGRAMS = \
	guestmount \
	guestunmount

# guestmount

guestmount_SOURCES = \
	guestmount.c

guestmount_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

guestmount_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(FUSE_CFLAGS)

guestmount_LDADD = \
	$(FUSE_LIBS) \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBCONFIG_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# guestunmount

guestunmount_SOURCES = \
	guestunmount.c

guestunmount_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

guestunmount_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

guestunmount_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Documentation.

man_MANS = \
	guestmount.1 \
	guestunmount.1
noinst_DATA = \
	$(top_builddir)/website/guestmount.1.html \
	$(top_builddir)/website/guestunmount.1.html

guestmount.1 $(top_builddir)/website/guestmount.1.html: stamp-guestmount.pod

stamp-guestmount.pod: guestmount.pod
	$(PODWRAPPER) \
	  --man guestmount.1 \
	  --html $(top_builddir)/website/guestmount.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning ro-option \
	  $<
	touch $@

guestunmount.1 $(top_builddir)/website/guestunmount.1.html: stamp-guestunmount.pod

stamp-guestunmount.pod: guestunmount.pod
	$(PODWRAPPER) \
	  --man guestunmount.1 \
	  --html $(top_builddir)/website/guestunmount.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS = \
	test-docs.sh \
	test-guestunmount-fd \
	test-guestunmount-not-mounted.sh

if ENABLE_APPLIANCE
TESTS += \
	test-fuse \
	test-fuse-umount-race.sh \
	test-guestmount-fd
endif ENABLE_APPLIANCE

TESTS_ENVIRONMENT = \
	top_builddir=.. \
	$(top_builddir)/run --test

check_PROGRAMS = test-fuse test-guestmount-fd test-guestunmount-fd

test_fuse_SOURCES = \
	test-fuse.c

test_fuse_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

test_fuse_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

test_fuse_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(ACL_LIBS) \
	../gnulib/lib/libgnu.la

test_guestmount_fd_SOURCES = \
	test-guestmount-fd.c

test_guestmount_fd_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

test_guestmount_fd_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

test_guestmount_fd_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

test_guestunmount_fd_SOURCES = \
	test-guestunmount-fd.c

test_guestunmount_fd_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

test_guestunmount_fd_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

test_guestunmount_fd_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

endif HAVE_FUSE
