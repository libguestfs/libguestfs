# libguestfs Python bindings
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

EXTRA_DIST = \
	guestfs.py \
	guestfs-py.c \
	t/*.py

CLEANFILES = *~ t/*~

if HAVE_PYTHON

pythondir = $(PYTHON_SITE_PACKAGES)

python_DATA = guestfs.py

python_LTLIBRARIES = libguestfsmod.la

libguestfsmod_la_SOURCES = guestfs-py.c
libguestfsmod_la_CFLAGS = -Wall -I$(PYTHON_INCLUDEDIR) -I$(top_builddir)/src
libguestfsmod_la_LIBADD = $(top_builddir)/src/libguestfs.la

TESTS_ENVIRONMENT = \
	LIBGUESTFS_PATH=$(abs_top_builddir) \
	PYTHONPATH=$(abs_top_builddir)/python:$(abs_top_builddir)/python/.libs \
	$(PYTHON)
TESTS = t/005-import.py t/010-launch.py t/050-lvcreate.py

endif