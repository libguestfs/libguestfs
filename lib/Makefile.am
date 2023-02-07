# libguestfs
# Copyright (C) 2010-2023 Red Hat Inc.
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

noinst_PROGRAMS =

generator_built = \
	guestfs-internal-actions.h \
	actions-0.c \
	actions-1.c \
	actions-2.c \
	actions-3.c \
	actions-4.c \
	actions-5.c \
	actions-6.c \
	actions-variants.c \
	bindtests.c \
	event-string.c \
	guestfs-actions.pod \
	guestfs-availability.pod \
	guestfs-structs.pod \
	libguestfs.syms \
	structs-compare.c \
	structs-copy.c \
	structs-free.c

BUILT_SOURCES = \
	$(generator_built)

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	MAX_PROC_NR \
	libguestfs.pc.in \
	local/libguestfs.pc.in \
	guestfs.pod

lib_LTLIBRARIES = libguestfs.la

libguestfs_la_SOURCES = \
	../common/errnostring/errnostring.h \
	../common/protocol/guestfs_protocol.h \
	../common/qemuopts/qemuopts.h \
	../common/utils/guestfs-utils.h \
	../common/structs/structs-cleanups.h \
	../include/guestfs.h \
	guestfs-internal.h \
	guestfs-internal-all.h \
	actions-0.c \
	actions-1.c \
	actions-2.c \
	actions-3.c \
	actions-4.c \
	actions-5.c \
	actions-6.c \
	actions-support.c \
	actions-variants.c \
	alloc.c \
	appliance.c \
	appliance-cpu.c \
	appliance-kcmdline.c \
	appliance-uefi.c \
	available.c \
	bindtests.c \
	canonical-name.c \
	command.c \
	conn-socket.c \
	copy-in-out.c \
	create.c \
	drives.c \
	errors.c \
	event-string.c \
	events.c \
	file.c \
	fuse.c \
	guid.c \
	handle.c \
	info.c \
	inspect-apps.c \
	inspect-icon.c \
	inspect-osinfo.c \
	journal.c \
	launch.c \
	launch-direct.c \
	launch-libvirt.c \
	libvirt-auth.c \
	libvirt-domain.c \
	lpj.c \
	match.c \
	mountable.c \
	private-data.c \
	proto.c \
	qemu.c \
	readdir.c \
	rescue.c \
	stringsbuf.c \
	structs-compare.c \
	structs-copy.c \
	structs-free.c \
	tmpdirs.c \
	tsk.c \
	uefi.c \
	umask.c \
	version.c \
	wait.c \
	whole-file.c \
	yara.c \
	libguestfs.syms

libguestfs_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/common/errnostring -I$(top_builddir)/common/errnostring \
	-I$(top_srcdir)/common/protocol -I$(top_builddir)/common/protocol \
	-I$(top_srcdir)/common/qemuopts -I$(top_builddir)/common/qemuopts \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/include

libguestfs_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS) \
	$(GCC_VISIBILITY_HIDDEN) \
	$(PCRE2_CFLAGS) \
	$(LIBVIRT_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(JANSSON_CFLAGS)

libguestfs_la_LIBADD = \
	../common/errnostring/liberrnostring.la \
	../common/protocol/libprotocol.la \
	../common/qemuopts/libqemuopts.la \
	../common/structs/libstructs.la \
	../common/utils/libutils.la \
	$(PCRE2_LIBS) \
	$(LIBVIRT_LIBS) $(LIBXML2_LIBS) \
	$(SELINUX_LIBS) \
	$(JANSSON_LIBS) \
	../gnulib/lib/libgnu.la \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LTLIBINTL) \
	$(LTLIBTHREAD) \
	$(RPC_LIBS)

# Force libtool to name the library 'libguestfs.so.0.$(MAX_PROC_NR).0'.
# Include the version script to limit which symbols are exported.
libguestfs_la_LDFLAGS = \
	-version-info $(MAX_PROC_NR):0:$(MAX_PROC_NR) \
	$(VERSION_SCRIPT_FLAGS)$(srcdir)/libguestfs.syms

if HAVE_FUSE
# XXX Unfortunately FUSE_CFLAGS defines _FILE_OFFSET_BITS=64.
libguestfs_la_CFLAGS += $(FUSE_CFLAGS)
libguestfs_la_LIBADD += $(FUSE_LIBS)
endif

if HAVE_LIBVIRT
# Small utility to check for a needed libvirt version;
# to be used in shell/script-based tests.
noinst_PROGRAMS += libvirt-is-version

libvirt_is_version_SOURCES = libvirt-is-version.c

libvirt_is_version_LDADD = \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL)

libvirt_is_version_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\"

libvirt_is_version_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS)
endif

# Tests: main tests are in tests/c-api.  Here we just have some
# internal tests of utility functions.

TESTS_ENVIRONMENT = $(top_builddir)/run --test
LOG_COMPILER = $(VG)

TESTS = unit-tests
check_PROGRAMS = unit-tests

unit_tests_SOURCES = unit-tests.c
unit_tests_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_srcdir)/include -I.
unit_tests_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS)
# We have to link this to libguestfs, but because we want to test
# non-exported functions we have to link with the objects not the
# library.
unit_tests_LDADD = \
	../common/structs/libstructs.la \
	../common/utils/libutils.la \
	$(libguestfs_la_OBJECTS) \
	$(libguestfs_la_LIBADD)

check-valgrind:
	$(MAKE) VG="@VG@" check

# Pkgconfig.

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libguestfs.pc

# Manual page.

man_MANS = guestfs.3 libguestfs.3
noinst_DATA = $(top_builddir)/website/guestfs.3.html

guestfs.3 $(top_builddir)/website/guestfs.3.html: stamp-guestfs.pod

stamp-guestfs.pod: guestfs.pod \
		guestfs-actions.pod \
		guestfs-availability.pod \
		guestfs-structs.pod
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs.3 \
	  --html $(top_builddir)/website/guestfs.3.html \
	  --insert $(srcdir)/guestfs-actions.pod:__ACTIONS__ \
	  --insert $(srcdir)/guestfs-availability.pod:__AVAILABILITY__ \
	  --insert $(srcdir)/guestfs-structs.pod:__STRUCTS__ \
	  --license LGPLv2+ \
	  $<
	touch $@

# The only reason we have to generate this from the Makefile is
# because the global CLEANFILES rule deletes it.
libguestfs.3: Makefile.am
	rm -f $@ $@-t
	echo '.so man3/guestfs.3' > $@-t
	mv $@-t $@
