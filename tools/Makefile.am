# libguestfs virt-* tools
# Copyright (C) 2009-2011 Red Hat Inc.
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

tools = \
	list-filesystems \
	list-partitions \
	make-fs \
	tar \
	win-reg

EXTRA_DIST = \
	$(tools:%=virt-%) \
	test-virt-*.sh

CLEANFILES = test.img

if HAVE_TOOLS

bin_SCRIPTS = $(tools:%=virt-%)

# Manual pages and HTML files for the website.

# XXX Bug in automake?  If you list virt-tar.1 explicitly, then it
# builds and installs the man pages.  However if this is removed,
# then the man pages are neither built nor installed.
man_MANS = virt-tar.1 $(patsubst %,virt-%.1,$(filter-out tar,$(tools)))

noinst_DATA = $(tools:%=$(top_builddir)/html/virt-%.1.html)

virt-%.1: virt-%
	$(top_builddir)/podwrapper.sh \
	  --man $@ \
	  $<

$(top_builddir)/html/virt-%.1.html: virt-%
	$(top_builddir)/podwrapper.sh \
	  --html $@ \
	  $<

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir) \
	PERL5LIB=$(top_builddir)/perl/blib/lib:$(top_builddir)/perl/blib/arch

TESTS = test-virt-list-filesystems.sh \
	test-virt-make-fs.sh \
	test-virt-tar.sh

endif

# Make symlinks from virt-foo.pl to virt-foo.  This is just to keep
# xgettext happy since it uses the file extension to determine the
# implementation language of a file.

all-local: $(tools:%=virt-%.pl)

virt-%.pl: virt-%
	ln -sf $< $@
