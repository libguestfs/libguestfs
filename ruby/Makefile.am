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
	lib/guestfs.rb \
	run-bindtests \
	run-ruby-tests \
	t/tc_*.rb \
	t/test_helper.rb

CLEANFILES = \
	lib/*~ \
	t/*~ \
	ext/guestfs/*~ \
	ext/guestfs/extconf.h \
	ext/guestfs/_guestfs.o \
	ext/guestfs/_guestfs.so \
	ext/guestfs/mkmf.log \
	ext/guestfs/Makefile

if HAVE_RUBY

all: $(generator_built)
	$(RAKE) build
	$(RAKE) rdoc

# Packagers can override this by doing: make INSTALLDIRS=vendor install
# INSTALLDIRS also affects where Perl bindings are installed.
INSTALLDIRS = site

RUBY_LIBDIR := $(shell $(RUBY) -rrbconfig -e "puts RbConfig::CONFIG['$(INSTALLDIRS)libdir']")
RUBY_ARCHDIR := $(shell $(RUBY) -rrbconfig -e "puts RbConfig::CONFIG['$(INSTALLDIRS)archdir']")

install:
	$(MKDIR_P) $(DESTDIR)$(RUBY_LIBDIR)
	$(MKDIR_P) $(DESTDIR)$(RUBY_ARCHDIR)
	$(INSTALL) -p -m 0644 $(srcdir)/lib/guestfs.rb $(DESTDIR)$(RUBY_LIBDIR)
	$(INSTALL) -p -m 0755 ext/guestfs/_guestfs.so $(DESTDIR)$(RUBY_ARCHDIR)

TESTS = run-bindtests run-ruby-tests

TESTS_ENVIRONMENT = $(top_builddir)/run --test

endif
