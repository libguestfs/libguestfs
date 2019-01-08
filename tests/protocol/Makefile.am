# libguestfs
# Copyright (C) 2009-2019 Red Hat Inc.
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

EXTRA_DIST = \
	test-both-ends-cancel.sh \
	test-cancellation-download-librarycancels.sh \
	test-cancellation-upload-daemoncancels.sh \
	test-launch-race.pl \
	test-qemudie-killsub.sh \
	test-qemudie-midcommand.sh \
	test-qemudie-synch.sh

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-both-ends-cancel.sh \
	test-cancellation-download-librarycancels.sh \
	test-cancellation-upload-daemoncancels.sh \
	test-error-messages \
	test-launch-race.pl \
	test-qemudie-killsub.sh \
	test-qemudie-midcommand.sh \
	test-qemudie-synch.sh

check_PROGRAMS = test-error-messages

test_error_messages_SOURCES = \
	../../common/protocol/guestfs_protocol.h \
	test-error-messages.c
test_error_messages_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/protocol -I$(top_builddir)/common/protocol \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib
test_error_messages_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS)
test_error_messages_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(top_builddir)/gnulib/lib/libgnu.la
