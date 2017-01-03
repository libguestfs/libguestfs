# libguestfs virt-* tools
# Copyright (C) 2009-2018 Red Hat Inc.
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

tools = \
	list-filesystems \
	list-partitions \
	tar \
	win-reg

EXTRA_DIST = \
	$(tools:%=virt-%) \
	test-virt-*.sh

if HAVE_TOOLS

bin_SCRIPTS = $(tools:%=virt-%)

# Manual pages and HTML files for the website.

man_MANS = \
	virt-list-filesystems.1 \
	virt-list-partitions.1 \
	virt-tar.1 \
	virt-win-reg.1

virt-list-filesystems.1 $(top_builddir)/website/virt-list-filesystems.1.html: stamp-virt-list-filesystems.pod

stamp-virt-list-filesystems.pod: virt-list-filesystems
	$(PODWRAPPER) \
	  --man virt-list-filesystems.1 \
	  --html $(top_builddir)/website/virt-list-filesystems.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-list-partitions.1 $(top_builddir)/website/virt-list-partitions.1.html: stamp-virt-list-partitions.pod

stamp-virt-list-partitions.pod: virt-list-partitions
	$(PODWRAPPER) \
	  --man virt-list-partitions.1 \
	  --html $(top_builddir)/website/virt-list-partitions.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-tar.1 $(top_builddir)/website/virt-tar.1.html: stamp-virt-tar.pod

stamp-virt-tar.pod: virt-tar
	$(PODWRAPPER) \
	  --man virt-tar.1 \
	  --html $(top_builddir)/website/virt-tar.1.html \
	  --license GPLv2+ \
	  --warning custom \
	  $<
	touch $@

virt-win-reg.1 $(top_builddir)/website/virt-win-reg.1.html: stamp-virt-win-reg.pod

stamp-virt-win-reg.pod: virt-win-reg
	$(PODWRAPPER) \
	  --man virt-win-reg.1 \
	  --html $(top_builddir)/website/virt-win-reg.1.html \
	  --license GPLv2+ \
	  --warning custom \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = test-virt-list-filesystems.sh \
	test-virt-tar.sh
endif ENABLE_APPLIANCE

endif

all-local:
	for f in $(tools:%=tools/virt-%); do echo $$f; done > $(top_srcdir)/po/POTFILES-pl
