# libguestfs virt-p2v ISO
# Copyright (C) 2009-2014 Red Hat Inc.
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

CLEANFILES = \
	*~ \
	kickstart-target.sh \
	launch-virt-p2v \
	p2v.ks \
	stamp-guestfs-p2v-iso.pod \
	virt-builder-target.sh

EXTRA_DIST = \
	guestfs-p2v-iso.pod \
	guestfs-p2v-iso.txt \
	issue \
	kickstart-target.sh.in \
	launch-virt-p2v.in \
	p2v.ks.in \
	p2v.service \
	virt-builder-target.sh.in

# You need to read 'guestfs-p2v-iso.txt' before trying any of these
# targets.

virt-builder-target: virt-builder-target.sh launch-virt-p2v
	srcdir=$(srcdir) $(top_builddir)/run ./virt-builder-target.sh

# Deal with stupid autotools libexecdir-not-expandable crap.
launch-virt-p2v: launch-virt-p2v.in
	rm -f $@ $@-t
	sed 's,@''libexecdir@,$(libexecdir),g' < $< > $@-t
	chmod 0555 $@-t
	mv $@-t $@

kickstart-target: kickstart-target.sh launch-virt-p2v
	srcdir=$(srcdir) $(top_builddir)/run ./kickstart-target.sh

man_MANS = guestfs-p2v-iso.1
noinst_DATA = $(top_builddir)/html/guestfs-p2v-iso.1.html

guestfs-p2v-iso.1 guestfs-p2v-iso.txt $(top_builddir)/html/guestfs-p2v-iso.1.html: stamp-guestfs-p2v-iso.pod

stamp-guestfs-p2v-iso.pod: guestfs-p2v-iso.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-p2v-iso.1 \
	  --text guestfs-p2v-iso.txt \
	  --html $(top_builddir)/html/guestfs-p2v-iso.1.html \
	  --license GPLv2+ \
	  $<
	touch $@
