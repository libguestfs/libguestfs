# libguestfs Perl bindings
# Copyright (C) 2009-2023 Red Hat Inc.
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
	lib/Sys/Guestfs.xs \
	lib/Sys/Guestfs.pm \
	bindtests.pl

EXTRA_DIST = \
	$(generator_built) \
	Build.PL.in \
	examples/README \
	examples/LICENSE \
	examples/*.pl \
	MANIFEST \
	run-bindtests \
	run-perl-tests \
	t/*.t \
	typemap

DISTCLEANFILES += Build

# Some files are not removed by './Build clean' below.
CLEANFILES += \
	MYMETA.json \
	MYMETA.yml \
	pm_to_blib

# It would be nice to do this, but 'make distclean' runs 'make clean'
# in parallel, and './Build clean' requires '_build/magicnum' to
# exist, so you end up deleting a file which is required by the
# parallel 'make clean' instance.
#
#distclean-local:
#	rm -rf _build

if HAVE_PERL

all-local: Build
	./Build

clean-local: Build
	./Build clean

Build: Build.PL
	$(PERL) Build.PL --prefix "@prefix@"

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = run-bindtests

if ENABLE_APPLIANCE
TESTS += run-perl-tests
endif

# Packagers may override this, eg using 'make install INSTALLDIRS=vendor'
INSTALLDIRS = site

install-data-hook: Build
	./Build install --destdir "$(DESTDIR)" --installdirs $(INSTALLDIRS)

endif
