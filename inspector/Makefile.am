# libguestfs virt-inspector
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

include $(top_srcdir)/subdir-rules.mk

EXAMPLE_XML = \
	example1.xml example2.xml example3.xml \
	example4.xml example5.xml example6.xml

EXTRA_DIST = \
	run-inspector-locally \
	virt-inspector

docdir = @docdir@
dist_doc_DATA = \
	virt-inspector.rng \
	$(EXAMPLE_XML)

if HAVE_INSPECTOR

bin_SCRIPTS = virt-inspector
man_MANS = virt-inspector.1

noinst_DATA = \
	$(top_builddir)/html/virt-inspector.1.html

virt-inspector.1: virt-inspector
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-inspector.1.html: virt-inspector
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --title 'virt-inspector, display OS version, kernel, drivers, mount points, applications, etc. in a virtual machine' \
	  --htmldir html \
	  --outfile html/virt-inspector.1.html \
	  inspector/$<

if HAVE_XMLLINT

TESTS = $(EXAMPLE_XML)
TESTS_ENVIRONMENT = $(XMLLINT) --noout --relaxng virt-inspector.rng

endif

endif

# Make symlink from virt-inspector.pl to virt-inspector.  This is just
# to keep xgettext happy since it uses the file extension to determine
# the implementation language of a file.

all-local: virt-inspector.pl

virt-inspector.pl: virt-inspector
	ln -sf $< $@
