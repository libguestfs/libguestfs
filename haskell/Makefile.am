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
	$(srcdir)/Guestfs.hs \
	Bindtests.hs

# $(generator_built) isn't redundant below as the wildcard rule won't match, and
# therefore won't generate, the files if they haven't been created yet
EXTRA_DIST = $(generator_built) *.hs run-bindtests

if HAVE_HASKELL

TESTS_ENVIRONMENT = $(top_builddir)/run --test $(VG)

# XXX Don't run the bindtests: they don't build since the addition of optargs.
# Haskell bindings are incomplete.

TESTS = Guestfs010Load Guestfs030Config
if ENABLE_APPLIANCE
TESTS += Guestfs050LVCreate
endif ENABLE_APPLIANCE

#check_DATA = Bindtests

GHCFLAGS = -I$(top_builddir)/lib -L$(top_builddir)/lib/.libs -i$(srcdir)

all_targets = Guestfs010Load Guestfs030Config Guestfs050LVCreate
$(all_targets): $(top_builddir)/lib/libguestfs.la

all: $(all_targets)

built_tests = Bindtests Guestfs010Load Guestfs030Config Guestfs050LVCreate

# Building with ghc --make doesn't work properly here because it
# always rebuilds Guestfs.o despite it being up to date. So if you:
#
# * build Guestfs010Load, then build it again, the second time it will
# not be rebuilt.
#
# * build Guestfs010Load, then build Guestfs030Config, then build
# Guestfs010Load again, it will be rebuilt every time.
#
# In the second case, building Guestfs030Config rebuilt Guestfs.o. As
# this is a dependency of Guestfs010Load, Guestfs010Load is now
# unnecessarily out of date.
#
# Because the default target builds all of the above, they will all be
# rebuilt every time.
#
# An obvious choice would be to remove the Guestfs.o dependency, but
# this would potentially result in corruption during a parallel build
# as multiple ghc processes rebuild Guestfs.o simultaneously. I had
# hoped that the solution below would work. It correctly builds
# Guestfs010Load and Guestfs030Config, but Guestfs050LVCreate requires
# additional link options which I haven't been able to work out.

#Guestfs.o: $(srcdir)/Guestfs.hs
#	$(GHC)  $(GHCFLAGS) -c $< -o $@
#
#$(built_tests:%=%.o): %.o: %.hs Guestfs.o
#	$(GHC)  $(GHCFLAGS) -main-is $(basename $<) -c $< -o $@
#
#$(built_tests): %: %.o Guestfs.o
#	$(GHC)  $(GHCFLAGS) -main-is $@ -o $@ $< Guestfs.o -lguestfs

# The solution below isn't ideal. It uses --make and avoids the
# parallel make problem by putting object files in separate
# directories per target.

$(built_tests): %: %.hs Guestfs.hs
	$(GHC)  $(GHCFLAGS) --make -main-is $@ -odir .$@ -o $@ $< $(srcdir)/Guestfs.hs -lguestfs

CLEANFILES += $(all_targets) *.hi test-lv-create.img

clean-local:
	-rm -rf $(built_tests:%=.%)

endif
