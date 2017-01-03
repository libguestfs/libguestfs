# libguestfs documentation
# Copyright (C) 2010-2018 Red Hat Inc.
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
	C_SOURCE_FILES \
	guestfs-building.pod \
	guestfs-faq.pod \
	guestfs-hacking.pod \
	guestfs-internals.pod \
	guestfs-performance.pod \
	guestfs-recipes.pod \
	guestfs-release-notes.pod \
	guestfs-security.pod \
	guestfs-testing.pod \
	make-internal-documentation.pl \
	README

CLEANFILES += \
	internal-documentation.pod

man_MANS = \
	guestfs-building.1 \
	guestfs-faq.1 \
	guestfs-hacking.1 \
	guestfs-internals.1 \
	guestfs-performance.1 \
	guestfs-recipes.1 \
	guestfs-release-notes.1 \
	guestfs-security.1 \
	guestfs-testing.1
noinst_DATA = \
	$(top_builddir)/website/guestfs-building.1.html \
	$(top_builddir)/website/guestfs-faq.1.html \
	$(top_builddir)/website/guestfs-hacking.1.html \
	$(top_builddir)/website/guestfs-internals.1.html \
	$(top_builddir)/website/guestfs-performance.1.html \
	$(top_builddir)/website/guestfs-recipes.1.html \
	$(top_builddir)/website/guestfs-release-notes.1.html \
	$(top_builddir)/website/guestfs-security.1.html \
	$(top_builddir)/website/guestfs-testing.1.html

guestfs-building.1 $(top_builddir)/website/guestfs-building.1.html: stamp-guestfs-building.pod

stamp-guestfs-building.pod: guestfs-building.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-building.1 \
	  --html $(top_builddir)/website/guestfs-building.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-faq.1 $(top_builddir)/website/guestfs-faq.1.html: stamp-guestfs-faq.pod

stamp-guestfs-faq.pod: guestfs-faq.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-faq.1 \
	  --html $(top_builddir)/website/guestfs-faq.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-hacking.1 $(top_builddir)/website/guestfs-hacking.1.html: stamp-guestfs-hacking.pod

stamp-guestfs-hacking.pod: guestfs-hacking.pod internal-documentation.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-hacking.1 \
	  --html $(top_builddir)/website/guestfs-hacking.1.html \
	  --insert internal-documentation.pod:__INTERNAL_DOCUMENTATION__ \
	  --license LGPLv2+ \
	  $<
	touch $@

source_files := $(shell cat $(srcdir)/C_SOURCE_FILES)

internal-documentation.pod: $(source_files:%=$(top_srcdir)/%)
	rm -f $@ $@-t
	./make-internal-documentation.pl \
	    --srcdir $(top_srcdir) \
	    -o $@-t \
	    $(source_files)
	mv $@-t $@

guestfs-internals.1 $(top_builddir)/website/guestfs-internals.1.html: stamp-guestfs-internals.pod

stamp-guestfs-internals.pod: guestfs-internals.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-internals.1 \
	  --html $(top_builddir)/website/guestfs-internals.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-performance.1 $(top_builddir)/website/guestfs-performance.1.html: stamp-guestfs-performance.pod

stamp-guestfs-performance.pod: guestfs-performance.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-performance.1 \
	  --html $(top_builddir)/website/guestfs-performance.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-recipes.1 $(top_builddir)/website/guestfs-recipes.1.html: stamp-guestfs-recipes.pod

stamp-guestfs-recipes.pod: guestfs-recipes.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-recipes.1 \
	  --html $(top_builddir)/website/guestfs-recipes.1.html \
	  --license examples \
	  $<
	touch $@

guestfs-release-notes.1 guestfs-release-notes.txt $(top_builddir)/website/guestfs-release-notes.1.html: stamp-guestfs-release-notes.pod

stamp-guestfs-release-notes.pod: guestfs-release-notes.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-release-notes.1 \
	  --html $(top_builddir)/website/guestfs-release-notes.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

guestfs-security.1 $(top_builddir)/website/guestfs-security.1.html: stamp-guestfs-security.pod

stamp-guestfs-security.pod: guestfs-security.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-security.1 \
	  --html $(top_builddir)/website/guestfs-security.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@

guestfs-testing.1 $(top_builddir)/website/guestfs-testing.1.html: stamp-guestfs-testing.pod

stamp-guestfs-testing.pod: guestfs-testing.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-testing.1 \
	  --html $(top_builddir)/website/guestfs-testing.1.html \
	  --license LGPLv2+ \
	  $<
	touch $@
