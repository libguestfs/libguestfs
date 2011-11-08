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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

include $(top_srcdir)/subdir-rules.mk

generator_built = \
	Guestfs.hs \
	Bindtests.hs

# $(generator_built) isn't redundant below as the wildcard rule won't match, and
# therefore won't generate, the files if they haven't been created yet
EXTRA_DIST = $(generator_built) *.hs run-bindtests

if HAVE_HASKELL

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir) \
	$(VG)

TESTS = run-bindtests Guestfs005Load Guestfs010Basic

check_DATA = Bindtests

GHCFLAGS = -I$(top_builddir)/src -L$(top_builddir)/src/.libs

all_targets = Bindtests Guestfs005Load Guestfs010Basic
$(all_targets): $(top_builddir)/src/libguestfs.la

all: $(all_targets)

Guestfs.o: Guestfs.hs
	$(GHC)  $(GHCFLAGS) -c $<

Bindtests: Bindtests.hs Guestfs.o
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

Guestfs005Load: Guestfs005Load.hs Guestfs.o
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

Guestfs010Basic: Guestfs010Basic.hs Guestfs.o
	$(GHC)  $(GHCFLAGS) -main-is $(shell basename $@) --make -o $@ $< -lguestfs

CLEANFILES = $(all_targets) *~ *.hi *.o

endif
