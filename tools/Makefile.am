# libguestfs virt-* tools
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

tools = cat df edit ls rescue tar win-reg

EXTRA_DIST = \
	run-locally \
	$(tools:%=virt-%)

if HAVE_TOOLS

bin_SCRIPTS = $(tools:%=virt-%)

# XXX Bug in automake?  If you list virt-cat.1 explicitly, then it
# builds and installs the man pages.  However if this is removed,
# then the man pages are neither built nor installed.
man_MANS = virt-cat.1 $(patsubst %,virt-%.1,$(filter-out cat,$(tools)))

noinst_DATA = $(tools:%=$(top_builddir)/html/virt-%.1.html)

virt-%.1: virt-%
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-%.1.html: virt-%
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/$<.1.html \
	  tools/$<

endif
