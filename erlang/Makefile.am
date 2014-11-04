# libguestfs Erlang bindings
# Copyright (C) 2011 Red Hat Inc.
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

generator_built = \
	bindtests.erl \
	erl-guestfs.c \
	guestfs.erl

EXTRA_DIST = \
	$(generator_built) \
	run-bindtests \
	tests/*.erl \
	README

CLEANFILES = \
	$(erlang_bin_DATA) \
	$(bin_PROGRAMS)

if HAVE_ERLANG

erlang_bindir = $(ERLANG_LIB_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/ebin

erlang_bin_DATA = guestfs.beam

# In order for the tests to work on the local copy, we have to create
# a phony directory hierarchy:
#
# $(builddir)/erlang/libguestfs-$(VERSION)/ebin/guestfs.beam
#
# The ./run script will set $ERL_LIBS to point to $(builddir)/erlang.
# (See: http://www.erlang.org/doc/man/code.html)
guestfs.beam: guestfs.erl
	$(ERLC) +debug_info $^
	mkdir -p $(PACKAGE)-$(VERSION)/ebin
	cp $@ $(PACKAGE)-$(VERSION)/ebin

bin_PROGRAMS = erl-guestfs

erl_guestfs_SOURCES = erl-guestfs.c erl-guestfs-proto.c

erl_guestfs_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-I$(ERLANG_LIB_DIR_erl_interface)/include

erl_guestfs_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

erl_guestfs_LDADD = \
	$(ERLANG_LIB_DIR_erl_interface)/lib/liberl_interface.a \
	$(ERLANG_LIB_DIR_erl_interface)/lib/libei.a \
	-lpthread \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += \
	tests/010-load.erl \
	tests/030-config.erl \
	tests/050-lvcreate.erl \
	tests/060-readdir.erl \
	tests/070-optargs.erl
endif

endif
