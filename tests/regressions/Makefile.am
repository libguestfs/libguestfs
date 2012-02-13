# libguestfs
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

include $(top_srcdir)/subdir-rules.mk

TESTS = \
	rhbz501893 \
	rhbz503169c13.sh \
	rhbz557655.sh \
	rhbz576879.sh \
	rhbz578407.sh \
	rhbz580246.sh \
	rhbz602997.sh \
	rhbz690819.sh \
	rhbz789960.sh \
	test-noexec-stack.pl

tests_not_run = \
	rhbz727178.sh

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	NOEXEC_CHECK="$(top_builddir)/src/.libs/libguestfs.so $(top_builddir)/daemon/guestfsd" \
	$(top_builddir)/run

check_PROGRAMS = \
	rhbz501893

rhbz501893_SOURCES = rhbz501893.c
rhbz501893_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
rhbz501893_LDADD = \
	$(top_builddir)/src/libguestfs.la

EXTRA_DIST = \
	$(TESTS) \
	$(tests_not_run) \
	rhbz557655-expected.stdout \
	rhbz557655-expected.stderr
