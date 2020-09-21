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

include $(top_srcdir)/subdir-rules.mk

include $(srcdir)/Makefile.inc

generator_built = \
	$(guestfs_gobject_headers) \
	$(guestfs_gobject_sources) \
	bindtests.js

BUILT_SOURCES = $(generator_built)

EXTRA_DIST = \
	$(generator_built) \
	TODO.txt \
	.gitignore \
	bindtests-retvalues.js \
	guestfs-gobject.pod \
	tests-misc.js \
	run-tests \
	run-tests-retvalues \
	run-live-tests

# Remove the old generated files which were directly in the gobject/
# directory.  These have now moved into gobject/src/
CLEANFILES += \
	guestfs-gobject*.c

libname = libguestfs-gobject-1.0.la

lib_LTLIBRARIES = $(libname)

libguestfs_gobject_1_0_ladir = $(includedir)/guestfs-gobject

libguestfs_gobject_1_0_la_HEADERS = $(guestfs_gobject_headers)
libguestfs_gobject_1_0_la_SOURCES = $(guestfs_gobject_sources)
libguestfs_gobject_1_0_la_CFLAGS = -I$(top_srcdir)/lib \
	                           -I$(top_srcdir)/include \
	                           -I$(srcdir)/include \
                                   -DGUESTFS_PRIVATE=1 \
                                   $(GOBJECT_CFLAGS)
libguestfs_gobject_1_0_la_LDFLAGS = $(LDFLAGS) -L$(top_builddir)/lib
libguestfs_gobject_1_0_la_LIBADD = $(top_builddir)/lib/libguestfs.la $(GOBJECT_LIBS) $(GIO_LIBS)

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libguestfs-gobject-1.0.pc

# All the headers except <guestfs-gobject.h> should be installed
# in the subdirectory.
install-data-hook:
	rm $(DESTDIR)$(includedir)/guestfs-gobject/guestfs-gobject.h
	install -m 0644 $(srcdir)/include/guestfs-gobject.h $(DESTDIR)$(includedir)

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
Guestfs_1_0_gir_CFLAGS = $(INCLUDES) -I$(srcdir)/include
Guestfs_1_0_gir_LIBS = $(libname) $(top_builddir)/lib/libguestfs.la
Guestfs_1_0_gir_FILES = $(patsubst %,$(srcdir)/%,$(introspection_sources))
INTROSPECTION_GIRS += Guestfs-1.0.gir

girdir = $(datadir)/gir-1.0
gir_DATA = $(INTROSPECTION_GIRS)

typelibdir = $(libdir)/girepository-1.0
typelib_DATA = $(INTROSPECTION_GIRS:.gir=.typelib)

# Tests.

TESTS = \
	run-tests \
	run-tests-retvalues

if ENABLE_APPLIANCE
TESTS += run-live-tests
endif ENABLE_APPLIANCE

TESTS_ENVIRONMENT = $(top_builddir)/run --test

$(TESTS): $(typelib_DATA)

CLEANFILES += $(gir_DATA) $(typelib_DATA)

if ENABLE_VAPIGEN
-include $(VAPIGEN_MAKEFILE)

libguestfs-gobject-1.0.vapi: Guestfs-1.0.gir libguestfs-gobject-1.0.deps

VAPIGEN_VAPIS = libguestfs-gobject-1.0.vapi

libguestfs_gobject_1_0_vapi_DEPS = gobject-2.0 gio-2.0
libguestfs_gobject_1_0_vapi_METADATADIRS = $(srcdir)
libguestfs_gobject_1_0_vapi_FILES = Guestfs-1.0.gir

vapidir = $(datadir)/vala/vapi
vapi_DATA = $(VAPIGEN_VAPIS) $(VAPIGEN_VAPIS:.vapi=.deps)
endif

EXTRA_DIST += libguestfs-gobject-1.0.deps

endif HAVE_INTROSPECTION

# Documentation.

man_MANS = guestfs-gobject.3
noinst_DATA = $(top_builddir)/website/guestfs-gobject.3.html

guestfs-gobject.3 $(top_builddir)/website/guestfs-gobject.3.html: stamp-guestfs-gobject.pod

stamp-guestfs-gobject.pod: guestfs-gobject.pod
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-gobject.3 \
	  --html $(top_builddir)/website/guestfs-gobject.3.html \
	  --license examples \
	  $<
	touch $@
