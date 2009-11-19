# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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

EXTRA_DIST = libguestfs-test-tool.pod

CLEANFILES =

bin_PROGRAMS = libguestfs-test-tool
libexec_PROGRAMS = libguestfs-test-tool-helper
man_MANS = libguestfs-test-tool.1

AM_CPPFLAGS = \
	-DDEFAULT_HELPER='"$(libexecdir)/libguestfs-test-tool-helper"'

libguestfs_test_tool_SOURCES = test-tool.c
libguestfs_test_tool_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-Wall
libguestfs_test_tool_LDADD = \
	$(top_builddir)/src/libguestfs.la

libguestfs_test_tool_helper_SOURCES = helper.c
libguestfs_test_tool_helper_LDFLAGS = -all-static

libguestfs-test-tool.1: libguestfs-test-tool.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@
