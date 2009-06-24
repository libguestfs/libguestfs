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

EXTRA_DIST = guestfs_protocol.x \
	guestfs_protocol.c \
	guestfs_protocol.h \
	MAX_PROC_NR

EXTRA_DIST += generator.ml

include_HEADERS = guestfs.h guestfs-actions.h guestfs-structs.h

lib_LTLIBRARIES = libguestfs.la

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
libguestfs_la_SOURCES = \
	guestfs.c \
	guestfs.h \
	guestfs_protocol.c \
	guestfs_protocol.h \
	guestfs-actions.h \
	guestfs-actions.c \
	guestfs-bindtests.c \
	gettext.h

libguestfs_la_CFLAGS = -Wall -DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"'

if HAVE_RPCGEN
guestfs_protocol.c: guestfs_protocol.x
	rm -f $@-t
	$(RPCGEN) -c -o $@-t $<
	mv $@-t $@

guestfs_protocol.h: guestfs_protocol.x
	rm -f $@-t
	$(RPCGEN) -h -o $@-t $<
	mv $@-t $@
endif
