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

bin_PROGRAMS = guestfish

EXTRA_DIST = \
	rc_protocol.x

CLEANFILES = rc_protocol.c rc_protocol.h

guestfish_SOURCES = \
	alloc.c \
	cmds.c \
	completion.c \
	destpaths.c \
	echo.c \
	edit.c \
	fish.c \
	fish.h \
	glob.c \
	lcd.c \
	more.c \
	rc.c \
	reopen.c \
	tilde.c \
	time.c

# This convenience library is solely to avoid compiler warnings
# in its generated sources.
librc_protocol_la_SOURCES = rc_protocol.c
librc_protocol_la_CFLAGS = -Wall -Wno-unused

BUILT_SOURCES = \
	rc_protocol.c \
	rc_protocol.h

guestfish_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish -I$(top_builddir)/fish \
	-DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"' \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

guestfish_LDADD = $(top_builddir)/src/libguestfs.la $(LIBREADLINE)

# Make libguestfs use the convenience library.
noinst_LTLIBRARIES = librc_protocol.la
guestfish_LDADD += librc_protocol.la

if HAVE_RPCGEN
rc_protocol.c: rc_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) -c -o $@-t $<
	sed 's,\.\./\.\./fish/,,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

rc_protocol.h: rc_protocol.x
	rm -f $@-t
	$(RPCGEN) -h -o $@-t $<
	mv $@-t $@
endif
