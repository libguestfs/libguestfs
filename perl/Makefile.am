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

EXTRA_DIST = \
	Makefile.PL.in \
	Guestfs.xs \
	examples/README \
	examples/LICENSE \
	examples/*.pl \
	lib/Sys/Guestfs.pm \
	lib/Sys/Guestfs/Lib.pm \
	run-bindtests \
	run-perl-tests \
	bindtests.pl \
	t/*.t \
	typemap

if HAVE_PERL

# Interfacing automake and ExtUtils::MakeMaker known to be
# a nightmare, news at 11.

TESTS = run-bindtests run-perl-tests

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance

INSTALLDIRS = site

all: Makefile-pl
	$(MAKE) -f Makefile-pl

Makefile-pl: Makefile.PL
	perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS) PREFIX=$(prefix)

CLEANFILES = Makefile-pl

clean-local:
	-$(MAKE) -f Makefile-pl clean

install-data-hook:
	$(MAKE) -f Makefile-pl DESTDIR=$(DESTDIR) install

endif
