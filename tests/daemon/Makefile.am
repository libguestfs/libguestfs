# libguestfs
# Copyright (C) 2015 Red Hat Inc.
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

# Tests in this subdirectory run the daemon as a captive host process
# and send commands directly to it.  There is a small Perl library
# called 'captive-daemon.pm' in this directory to help with this.

include $(top_srcdir)/subdir-rules.mk

check_DATA = captive-daemon.pm

TESTS =

TESTS_ENVIRONMENT = $(top_builddir)/run --test

EXTRA_DIST = \
	captive-daemon.pm \
	$(TESTS)

check-valgrind:
	$(MAKE) check TEST_WITH_VALGRIND=1
