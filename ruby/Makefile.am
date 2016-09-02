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
	ext/guestfs/actions-0.c \
	ext/guestfs/actions-1.c \
	ext/guestfs/actions-2.c \
	ext/guestfs/actions-3.c \
	ext/guestfs/actions-4.c \
	ext/guestfs/actions-5.c \
	ext/guestfs/actions-6.c \
	ext/guestfs/actions.h \
	ext/guestfs/module.c \
	bindtests.rb

DLEXT := $(shell $(RUBY) -rrbconfig -e "puts RbConfig::CONFIG['DLEXT']")

EXTRA_DIST = \
	$(generator_built) \
	Rakefile.in \
	README.rdoc \
	doc/site/index.html \
	ext/guestfs/handle.c \
	lib/guestfs.rb \
	run-bindtests \
	run-ruby-tests \
	t/tc_*.rb \
	t/test_helper.rb

CLEANFILES += \
	lib/*~ \
	t/*~ \
	ext/guestfs/*~ \
	ext/guestfs/extconf.h \
	ext/guestfs/_guestfs.o \
	ext/guestfs/_guestfs.$(DLEXT) \
	ext/guestfs/mkmf.log \
	ext/guestfs/Makefile

if HAVE_RUBY

all: $(generator_built) doc/site/index.html
	$(RAKE) build

# Rebuilding the documentation takes forever, so be careful to only do
# it when the ruby bindings change.
doc/site/index.html doc/site/api/table_of_contents.html: stamp-rdoc

stamp-rdoc: $(generator_built)
	$(RAKE) rdoc
	touch $@

# Packagers can override this by doing: make INSTALLDIRS=vendor install
# INSTALLDIRS also affects where Perl bindings are installed.
INSTALLDIRS = site

RUBY_LIBDIR := $(shell $(RUBY) -rrbconfig -e "puts RbConfig::CONFIG['$(INSTALLDIRS)libdir']")
RUBY_ARCHDIR := $(shell $(RUBY) -rrbconfig -e "puts RbConfig::CONFIG['$(INSTALLDIRS)archdir']")

install:
	$(MKDIR_P) $(DESTDIR)$(RUBY_LIBDIR)
	$(MKDIR_P) $(DESTDIR)$(RUBY_ARCHDIR)
	$(INSTALL) -p -m 0644 $(srcdir)/lib/guestfs.rb $(DESTDIR)$(RUBY_LIBDIR)
	$(INSTALL) -p -m 0755 ext/guestfs/_guestfs.$(DLEXT) $(DESTDIR)$(RUBY_ARCHDIR)

TESTS = run-bindtests run-ruby-tests

TESTS_ENVIRONMENT = $(top_builddir)/run --test

endif
