# libguestfs cloning tools
# Copyright (C) 2011 Red Hat Inc.
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

EXTRA_DIST = \
	test-virt-sysprep.sh \
	virt-sysprep.pod

CLEANFILES = stamp-virt-sysprep.pod

bin_SCRIPTS = virt-sysprep

# Manual pages and HTML files for the website.
man_MANS = virt-sysprep.1
noinst_DATA = $(top_builddir)/html/virt-sysprep.1.html

virt-sysprep.1 $(top_builddir)/html/virt-sysprep.1.html: stamp-virt-sysprep.pod

stamp-virt-sysprep.pod: virt-sysprep.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-sysprep.1 \
	  --html $(top_builddir)/html/virt-sysprep.1.html \
	  $<
	touch $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir)

TESTS = test-virt-sysprep.sh
