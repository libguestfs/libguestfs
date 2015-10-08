# libguestfs
# Copyright (C) 2009-2015 Red Hat Inc.
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

if HAVE_FUSE

TESTS = test-parallel-mount-local

TESTS_ENVIRONMENT = $(top_builddir)/run --test $(VG)

check_PROGRAMS = $(TESTS)

test_parallel_mount_local_SOURCES = \
	test-parallel-mount-local.c \
	../../df/estimate-max-threads.c \
	../../df/estimate-max-threads.h
test_parallel_mount_local_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/df
test_parallel_mount_local_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(FUSE_CFLAGS)
test_parallel_mount_local_LDADD = \
	$(FUSE_LIBS) \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

endif
