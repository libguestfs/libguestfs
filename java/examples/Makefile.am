# libguestfs Java examples
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

EXTRA_DIST = \
	LICENSE \
	CreateDisk.java \
	InspectVM.java \
	guestfs-java.pod

CLEANFILES = \
	*.class \
	stamp-guestfs-java.pod

man_MANS = guestfs-java.3
noinst_DATA = $(top_builddir)/html/guestfs-java.3.html

guestfs-java.3 $(top_builddir)/html/guestfs-java.3.html: stamp-guestfs-java.pod

stamp-guestfs-java.pod: guestfs-java.pod CreateDisk.java InspectVM.java
	$(top_builddir)/podwrapper.sh \
	  --section 3 \
	  --man guestfs-java.3 \
	  --html $(top_builddir)/html/guestfs-java.3.html \
	  --verbatim $(srcdir)/CreateDisk.java:@EXAMPLE1@ \
	  --verbatim $(srcdir)/InspectVM.java:@EXAMPLE2@ \
	  $<
	touch $@

if HAVE_JAVA

noinst_SCRIPTS = CreateDisk.class InspectVM.class

%.class: %.java
	$(JAVAC) $(JAVAC_FLAGS) -classpath ../libguestfs-$(VERSION).jar $<

endif
