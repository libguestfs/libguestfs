# libguestfs Ruby bindings
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
	Rakefile.in \
	ext/guestfs/_guestfs.c \
	ext/guestfs/extconf.rb \
	lib/guestfs.rb \
	run-bindtests \
	run-ruby-tests \
	bindtests.rb \
	tests/tc_*.rb

CLEANFILES = \
	lib/*~ \
	tests/*~ \
	ext/guestfs/*~ \
	ext/guestfs/extconf.h \
	ext/guestfs/_guestfs.o \
	ext/guestfs/_guestfs.so \
	ext/guestfs/mkmf.log \
	ext/guestfs/Makefile

if HAVE_RUBY

TESTS = run-bindtests run-ruby-tests

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=../src/.libs \
	LIBGUESTFS_PATH=../appliance

all:
	rake build

endif