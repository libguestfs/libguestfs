# libguestfs translations of man pages and POD files
# Copyright (C) 2010-2012 Red Hat Inc.
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

# Note that each Makefile.am in po-docs/$lang/Makefile.am should be
# identical.  If you create a new $lang.po, create the $lang/
# subdirectory and copy the Makefile.am from an existing language.

LINGUA = $(shell basename -- `pwd`)

CLEANFILES = *.1 *.3

MANPAGES = \
	guestfs.3 \
	guestfish.1 \
	virt-alignment-scan.1 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-tar-in.1 \
	virt-tar-out.1 \
	libguestfs-test-tool.1 \
	guestmount.1 \
	$(patsubst %.pl,%.1,$(wildcard virt-*.pl)) \
	virt-cat.1 \
	virt-df.1 \
	virt-edit.1 \
	virt-filesystems.1 \
	virt-inspector.1 \
	virt-ls.1 \
	virt-rescue.1 \
	virt-resize.1 \
	virt-sparsify.1 \
	virt-sysprep.1

# Ship the POD files and the translated manpages in the tarball.  This
# just simplifies building from the tarball, at a small cost in extra
# size.
EXTRA_DIST = \
	$(MANPAGES) \
	$(shell for f in `cat ../podfiles`; do basename $$f; done)

all-local: $(MANPAGES)

guestfs.3: guestfs.pod guestfs-actions.pod guestfs-availability.pod guestfs-structs.pod
	$(top_builddir)/podwrapper.sh \
	  --section 3 \
	  --man $@ \
	  --insert $(srcdir)/guestfs-actions.pod:@ACTIONS@ \
	  --insert $(srcdir)/guestfs-availability.pod:@AVAILABILITY@ \
	  --insert $(srcdir)/guestfs-structs.pod:@STRUCTS@ \
	  $<

guestfish.1: guestfish.pod guestfish-actions.pod guestfish-commands.pod
	$(top_builddir)/podwrapper.sh \
	  --man $@ \
	  --insert $(srcdir)/guestfish-actions.pod:@ACTIONS@ \
	  --insert $(srcdir)/guestfish-commands.pod:@FISH_COMMANDS@ \
	  $<

%.1: %.pod
	$(top_builddir)/podwrapper.sh --man $@ $<

%.1: %.pl
	$(top_builddir)/podwrapper.sh --man $@ $<

# Ensure that the first time we build from git, since guestfs.pod
# hasn't been built yet, build it.
guestfs.pod:
	if [ ! -f guestfs.pod ]; then make -C .. update-po; fi

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestfish.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestmount.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 virt-*.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(INSTALL) -m 0644 guestfs.3 $(DESTDIR)$(mandir)/$(LINGUA)/man3
