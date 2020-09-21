# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

TESTS_ENVIRONMENT = \
	$(top_builddir)/run --test

TESTS = \
	test-qemu-drive.sh

if HAVE_LIBVIRT
TESTS += \
	test-qemu-drive-libvirt.sh \
	test-qemu-drive-with-blocksize-libvirt.sh

if ENABLE_APPLIANCE
TESTS += \
	test-27-disks.sh \
	test-255-disks.sh \
	test-add-lots-of-disks.sh \
	test-add-drive-with-blocksize.sh
endif
endif

SLOW_TESTS = \
	test-max-disks.sh

TESTS += \
	$(SLOW_TESTS)

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

check_PROGRAMS = test-add-disks

test_add_disks_SOURCES = \
	test-add-disks.c
test_add_disks_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib
test_add_disks_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_add_disks_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la \
	$(LIBXML2_LIBS)

EXTRA_DIST = \
	debug-qemu.sh \
	$(TESTS)
