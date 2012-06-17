# libguestfs Python bindings
# Copyright (C) 2009-2012 Red Hat Inc.
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

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= .

include $(top_srcdir)/subdir-rules.mk

generator_built = \
	guestfs-py.c \
	guestfs.py \
	bindtests.py

EXTRA_DIST = \
	$(generator_built) \
	run-bindtests \
	run-python-tests \
	t/*.py

if HAVE_PYTHON

pythondir = $(PYTHON_INSTALLDIR)

python_DATA = guestfs.py

python_LTLIBRARIES = libguestfsmod.la

libguestfsmod_la_SOURCES = guestfs-py.c guestfs-py.h guestfs-py-byhand.c
libguestfsmod_la_CFLAGS = -Wall -I$(PYTHON_INCLUDEDIR) \
			  -I$(top_srcdir)/src -I$(top_builddir)/src
libguestfsmod_la_LIBADD = $(top_builddir)/src/libguestfs.la
libguestfsmod_la_LDFLAGS = -avoid-version -shared

TESTS_ENVIRONMENT = \
	PYTHON=$(PYTHON) \
	$(top_builddir)/run

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += run-python-tests
endif ENABLE_APPLIANCE

endif HAVE_PYTHON
