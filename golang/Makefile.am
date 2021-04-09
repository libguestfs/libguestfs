# libguestfs golang bindings
# Copyright (C) 2013 Red Hat Inc.
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

# http://golang.org/doc/code.html#Organization
pkg = libguestfs.org/guestfs

source_files = \
	src/$(pkg)/guestfs.go \
	src/$(pkg)/guestfs_*_test.go

generator_built = \
	$(source_files) \
	bindtests/bindtests.go

EXTRA_DIST = \
	src/libguestfs.org/guestfs/.gitignore \
	src/libguestfs.org/guestfs/go.mod \
	$(generator_built) \
	bindtests/go.mod \
	config-test.go \
	run-bindtests \
	run-tests

if HAVE_GOLANG

all-local: $(source_files)
	-[ "$(srcdir)" != "$(builddir)" ] && \
	    ln -s $(abs_srcdir)/src $(builddir)/src
	cd src/$(pkg) && \
	    $(abs_top_builddir)/run $(GOLANG) build

TESTS_ENVIRONMENT = pkg=$(pkg) $(top_builddir)/run $(VG) # --test

TESTS = run-bindtests run-tests

endif

CLEANFILES += src/$(pkg)/*~
