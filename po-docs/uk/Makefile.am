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

CLEANFILES = *.1 *.3 stamp-update-po

MANPAGES = \
	guestfish.1 \
	guestfs.3 \
	guestfs-erlang.3 \
	guestfs-examples.3 \
	guestfs-faq.1 \
	guestfs-java.3 \
	guestfs-ocaml.3 \
	guestfs-performance.1 \
	guestfs-perl.3 \
	guestfs-python.3 \
	guestfs-recipes.1 \
	guestfs-ruby.3 \
	guestfs-testing.1 \
	guestmount.1 \
	libguestfs-make-fixed-appliance.1 \
	libguestfs-test-tool.1 \
	virt-alignment-scan.1 \
	virt-cat.1 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-df.1 \
	virt-edit.1 \
	virt-filesystems.1 \
	virt-format.1 \
	virt-inspector.1 \
	virt-list-filesystems.1 \
	virt-list-partitions.1 \
	virt-ls.1 \
	virt-make-fs.1 \
	virt-rescue.1 \
	virt-resize.1 \
	virt-sparsify.1 \
	virt-sysprep.1 \
	virt-tar.1 \
	virt-tar-in.1 \
	virt-tar-out.1 \
	virt-win-reg.1

podfiles := $(shell for f in `cat ../podfiles`; do basename $$f; done)

# Ship the POD files and the translated manpages in the tarball.  This
# just simplifies building from the tarball, at a small cost in extra
# size.
EXTRA_DIST = \
	$(MANPAGES) \
	$(podfiles)

all-local: $(MANPAGES)

guestfs.3: guestfs.pod guestfs-actions.pod guestfs-availability.pod guestfs-structs.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --section 3 \
	  --license LGPLv2+ \
	  --insert $(srcdir)/guestfs-actions.pod:__ACTIONS__ \
	  --insert $(srcdir)/guestfs-availability.pod:__AVAILABILITY__ \
	  --insert $(srcdir)/guestfs-structs.pod:__STRUCTS__ \
	  $<

guestfish.1: guestfish.pod guestfish-actions.pod guestfish-commands.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/guestfish-actions.pod:__ACTIONS__ \
	  --insert $(srcdir)/guestfish-commands.pod:__FISH_COMMANDS__ \
	  $<

virt-sysprep.1: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
          --insert sysprep-extra-options.pod:__EXTRA_OPTIONS__ \
          --insert sysprep-operations.pod:__OPERATIONS__ \
	  $<

%.1: %.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  $<

%.3: %.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --section 3 \
	  $<

%.1: %.pl
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  $<

# Ensure that the first time we build from git, since guestfs.pod
# hasn't been built yet, build it.
$(podfiles): stamp-update-po

stamp-update-po:
	if [ ! -f guestfs.pod ]; then make -C .. update-po; fi
	touch $@

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 *.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(INSTALL) -m 0644 *.3 $(DESTDIR)$(mandir)/$(LINGUA)/man3
