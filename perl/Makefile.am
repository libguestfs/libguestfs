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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

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
	lib/Sys/Guestfs/Lib.pm \
	run-bindtests \
	run-perl-tests \
	t/*.t \
	typemap

if HAVE_PERL

# Interfacing automake and ExtUtils::MakeMaker known to be
# a nightmare, news at 11.

# src/ dependencies
.PHONY: src_deps
src_deps: $(top_builddir)/src/libguestfs.la $(generator_built)

# Images used by tests
.PHONY: test_images
test_images:
	$(MAKE) -C $(top_builddir)/images

TESTS = run-bindtests run-perl-tests

$(TESTS): src_deps all appliance test_images

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir)

INSTALLDIRS = site

all: Makefile-pl src_deps
	$(MAKE) -f Makefile-pl

Makefile-pl: Makefile.PL
	perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS) PREFIX=$(prefix)

# No!  Otherwise it is deleted before the clean-local rule runs.
#CLEANFILES = Makefile-pl

clean-local:
	-$(MAKE) -f Makefile-pl clean
	rm -f Makefile-pl

install-data-hook:
	$(MAKE) -f Makefile-pl DESTDIR=$(DESTDIR) install

endif
