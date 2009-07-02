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
	time.c

guestfish_CFLAGS = \
	-I$(top_builddir)/src -Wall \
	-DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"'
guestfish_LDADD = $(top_builddir)/src/libguestfs.la $(LIBREADLINE)
