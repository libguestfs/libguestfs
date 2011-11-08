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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

include $(top_srcdir)/subdir-rules.mk

generator_built = \
	ext/guestfs/_guestfs.c \
	bindtests.rb

EXTRA_DIST = \
	$(generator_built) \
	Rakefile.in \
	README.rdoc \
	doc/site/index.html \
	ext/guestfs/extconf.rb \
	lib/guestfs.rb \
	run-bindtests \
	run-ruby-tests \
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
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir)

all: $(generator_built)
	rake build
	rake rdoc

RUBY_SITELIB := $(shell ruby -rrbconfig -e "puts Config::CONFIG['sitelibdir']")
RUBY_SITEARCH := $(shell ruby -rrbconfig -e "puts Config::CONFIG['sitearchdir']")

install:
	$(MKDIR_P) $(DESTDIR)$(RUBY_SITELIB)
	$(MKDIR_P) $(DESTDIR)$(RUBY_SITEARCH)
	$(INSTALL) -p -m 0644 lib/guestfs.rb $(DESTDIR)$(RUBY_SITELIB)
	$(INSTALL) -p -m 0755 ext/guestfs/_guestfs.so $(DESTDIR)$(RUBY_SITEARCH)

endif
