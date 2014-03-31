# libguestfs Python bindings
# Copyright (C) 2009-2014 Red Hat Inc.
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
	guestfs-py.c \
	guestfs.py \
	bindtests.py

EXTRA_DIST = \
	$(generator_built) \
	MANIFEST.in \
	README.txt \
	setup.py.in \
	run-bindtests \
	run-python-tests \
	t/*.py

if HAVE_PYTHON

# Build the library.

pythondir = $(PYTHON_INSTALLDIR)

python_DATA = guestfs.py

python_LTLIBRARIES = libguestfsmod.la

libguestfsmod_la_SOURCES = guestfs-py.c guestfs-py.h guestfs-py-byhand.c

libguestfsmod_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	$(PYTHON_CFLAGS) \
	-I$(top_srcdir)/src -I$(top_builddir)/src

libguestfsmod_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

libguestfsmod_la_LIBADD = \
	$(top_builddir)/src/libutils_la-utils.lo \
	$(top_builddir)/src/libguestfs.la

libguestfsmod_la_LDFLAGS = -avoid-version -shared -module -shrext $(PYTHON_EXT_SUFFIX)

# Currently we don't use setup.py to build the Python library for
# distribution with libguestfs (although maybe we should in future).
# For now, these are some rules which use setup.py to make a source
# distribution for pip, and a few other bits.

sdist: setup.py stamp-extra-files
	$(PYTHON) setup.py $@

setup-build: setup.py stamp-extra-files
	$(PYTHON) setup.py build

setup-install: setup.py stamp-extra-files
	$(PYTHON) setup.py install $(SETUP_INSTALL_ARGS)

# Python's crappy MANIFEST file cannot graft single files, so we have
# to hard-link any extra files we need into the local directory.
stamp-extra-files: \
	  config.h \
	  guestfs-internal-all.h \
	  guestfs-internal-frontend-cleanups.h \
	  guestfs-internal-frontend.h \
	  utils.c
	touch $@

config.h:
	ln ../config.h $@

guestfs-internal-all.h:
	ln $(top_srcdir)/src/guestfs-internal-all.h $@

guestfs-internal-frontend-cleanups.h:
	ln $(top_srcdir)/src/guestfs-internal-frontend-cleanups.h $@

guestfs-internal-frontend.h:
	ln $(top_srcdir)/src/guestfs-internal-frontend.h $@

utils.c:
	ln $(top_srcdir)/src/utils.c $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += run-python-tests
endif ENABLE_APPLIANCE

endif HAVE_PYTHON

# Extra clean.
CLEANFILES = \
	*~ examples/*~ t/*~ \
	config.h \
	guestfs-internal-all.h \
	guestfs-internal-frontend-cleanups.h \
	guestfs-internal-frontend.h \
	stamp-extra-files \
	utils.c

clean-local:
	rm -rf build dist
