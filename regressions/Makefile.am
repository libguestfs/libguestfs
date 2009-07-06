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

# Regression tests and other important tests which are not
# specific to the C API.  We can write these more easily in
# higher level languages than C.
#
# See also capitests/

TESTS = \
	rhbz503169c10.sh \
	rhbz503169c13.sh \
	test-qemudie-midcommand.sh \
	test-qemudie-killsub.sh \
	test-qemudie-synch.sh

SKIPPED_TESTS = \
	test-bootbootboot.sh

FAILING_TESTS = \
	test-qemudie-launchfail.sh

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance

EXTRA_DIST = \
	$(FAILING_TESTS) \
	$(SKIPPED_TESTS) \
	$(TESTS)
