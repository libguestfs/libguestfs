# libguestfs Perl bindings
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
	Guestfs.xs \
	lib/Sys/Guestfs.pm \
	bindtests.pl

EXTRA_DIST = \
	$(generator_built) \
	Makefile.PL.in \
	examples/README \
	examples/LICENSE \
	examples/*.pl \
	run-bindtests \
	run-perl-tests \
	t/*.t \
	typemap

if HAVE_PERL

# Interfacing automake and ExtUtils::MakeMaker known to be
# a nightmare, news at 11.

# src/ dependencies
src_deps: $(top_builddir)/src/libguestfs.la $(generator_built)

# Images used by tests.
test_images:
	$(MAKE) -C $(top_builddir)/tests/data

# Build the appliance.
appliance:
	$(MAKE) -C $(top_builddir)/appliance

TESTS = run-bindtests
test_prereq = src_deps all test_images

if ENABLE_APPLIANCE
test_prereq += appliance
TESTS += run-perl-tests
endif

$(TESTS): $(test_prereq)

TESTS_ENVIRONMENT = $(top_builddir)/run --test

INSTALLDIRS = site

all: Makefile-pl src_deps
	$(MAKE) -f Makefile-pl

Makefile-pl: Makefile.PL
	-[ $(srcdir) != $(builddir) ] && cp -rsu $(abs_srcdir)/. $(builddir)/.
	perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS) PREFIX=$(prefix)

# No!  Otherwise it is deleted before the clean-local rule runs.
#CLEANFILES = Makefile-pl

clean-local:
	-$(MAKE) -f Makefile-pl clean
	rm -f Makefile-pl

install-data-hook:
	$(MAKE) -C $(srcdir) -f $(abs_builddir)/Makefile-pl \
		DESTDIR=$(DESTDIR) install

endif

.PHONY: appliance src_deps test_images
