# libguestfs Haskell bindings
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
	Guestfs.hs \
	Bindtests.hs

# $(generator_built) isn't redundant below as the wildcard rule won't match, and
# therefore won't generate, the files if they haven't been created yet
EXTRA_DIST = $(generator_built) *.hs run-bindtests

CLEANFILES = *~

if HAVE_HASKELL

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	$(VG)

TESTS = run-bindtests Guestfs005Load Guestfs010Launch Guestfs050LVCreate

check_DATA = Bindtests

GHCFLAGS = -I$(top_builddir)/src -L$(top_builddir)/src/.libs

all: Bindtests Guestfs005Load Guestfs010Launch Guestfs050LVCreate

Bindtests: Bindtests.hs Guestfs.hs
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

Guestfs005Load: Guestfs005Load.hs Guestfs.hs
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

Guestfs010Launch: Guestfs010Launch.hs Guestfs.hs
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

Guestfs050LVCreate: Guestfs050LVCreate.hs Guestfs.hs
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

endif
