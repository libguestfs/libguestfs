# libguestfs documentation
# Copyright (C) 2010-2015 Red Hat Inc.
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

EXTRA_DIST = \
	guestfs-faq.pod \
	guestfs-performance.pod \
	guestfs-recipes.pod \
	guestfs-release-notes.pod \
	guestfs-testing.pod \
	README

CLEANFILES = \
	stamp-guestfs-faq.pod \
	stamp-guestfs-performance.pod \
	stamp-guestfs-recipes.pod \
	stamp-guestfs-release-notes.pod \
	stamp-guestfs-testing.pod

man_MANS = \
	guestfs-faq.1 \
	guestfs-performance.1 \
	guestfs-recipes.1 \
	guestfs-release-notes.1 \
	guestfs-testing.1
noinst_DATA = \
	$(top_builddir)/html/guestfs-faq.1.html \
	$(top_builddir)/html/guestfs-performance.1.html \
	$(top_builddir)/html/guestfs-recipes.1.html \
	$(top_builddir)/html/guestfs-release-notes.1.html \
	$(top_builddir)/html/guestfs-testing.1.html

guestfs-faq.1 $(top_builddir)/html/guestfs-faq.1.html: stamp-guestfs-faq.pod

stamp-guestfs-faq.pod: guestfs-faq.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-faq.1 \
	  --html $(top_builddir)/html/guestfs-faq.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-performance.1 $(top_builddir)/html/guestfs-performance.1.html: stamp-guestfs-performance.pod

stamp-guestfs-performance.pod: guestfs-performance.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-performance.1 \
	  --html $(top_builddir)/html/guestfs-performance.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-recipes.1 $(top_builddir)/html/guestfs-recipes.1.html: stamp-guestfs-recipes.pod

stamp-guestfs-recipes.pod: guestfs-recipes.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-recipes.1 \
	  --html $(top_builddir)/html/guestfs-recipes.1.html \
	  --license examples \
	  $<
	touch $@

guestfs-release-notes.1 guestfs-release-notes.txt $(top_builddir)/html/guestfs-release-notes.1.html: stamp-guestfs-release-notes.pod

stamp-guestfs-release-notes.pod: guestfs-release-notes.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-release-notes.1 \
	  --html $(top_builddir)/html/guestfs-release-notes.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

guestfs-testing.1 $(top_builddir)/html/guestfs-testing.1.html: stamp-guestfs-testing.pod

stamp-guestfs-testing.pod: guestfs-testing.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-testing.1 \
	  --html $(top_builddir)/html/guestfs-testing.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@
