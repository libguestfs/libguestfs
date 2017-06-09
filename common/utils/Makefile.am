# libguestfs
# Copyright (C) 2017 Red Hat Inc.
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

noinst_LTLIBRARIES = libutils.la

libutils_la_SOURCES = \
	../../lib/guestfs.h \
	cleanups.c \
	cleanups.h \
	gnulib-cleanups.c \
	guestfs-utils.h \
	libxml2-cleanups.c \
	utils.c
libutils_la_CPPFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
libutils_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(GCC_VISIBILITY_HIDDEN) \
	$(LIBXML2_CFLAGS)
