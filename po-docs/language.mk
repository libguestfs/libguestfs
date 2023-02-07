# libguestfs translations of man pages and POD files
# Copyright (C) 2010-2023 Red Hat Inc.
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

# Common logic for generating translated documentation.

include $(top_srcdir)/subdir-rules.mk

LINGUA = $(shell basename -- `pwd`)

# Before 1.23.23, the old Perl tools were called *.pl.
CLEANFILES += *.pl *.pod

MANPAGES = \
	guestfish.1 \
	guestfs.3 \
	guestfs-building.1 \
	guestfs-erlang.3 \
	guestfs-examples.3 \
	guestfs-faq.1 \
	guestfs-hacking.1 \
	guestfs-internals.1 \
	guestfs-golang.3 \
	guestfs-java.3 \
	guestfs-lua.3 \
	guestfs-ocaml.3 \
	guestfs-performance.1 \
	guestfs-perl.3 \
	guestfs-python.3 \
	guestfs-recipes.1 \
	guestfs-release-notes-1.42.1 \
	guestfs-release-notes-1.40.1 \
	guestfs-release-notes-1.38.1 \
	guestfs-release-notes-1.36.1 \
	guestfs-release-notes-1.34.1 \
	guestfs-release-notes-1.32.1 \
	guestfs-release-notes-1.30.1 \
	guestfs-release-notes-1.28.1 \
	guestfs-release-notes-1.26.1 \
	guestfs-release-notes-1.24.1 \
	guestfs-release-notes-1.22.1 \
	guestfs-release-notes-1.20.1 \
	guestfs-release-notes-1.18.1 \
	guestfs-release-notes-1.16.1 \
	guestfs-release-notes-1.14.1 \
	guestfs-release-notes-1.12.1 \
	guestfs-release-notes-1.10.1 \
	guestfs-release-notes-1.8.1 \
	guestfs-release-notes-1.6.1 \
	guestfs-release-notes-1.4.1 \
	guestfs-release-notes-historical.1 \
	guestfs-ruby.3 \
	guestfs-security.1 \
	guestfs-testing.1 \
	guestfsd.8 \
	guestmount.1 \
	guestunmount.1 \
	libguestfs-make-fixed-appliance.1 \
	libguestfs-test-tool.1 \
	libguestfs-tools.conf.5 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-rescue.1 \
	virt-tar-in.1 \
	virt-tar-out.1

podfiles := $(shell for f in `cat $(top_srcdir)/po-docs/podfiles`; do echo `basename $$f .pod`.pod; done)

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

# XXX --warning parameter is not passed, so no WARNING section is
# generated in any translated manual.  To fix this we need to expand
# out all the %.1 pattern rules below.

guestfish.1: guestfish.pod guestfish-actions.pod guestfish-commands.pod guestfish-prepopts.pod blocksize-option.pod key-option.pod keys-from-stdin-option.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  $<

virt-builder.1: virt-builder.pod customize-synopsis.pod customize-options.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(srcdir)/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  $<

virt-customize.1: virt-customize.pod customize-synopsis.pod customize-options.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(srcdir)/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  $<

virt-sysprep.1: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
          --insert $(srcdir)/sysprep-extra-options.pod:__EXTRA_OPTIONS__ \
          --insert $(srcdir)/sysprep-operations.pod:__OPERATIONS__ \
	  $<

virt-p2v.1: virt-p2v.pod virt-p2v-kernel-config.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/virt-p2v-kernel-config.pod:__KERNEL_CONFIG__ \
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

%.5: %.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --section 5 \
	  $<

%.8: %.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --section 8 \
	  $<

# Note: po4a puts the following junk at the top of every POD file it
# generates:
#  - a warning
#  - a probably bogus =encoding line
# Remove both.
# XXX Fix po4a so it doesn't do this.
%.pod: $(srcdir)/../$(LINGUA).po
	$(guestfs_am_v_po4a_translate)$(PO4A_TRANSLATE) \
	  -f pod \
	  -M utf-8 -L utf-8 \
	  -k 0 \
	  -m $(top_srcdir)/$(shell grep '/$(notdir $@)$$' $(top_srcdir)/po-docs/podfiles) \
	  -p $< \
	  | $(SED) '0,/^=encoding/d' > $@

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 $(srcdir)/*.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(INSTALL) -m 0644 $(srcdir)/*.3 $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man5
	$(INSTALL) -m 0644 $(srcdir)/*.5 $(DESTDIR)$(mandir)/$(LINGUA)/man5
