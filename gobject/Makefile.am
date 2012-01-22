# libguestfs
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

BUILT_SOURCES = \
	guestfs-gobject.h \
	guestfs-gobject.c \
	bindtests.js
EXTRA_DIST = \
	$(BUILT_SOURCES) \
	bindtests-manual.js \
	run-bindtests

libname = libguestfs-gobject-1.0.la

lib_LTLIBRARIES = $(libname)

libguestfs_gobject_1_0_ladir = $(includedir)

libguestfs_gobject_1_0_la_HEADERS = guestfs-gobject.h
libguestfs_gobject_1_0_la_SOURCES = guestfs-gobject.c
libguestfs_gobject_1_0_la_CFLAGS = -I$(top_srcdir)/src $(GOBJECT_CFLAGS)
libguestfs_gobject_1_0_la_LIBS = $(GOBJECT_LIBS)
libguestfs_gobject_1_0_la_LDFLAGS = $(LDFLAGS) -L$(top_builddir)/src
libguestfs_gobject_1_0_la_LIBADD = -lguestfs

-include $(INTROSPECTION_MAKEFILE)
INTROSPECTION_GIRS =
INTROSPECTION_SCANNER_ARGS = --add-include-path=$(srcdir) --warn-all
INTROSPECTION_COMPILER_ARGS = --includedir=$(srcdir)

if HAVE_INTROSPECTION
introspection_sources = \
  $(libguestfs_gobject_1_0_la_HEADERS) \
  $(libguestfs_gobject_1_0_la_SOURCES)

Guestfs-1.0.gir: $(libname)
Guestfs_1_0_gir_INCLUDES = GObject-2.0 Gio-2.0
Guestfs_1_0_gir_CFLAGS = $(INCLUDES)
Guestfs_1_0_gir_LIBS = $(libname)
Guestfs_1_0_gir_FILES = $(introspection_sources)
INTROSPECTION_GIRS += Guestfs-1.0.gir

girdir = $(datadir)/gir-1.0
gir_DATA = $(INTROSPECTION_GIRS)

typelibdir = $(libdir)/girepository-1.0
typelib_DATA = $(INTROSPECTION_GIRS:.gir=.typelib)

TESTS = run-bindtests
TESTS_ENVIRONMENT = GJS=$(GJS)

$(TESTS): $(typelib_DATA)

CLEANFILES = $(gir_DATA) $(typelib_DATA)
endif
