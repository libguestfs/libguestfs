# libguestfs
# Copyright (C) 2009-2019 Red Hat Inc.
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

# liboptions.la contains guestfish code which is used in other
# C tools for options parsing and a few other things
noinst_LTLIBRARIES = liboptions.la

liboptions_la_SOURCES = \
	config.c \
	decrypt.c \
	display-options.h \
	display-options.c \
	domain.c \
	inspect.c \
	keys.c \
	options.h \
	options.c \
	uri.h \
	uri.c
liboptions_la_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib
liboptions_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBXML2_CFLAGS)
liboptions_la_LIBADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBCONFIG_LIBS) \
	$(LIBXML2_LIBS) \
	$(LTLIBINTL)
