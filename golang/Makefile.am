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
	bindtests.go

EXTRA_DIST = \
	src/libguestfs.org/guestfs/.gitignore \
	$(generator_built) \
	config-test.go \
	run-bindtests \
	run-tests

if HAVE_GOLANG

GOFLAGS =
if ENABLE_APPLIANCE
GOFLAGS += -tags appliance
endif

golangpkgdir = $(GOROOT)/pkg/$(GOOS)_$(GOARCH)/$(pkg)
golangsrcdir = $(GOROOT)/src/pkg/$(pkg)

golangpkg_DATA = \
	pkg/$(GOOS)_$(GOARCH)/$(pkg).a

pkg/$(GOOS)_$(GOARCH)/$(pkg).a: src/$(pkg)/guestfs.go
	$(top_builddir)/run $(GOLANG) install $(pkg)

golangsrc_DATA = $(source_files)

TESTS_ENVIRONMENT = pkg=$(pkg) GOFLAGS="$(GOFLAGS)" $(top_builddir)/run $(VG) # --test

TESTS = run-bindtests run-tests

endif

CLEANFILES = *~ src/$(pkg)/*~

clean-local:
	rm -rf pkg
