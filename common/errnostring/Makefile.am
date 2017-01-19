# libguestfs
# Copyright (C) 2017 Red Hat Inc.
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
	errnostring-gperf.gperf \
	errnostring.c \
	errnostring.h

BUILT_SOURCES = \
	$(generator_built) \
	errnostring-gperf.c

EXTRA_DIST = \
	$(BUILT_SOURCES)

noinst_LTLIBRARIES = liberrnostring.la

# Build the errnostring perfect hash code.  The generated code has lots
# of warnings so we must compile it in a separate mini-library.
liberrnostring_la_SOURCES = \
	errnostring-gperf.c \
	errnostring.h \
	errnostring.c
liberrnostring_la_CFLAGS = $(GCC_VISIBILITY_HIDDEN)

errnostring-gperf.c: errnostring-gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@
