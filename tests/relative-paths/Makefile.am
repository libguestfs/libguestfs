# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Test relative paths to backing files.  Mainly this is a test that we
# don't break this.
#
# See eg:
# https://bugzilla.redhat.com/show_bug.cgi?id=1053684
# https://www.redhat.com/archives/libguestfs/2014-January/thread.html#00087
# (and more)

include $(top_srcdir)/subdir-rules.mk

TESTS = \
	test-relative-paths.sh

TESTS_ENVIRONMENT = $(top_builddir)/run --test

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

EXTRA_DIST = \
	$(TESTS)
