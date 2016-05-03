# libguestfs
# Copyright (C) 2011-2016 Red Hat Inc.
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

# Safety and liveness tests of components that libguestfs depends upon
# (not of libguestfs itself).  Mainly this is for qemu and the kernel.
# This test is the first to run.

include $(top_srcdir)/subdir-rules.mk

noinst_PROGRAMS = boot-benchmark

boot_benchmark_SOURCES = \
	boot-benchmark.c \
	../boot-analysis/boot-analysis-utils.c \
	../boot-analysis/boot-analysis-utils.h
boot_benchmark_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/utils/boot-analysis
boot_benchmark_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
boot_benchmark_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la \
	-lm

EXTRA_DIST = boot-benchmark-range.pl
