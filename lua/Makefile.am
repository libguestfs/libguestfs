# libguestfs Lua bindings
# Copyright (C) 2012 Red Hat Inc.
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

lualibdir = $(libdir)/lua/$(LUA_VERSION)

generator_built = \
	bindtests.lua \
	lua-guestfs.c

EXTRA_DIST = \
	$(generator_built) \
	run-bindtests

CLEANFILES += \
	guestfs.so

if HAVE_LUA

# Libtool forces us to use 'libluaguestfs.so' instead of the desired
# name 'guestfs.so'.  However we'll rename it in the install hook.
# Cannot use 'noinst' here as that prevents the shared library from
# being built at all.
lualib_LTLIBRARIES = libluaguestfs.la
libluaguestfs_la_SOURCES = lua-guestfs.c

libluaguestfs_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include

libluaguestfs_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LUA_CFLAGS)

libluaguestfs_la_LIBADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	../gnulib/lib/libgnu.la

libluaguestfs_la_LDFLAGS = -avoid-version -shared

# Hack so we can run without installing.
noinst_DATA = guestfs.so
guestfs.so: libluaguestfs.la
	ln -sf .libs/libluaguestfs.so $@

# Tests.
TESTS_ENVIRONMENT = LC_ALL=C $(top_builddir)/run --test
TESTS = \
	run-bindtests \
	tests/010-load.lua \
	tests/015-globals.lua \
	tests/020-create.lua \
	tests/025-create-flags.lua \
	tests/027-create-multiple.lua \
	tests/030-config.lua \
	tests/070-optargs.lua \
	tests/400-events.lua \
	tests/900-errors.lua

if ENABLE_APPLIANCE
TESTS += \
	tests/050-lvcreate.lua \
	tests/060-readdir.lua \
	tests/400-progress.lua
endif

EXTRA_DIST += \
	tests/010-load.lua \
	tests/015-globals.lua \
	tests/020-create.lua \
	tests/025-create-flags.lua \
	tests/027-create-multiple.lua \
	tests/030-config.lua \
	tests/050-lvcreate.lua \
	tests/060-readdir.lua \
	tests/070-optargs.lua \
	tests/400-events.lua \
	tests/400-progress.lua \
	tests/900-errors.lua

# Run the tests under valgrind.
# This doesn't work.  Because Lua dlcloses the library on exit, the
# stack traces contain no useful information.  The only way to make
# this work would be to patch Lua or fix valgrind.
# https://bugs.kde.org/show_bug.cgi?id=79362
# http://valgrind.org/docs/manual/faq.html#faq.unhelpful
#check-valgrind:
#	$(MAKE) VG="@VG@" check

# Custom install rule.
install-data-hook:
	mkdir -p $(DESTDIR)$(lualibdir)
	mv $(DESTDIR)$(lualibdir)/libluaguestfs.so $(DESTDIR)$(lualibdir)/guestfs.so

endif
