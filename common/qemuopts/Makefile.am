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

noinst_LTLIBRARIES = libqemuopts.la

libqemuopts_la_SOURCES = \
	qemuopts.c \
	qemuopts.h
libqemuopts_la_CPPFLAGS = \
	-I$(srcdir) -I.
libqemuopts_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(GCC_VISIBILITY_HIDDEN)

TESTS_ENVIRONMENT = $(top_builddir)/run --test
LOG_COMPILER = $(VG)
TESTS = qemuopts-tests

check_PROGRAMS = qemuopts-tests

qemuopts_tests_SOURCES = qemuopts-tests.c
qemuopts_tests_CPPFLAGS = \
	-I$(srcdir) -I.
qemuopts_tests_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
qemuopts_tests_LDADD = \
	libqemuopts.la

check-valgrind:
	make VG="@VG@" check
