# libguestfs
# Copyright (C) 2010-2012 Red Hat Inc.
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

CLEANFILES = stamp-guestfs.pod

generator_built = \
	guestfs_protocol.x \
	guestfs.h \
	guestfs-internal-actions.h \
	guestfs-internal-frontend-cleanups.h \
	actions-0.c \
	actions-1.c \
	actions-2.c \
	actions-3.c \
	actions-4.c \
	actions-5.c \
	actions-6.c \
	actions-variants.c \
	bindtests.c \
	errnostring-gperf.gperf \
	errnostring.c \
	errnostring.h \
	event-string.c \
	guestfs-actions.pod \
	guestfs-availability.pod \
	guestfs-structs.pod \
	libguestfs.syms \
	structs-cleanup.c \
	structs-compare.c \
	structs-copy.c \
	structs-free.c

BUILT_SOURCES = \
	$(generator_built) \
	guestfs_protocol.c \
	guestfs_protocol.h \
	errnostring-gperf.c

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	MAX_PROC_NR \
	libguestfs.3 \
	libguestfs.pc.in \
	guestfs.pod \
	api-support/added \
	api-support/README \
	api-support/update-from-tarballs.sh

include_HEADERS = guestfs.h

lib_LTLIBRARIES = libguestfs.la

libguestfs_la_SOURCES = \
	guestfs.h \
	guestfs-internal.h \
	guestfs-internal-all.h \
	guestfs-internal-frontend.h \
	guestfs-internal-frontend-cleanups.h \
	guestfs_protocol.h \
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
	bindtests.c \
	canonical-name.c \
	command.c \
	conn-socket.c \
	create.c \
	dbdump.c \
	drives.c \
	errors.c \
	event-string.c \
	events.c \
	file.c \
	filearch.c \
	fuse.c \
	guid.c \
	handle.c \
	info.c \
	inspect.c \
	inspect-apps.c \
	inspect-fs.c \
	inspect-fs-cd.c \
	inspect-fs-unix.c \
	inspect-fs-windows.c \
	inspect-icon.c \
	journal.c \
	launch.c \
	launch-direct.c \
	launch-libvirt.c \
	launch-uml.c \
	launch-unix.c \
	libvirt-auth.c \
	libvirt-domain.c \
	listfs.c \
	lpj.c \
	match.c \
	osinfo.c \
	private-data.c \
	proto.c \
	stringsbuf.c \
	structs-compare.c \
	structs-copy.c \
	structs-free.c \
	tmpdirs.c \
	libguestfs.syms

libguestfs_la_CPPFLAGS = \
	-DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"' \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-DGUESTFS_PRIVATE=1 \
	-DLIBOSINFO_DB_PATH='"$(datadir)/libosinfo/db"' \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib

libguestfs_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(GCC_VISIBILITY_HIDDEN) \
	$(PCRE_CFLAGS) \
	$(LIBVIRT_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(YAJL_CFLAGS)

libguestfs_la_LIBADD = \
	liberrnostring.la \
	libprotocol.la \
	libutils.la \
	$(PCRE_LIBS) $(MAGIC_LIBS) \
	$(LIBVIRT_LIBS) $(LIBXML2_LIBS) \
	$(SELINUX_LIBS) \
	$(YAJL_LIBS) \
	../gnulib/lib/libgnu.la \
	$(GETADDRINFO_LIB) \
	$(HOSTENT_LIB) \
	$(INET_NTOP_LIB) \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LTLIBINTL) \
	$(LTLIBTHREAD) \
	$(LTLIBICONV) \
	$(SERVENT_LIB)

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

# Convenience libraries.
noinst_LTLIBRARIES = liberrnostring.la libprotocol.la libutils.la

# Build the errnostring perfect hash code.  The generated code has lots
# of warnings so we must compile it in a separate mini-library.
liberrnostring_la_SOURCES = \
	errnostring-gperf.c \
	errnostring.h \
	errnostring.c
liberrnostring_la_CFLAGS = $(GCC_VISIBILITY_HIDDEN)

errnostring-gperf.c: errnostring-gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@

# This convenience library is solely to compile its generated sources with
# custom flags.
libprotocol_la_SOURCES = guestfs_protocol.c  guestfs_protocol.h
libprotocol_la_CFLAGS = \
	-Wall -Wno-unused -fno-strict-aliasing $(GCC_VISIBILITY_HIDDEN)

if HAVE_RPCGEN
RPCGEN_DEFS =
if HAVE_XDR_U_INT64_T
RPCGEN_DEFS += -DHAVE_XDR_U_INT64_T=1
else
if HAVE_XDR_UINT64_T
RPCGEN_DEFS += -DHAVE_XDR_UINT64_T=1
endif
endif

guestfs_protocol.c: guestfs_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) $(RPCGEN_DEFS) -c -o $@-t $<
	$(SED) 's,\.\./\(\.\./\)*src,.,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

guestfs_protocol.h: guestfs_protocol.x
	rm -f $@-t
	$(RPCGEN) $(RPCGEN_DEFS) -h -o $@-t $<
	mv $@-t $@
endif

# libutils.la contains code outside libguestfs which is also
# included in tools and bindings.
libutils_la_SOURCES = \
	cleanup.c \
	structs-cleanup.c \
	utils.c
libutils_la_CPPFLAGS = $(libguestfs_la_CPPFLAGS)
libutils_la_CFLAGS = $(libguestfs_la_CFLAGS)

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
# internal tests of utility functions.  Note we don't just test what's
# in utils.c, we can test other functions as well here.

TESTS_ENVIRONMENT = $(top_builddir)/run --test $(VG)

TESTS = test-utils
check_PROGRAMS = test-utils

test_utils_SOURCES = test-utils.c
test_utils_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I.
test_utils_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_utils_LDADD = \
	libguestfs_la-guid.lo \
	libutils.la \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

check-valgrind:
	$(MAKE) VG="@VG@" check

# Pkgconfig.

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libguestfs.pc

# Manual page.

man_MANS = guestfs.3 libguestfs.3
noinst_DATA = $(top_builddir)/html/guestfs.3.html

guestfs.3 $(top_builddir)/html/guestfs.3.html: stamp-guestfs.pod

stamp-guestfs.pod: guestfs.pod \
		guestfs-actions.pod \
		guestfs-availability.pod \
		guestfs-structs.pod
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs.3 \
	  --html $(top_builddir)/html/guestfs.3.html \
	  --insert $(srcdir)/guestfs-actions.pod:__ACTIONS__ \
	  --insert $(srcdir)/guestfs-availability.pod:__AVAILABILITY__ \
	  --insert $(srcdir)/guestfs-structs.pod:__STRUCTS__ \
	  --license LGPLv2+ \
	  $<
	touch $@
