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

# NB. guestfs-actions.c is #include'd into guestfs.c, so it should not
# be listed as a source file.
EXTRA_DIST = guestfs-actions.c

EXTRA_DIST += guestfs_protocol.x \
	guestfs_protocol.c \
	guestfs_protocol.h

include_HEADERS = guestfs.h guestfs-actions.h guestfs-structs.h

lib_LTLIBRARIES = libguestfs.la

libguestfs_la_LDFLAGS = -version-info 0:0:0
libguestfs_la_SOURCES = \
	guestfs.c \
	guestfs.h \
	guestfs_protocol.c \
	guestfs_protocol.h \
	guestfs-actions.h

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