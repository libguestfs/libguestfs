# libguestfs
# Copyright (C) 2011-2019 Red Hat Inc.
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

EXTRA_DIST = boot-benchmark.pod boot-benchmark-range.pl

noinst_PROGRAMS = boot-benchmark

boot_benchmark_SOURCES = \
	boot-benchmark.c \
	../boot-analysis/boot-analysis-utils.c \
	../boot-analysis/boot-analysis-utils.h
boot_benchmark_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/utils/boot-analysis
boot_benchmark_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
boot_benchmark_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la \
	-lm

# Manual page.
# It should be noinst_MANS but that doesn't work.
noinst_DATA = boot-benchmark.1

boot-benchmark.1: boot-benchmark.pod
	$(PODWRAPPER) \
	  --man $@ \
	  --license GPLv2+ \
	  --warning safe \
	  $<
