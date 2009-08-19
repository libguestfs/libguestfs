# libguestfs
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
	tests.c

# Tests.  These are auto-generated from the test descriptions
# in the generator.

check_PROGRAMS = tests test-command

tests_SOURCES = tests.c
tests_CFLAGS = -I$(top_srcdir)/src -I$(top_builddir)/src -Wall
tests_LDADD = $(top_builddir)/src/libguestfs.la

# Old version of e2fsprogs which didn't support UUIDs?
e2fs_uuid_not_supported :=                                              \
  $(shell r=1;                                                          \
    test -x ../initramfs/sbin/mkswap                                    \
      && ../initramfs/sbin/mkswap --help 2>&1 | grep -sq -- -U          \
      && r=1;                                                           \
    echo $$r)

TESTS = tests
TESTS_ENVIRONMENT = \
	SKIP_TEST_COMMAND=$(shell ldd test-command | grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_COMMAND_LINES=$(shell ldd test-command | grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_ZEROFREE=$(shell test -x ../initramfs/usr/sbin/zerofree || echo 1) \
	SKIP_TEST_NTFS_3G_PROBE=$(shell test -x ../initramfs/bin/ntfs-3g.probe || echo 1) \
	SKIP_TEST_CHECKSUM_8=$(shell if test `find ../initramfs -name squashfs.ko | wc -l` -eq 0; then echo 1; fi) \
	SKIP_TEST_MKSWAP_U=$(e2fs_uuid_not_supported) \
	SKIP_TEST_SWAPON_UUID=$(e2fs_uuid_not_supported) \
	SKIP_TEST_MKE2JOURNAL_U=$(e2fs_uuid_not_supported) \
	SKIP_TEST_SCRUB_FILE=$(shell test -x ../initramfs/usr/bin/scrub || echo 1) \
	SKIP_TEST_SCRUB_DEVICE=$(shell test -x ../initramfs/usr/bin/scrub || echo 1) \
	$(VG)

# Run the tests under valgrind.

valgrind:
	$(MAKE) check VG="valgrind --quiet --leak-check=full"

# This binary must be statically linked.  It is used for testing
# the "guestfs_command" and "guestfs_command_lines" functions.

test_command_SOURCES = test-command.c
test_command_LDFLAGS = -all-static
