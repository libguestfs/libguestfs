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

TESTS = \
	qemu-liveness.sh \
	qemu-snapshot-isolation.sh \
	qemu-force-tcg.sh

TESTS_ENVIRONMENT = $(top_builddir)/run --test

EXTRA_DIST = \
	$(TESTS) \
	boot-benchmark-range.pl \
	qemu-boot.c \
	qemu-speed-test.c

# qemu-boot, qemu-speed-test, boot-analysis and boot-benchmark are
# built but not run by default as they are mainly qemu & kernel
# diagnostic tools.

check_PROGRAMS = qemu-boot qemu-speed-test boot-analysis boot-benchmark

qemu_boot_SOURCES = \
	../../df/estimate-max-threads.c \
	../../df/estimate-max-threads.h \
	qemu-boot.c
qemu_boot_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/df
qemu_boot_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
qemu_boot_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

qemu_speed_test_SOURCES = \
	qemu-speed-test.c
qemu_speed_test_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/df
qemu_speed_test_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
qemu_speed_test_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

boot_analysis_SOURCES = \
	boot-analysis.c \
	boot-analysis.h \
	boot-analysis-timeline.c \
	boot-analysis-utils.c \
	boot-analysis-utils.h
boot_analysis_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
boot_analysis_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS)
boot_analysis_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(PCRE_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la \
	-lm

boot_benchmark_SOURCES = \
	boot-benchmark.c \
	boot-analysis-utils.c \
	boot-analysis-utils.h
boot_benchmark_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
boot_benchmark_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
boot_benchmark_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la \
	-lm

# Don't run these tests in parallel, since they are designed to check
# the integrity of qemu.
.NOTPARALLEL:
