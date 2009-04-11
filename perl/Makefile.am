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
	run-perl-tests \
	t/*.t \
	typemap

CLEANFILES = *~ examples/*~ t/*~

if HAVE_PERL

# Interfacing automake and ExtUtils::MakeMaker known to be
# a nightmare, news at 11.

TESTS = run-perl-tests

INSTALLDIRS = site

all:
	perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS) PREFIX=$(prefix)
	$(MAKE) -f Makefile-pl

install-data-hook:
	$(MAKE) -f Makefile-pl DESTDIR=$(DESTDIR) install

endif
