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

include $(top_srcdir)/subdir-rules.mk

TESTS = \
	rhbz503169c10.sh \
	rhbz503169c13.sh \
	rhbz557655.sh \
	test-cancellation-download-librarycancels.sh \
	test-cancellation-upload-daemoncancels.sh \
	test-find0.sh \
	test-lvm-mapping.pl \
	test-noexec-stack.pl \
	test-qemudie-killsub.sh \
	test-qemudie-midcommand.sh \
	test-qemudie-synch.sh \
	test-read_file.sh \
	test-remote.sh \
	test-reopen.sh \
	test-stringlist.sh

SKIPPED_TESTS = \
	test-bootbootboot.sh

FAILING_TESTS = \
	test-qemudie-launchfail.sh

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	PERL5LIB=$(top_builddir)/perl/blib/lib:$(top_builddir)/perl/blib/arch \
	NOEXEC_CHECK="$(top_builddir)/src/.libs/libguestfs.so $(top_builddir)/daemon/guestfsd"

EXTRA_DIST = \
	$(FAILING_TESTS) \
	$(SKIPPED_TESTS) \
	$(TESTS) \
	rhbz557655-expected.stdout \
	rhbz557655-expected.stderr
