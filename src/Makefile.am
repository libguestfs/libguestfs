# libguestfs
# Copyright (C) 2010 Red Hat Inc.
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

CLEANFILES = stamp-guestfs.pod

generator_built = \
	guestfs_protocol.x \
	guestfs.h \
	guestfs-internal-actions.h \
	actions.c \
	bindtests.c \
	errnostring_gperf.gperf \
	errnostring.c \
	errnostring.h \
	guestfs-actions.pod \
	guestfs-availability.pod \
	guestfs-structs.pod \
	libguestfs.syms

BUILT_SOURCES = \
	$(generator_built) \
	guestfs_protocol.c \
	guestfs_protocol.h \
	errnostring_gperf.c

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	MAX_PROC_NR \
	libguestfs.3 \
	guestfs.pod \
	api-support/added \
	api-support/README \
	api-support/update-from-tarballs.sh

include_HEADERS = guestfs.h

lib_LTLIBRARIES = libguestfs.la

# This convenience library is solely to compile its generated sources with
# custom flags.
libprotocol_la_SOURCES = guestfs_protocol.c  guestfs_protocol.h
libprotocol_la_CFLAGS = -Wall -Wno-unused -fno-strict-aliasing

# Build the errnostring perfect hash code.  The generated code has lots
# of warnings so we must compile it in a separate mini-library.
liberrnostring_la_SOURCES = \
	errnostring_gperf.c \
	errnostring.h \
	errnostring.c
liberrnostring_la_CFLAGS =

errnostring_gperf.c: errnostring_gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@

# From the libtool info file, with comments:
#
# |  1. Start with version information of `0:0:0' for each libtool library.
# |
# |  2. Update the version information only immediately before a public
# |     release of your software.  More frequent updates are unnecessary,
# |     and only guarantee that the current interface number gets larger
# |     faster.
# |
# |  3. If the library source code has changed at all since the last
# |     update, then increment REVISION (`C:R:A' becomes `C:r+1:A').
#
# [So it seems like we should always update the middle 'R' field
# for any release.]
#
# |  4. If any interfaces have been added, removed, or changed since the
# |     last update, increment CURRENT, and set REVISION to 0.
# |
# |  5. If any interfaces have been added since the last public release,
# |     then increment AGE.
#
# [These two rules seem to mean that if any change is made to the
# generator, we should increment C and A, and set R to 0, so:
# C+1:0:A+1.]
#
# |  6. If any interfaces have been removed since the last public release,
# |     then set AGE to 0.
#
# [Our ABI guarantee means we won't remove interfaces except in
# very exceptional circumstances.]
#
# The maximum proc number (see guestfs_protocol.x:guestfs_procedure) is
# a mostly accurate stand-in for C & A in rules 5 & 6, so we use that.  It
# is always incremented when we add a new appliance interface, and easy to
# calculate.
#
# The middle number is hard to increment-and-reset as described in rules
# 4 & 5, so for the moment it is always set to 0.
#
# Note that this scheme means the real library version will always be
# 'libguestfs.so.0.$(MAX_PROC_NR).0'.
libguestfs_la_LDFLAGS = -version-info $(MAX_PROC_NR):0:$(MAX_PROC_NR)

libguestfs_la_LDFLAGS += $(VERSION_SCRIPT_FLAGS)$(srcdir)/libguestfs.syms

libguestfs_la_SOURCES = \
	guestfs.c \
	guestfs.h \
	guestfs-internal.h \
	guestfs_protocol.h \
	gettext.h \
	actions.c \
	appliance.c \
	bindtests.c \
	dbdump.c \
	events.c \
	filearch.c \
	inspect.c \
	inspect_apps.c \
	inspect_fs.c \
	inspect_fs_cd.c \
	inspect_fs_unix.c \
	inspect_fs_windows.c \
	inspect_icon.c \
	launch.c \
	listfs.c \
	match.c \
	proto.c \
	virt.c \
	libguestfs.syms

libguestfs_la_LIBADD = \
	$(HIVEX_LIBS) $(AUGEAS_LIBS) $(PCRE_LIBS) $(MAGIC_LIBS) \
	$(LIBVIRT_LIBS) $(LIBXML2_LIBS) \
	../gnulib/lib/libgnu.la \
	$(GETADDRINFO_LIB) \
	$(HOSTENT_LIB) \
	$(INET_NTOP_LIB) \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LIBINTL) \
	$(LTLIBTHREAD) \
	$(SERVENT_LIB)

# Make libguestfs include the convenience libraries.
noinst_LTLIBRARIES = liberrnostring.la libprotocol.la
libguestfs_la_LIBADD += liberrnostring.la libprotocol.la

libguestfs_la_CFLAGS = \
  -DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"' \
  -DGUESTFS_WARN_DEPRECATED=1 \
  $(HIVEX_CFLAGS) $(AUGEAS_CFLAGS) $(PCRE_CFLAGS) \
  $(LIBVIRT_CFLAGS) $(LIBXML2_CFLAGS) \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

libguestfs_la_CPPFLAGS = -I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib

if HAVE_RPCGEN
guestfs_protocol.c: guestfs_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) -c -o $@-t $(srcdir)/$<
	sed 's,\.\./\.\./src/,,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

guestfs_protocol.h: guestfs_protocol.x
	rm -f $@-t
	$(RPCGEN) -h -o $@-t $(srcdir)/$<
	mv $@-t $@
endif

# Manual page.

man_MANS = guestfs.3 libguestfs.3
noinst_DATA = $(top_builddir)/html/guestfs.3.html

guestfs.3 $(top_builddir)/html/guestfs.3.html: stamp-guestfs.pod

stamp-guestfs.pod: guestfs.pod \
		guestfs-actions.pod \
		guestfs-availability.pod \
		guestfs-structs.pod
	$(top_builddir)/podwrapper.sh \
	  --section 3 \
	  --man guestfs.3 \
	  --html $(top_builddir)/html/guestfs.3.html \
	  --insert $(srcdir)/guestfs-actions.pod:@ACTIONS@ \
	  --insert $(srcdir)/guestfs-availability.pod:@AVAILABILITY@ \
	  --insert $(srcdir)/guestfs-structs.pod:@STRUCTS@ \
	  $<
	touch $@
