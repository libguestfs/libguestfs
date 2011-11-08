# libguestfs
# Copyright (C) 2009-2011 Red Hat Inc.
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

EXTRA_DIST = libguestfs-test-tool.pod

CLEANFILES =

bin_PROGRAMS = libguestfs-test-tool
man_MANS = libguestfs-test-tool.1

libguestfs_test_tool_SOURCES = test-tool.c
libguestfs_test_tool_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
libguestfs_test_tool_LDADD = \
	$(top_builddir)/src/libguestfs.la

libguestfs-test-tool.1: libguestfs-test-tool.pod
	$(top_builddir)/podwrapper.sh \
	  --man $@ \
	  $<
