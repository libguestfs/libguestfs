# libguestfs Python bindings
# Copyright (C) 2009-2019 Red Hat Inc.
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
	actions-0.c \
	actions-1.c \
	actions-2.c \
	actions-3.c \
	actions-4.c \
	actions-5.c \
	actions-6.c \
	actions.h \
	module.c \
	structs.c \
	guestfs.py \
	bindtests.py

EXTRA_DIST = \
	$(generator_built) \
	MANIFEST.in \
	README.txt \
	setup.py.in \
	run-bindtests \
	run-python-tests \
	t/README \
	t/*.py

if HAVE_PYTHON

# Build the library.

pythondir = $(PYTHON_INSTALLDIR)

python_DATA = guestfs.py

python_LTLIBRARIES = libguestfsmod.la

libguestfsmod_la_SOURCES = \
	actions-0.c \
	actions-1.c \
	actions-2.c \
	actions-3.c \
	actions-4.c \
	actions-5.c \
	actions-6.c \
	actions.h \
	handle.c \
	module.c \
	structs.c

libguestfsmod_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	$(PYTHON_CFLAGS) \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib

libguestfsmod_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

libguestfsmod_la_LIBADD = \
	$(top_builddir)/common/utils/libutils_la-utils.lo \
	$(top_builddir)/lib/libguestfs.la

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
	  c-ctype.h \
	  cleanups.c \
	  cleanups.h \
	  config.h \
	  guestfs-internal-all.h \
	  guestfs-utils.h \
	  ignore-value.h \
	  utils.c
	touch $@

config.h:
	ln ../config.h $@

c-ctype.h:
	ln $(top_srcdir)/gnulib/lib/c-ctype.h $@

cleanups.c:
	ln $(top_srcdir)/common/utils/cleanups.c $@

cleanups.h:
	ln $(top_srcdir)/common/utils/cleanups.h $@

ignore-value.h:
	ln $(top_srcdir)/gnulib/lib/ignore-value.h $@

guestfs-internal-all.h:
	ln $(top_srcdir)/lib/guestfs-internal-all.h $@

guestfs-utils.h:
	ln $(top_srcdir)/common/utils/guestfs-utils.h $@

utils.c:
	ln $(top_srcdir)/common/utils/utils.c $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += run-python-tests
endif ENABLE_APPLIANCE

endif HAVE_PYTHON

# Extra clean.
CLEANFILES += \
	*.pyc \
	examples/*~ examples/*.pyc \
	t/*~ t/*.pyc \
	c-ctype.h \
	config.h \
	cleanups.c \
	cleanups.h \
	guestfs-internal-all.h \
	guestfs-utils.h \
	ignore-value.h \
	stamp-extra-files \
	utils.c

clean-local:
	rm -rf build dist
