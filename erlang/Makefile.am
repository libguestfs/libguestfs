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
	guestfs.erl \
	erl-guestfs.c

EXTRA_DIST = \
	$(generator_built) \
	README

if HAVE_ERLANG

erlang_bindir = $(libdir)/erlang/lib/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/ebin

erlang_bin_DATA = guestfs.beam

guestfs.beam: guestfs.erl
	$(ERLC) +debug_info $^

bin_PROGRAMS = erl-guestfs

erl_guestfs_SOURCES = erl-guestfs.c erl-guestfs-proto.c

erl_guestfs_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-I$(ERLANG_LIB_DIR_erl_interface)/include \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

erl_guestfs_LDADD = \
	$(ERLANG_LIB_DIR_erl_interface)/lib/liberl_interface.a \
	$(ERLANG_LIB_DIR_erl_interface)/lib/libei.a \
	-lpthread \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

endif
