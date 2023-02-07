# libguestfs Python bindings
# Copyright (C) 2009-2023 Red Hat Inc.
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
	test-pycodestyle.sh \
	t/__init__.py \
	t/README \
	t/test[0-9]*.py

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
	structs.c \
	../common/utils/stringlists-utils.c

libguestfsmod_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	$(PYTHON_CFLAGS) \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include

libguestfsmod_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

libguestfsmod_la_LIBADD = \
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
	  config.h \
	  guestfs-stringlists-utils.h \
	  stringlists-utils.c
	touch $@

config.h:
	ln ../config.h $@

guestfs-stringlists-utils.h:
	ln $(top_srcdir)/common/utils/guestfs-stringlists-utils.h $@

stringlists-utils.c:
	ln $(top_srcdir)/common/utils/stringlists-utils.c $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += run-python-tests
endif ENABLE_APPLIANCE

if HAVE_PYCODESTYLE
TESTS += test-pycodestyle.sh
endif

endif HAVE_PYTHON

# Extra clean.
CLEANFILES += \
	*.pyc \
	examples/*~ examples/*.pyc \
	t/*~ t/*.pyc \
	config.h \
	guestfs-stringlists-utils.h \
	stamp-extra-files \
	stringlists-utils.c

clean-local:
	rm -rf build dist __pycache__ t/__pycache__
