# libguestfs
# Copyright (C) 2017-2023 Red Hat Inc.
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

# This directory contains some dependencies originally from gnulib.
# The aim is for everything in this directory to eventually go away,
# probably being moved to common/utils.

include $(top_srcdir)/subdir-rules.mk

noinst_LTLIBRARIES = libgnu.la
libgnu_la_SOURCES = \
	accept4.c \
	base64.c \
	base64.h \
	bitrotate.h \
	c-ctype.h \
	cloexec.c \
	cloexec.h \
	error.c \
	error.h \
	full-read.c \
	full-read.h \
	full-write.c \
	full-write.h \
	getprogname.h \
	hash.c \
	hash.h \
	hash-pjw.c \
	hash-pjw.h \
	ignore-value.h \
	nonblocking.c \
	nonblocking.h \
	pipe2.c \
	safe-read.c \
	safe-read.h \
	safe-write.c \
	safe-write.h \
	xalloc-oversized.h \
	xstrtol.c \
	xstrtol.h \
	xstrtoll.c \
	xstrtoul.c \
	xstrtoull.c \
	xstrtoumax.c
libutils_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(GCC_VISIBILITY_HIDDEN)
