# libguestfs
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

EXTRA_DIST = \
	kmod.whitelist.in \
	packagelist.in \
	init \
	debian/modules/y0_install-guestfsd \
	debian/modules/z99_final-cleanups \
	debian/debirf.conf.in \
	make.sh.in

# Build the root filesystem (appliance).
# Currently this is arch-dependent, so it seems like putting it in
# $(libdir) is best.  When we build cross-architecture filesystems we
# should probably move them to $(datadir).
fsdir = $(libdir)/guestfs
superminfsdir = $(libdir)/guestfs/supermin.d

# These are the resulting output files from the whole process:
#   VMLINUZ        kernel for the full appliance
#   INITRAMFSIMG   initramfs (ie. root fs) for the full appliance
# For details of the supermin appliance, read the README file.
fs_DATA = $(INITRAMFSIMG) $(VMLINUZ)
if SUPERMIN
fs_DATA += kmod.whitelist
superminfs_DATA = \
	supermin.d/base.img \
	supermin.d/daemon.img \
	supermin.d/hostfiles
endif

# Don't change these names - they must be the same as in '*.sh' scripts.
INITRAMFSIMG = initramfs.$(host_cpu).img
VMLINUZ = vmlinuz.$(host_cpu)

# This is for building the normal appliance:
$(INITRAMFSIMG) $(VMLINUZ): $(top_builddir)/initramfs/fakeroot.log

$(top_builddir)/initramfs/fakeroot.log: make.sh kmod.whitelist packagelist
	mv $(INITRAMFSIMG) $(INITRAMFSIMG).bak 2>/dev/null; :
	mv $(VMLINUZ) $(VMLINUZ).bak 2>/dev/null; :
	if ! bash make.sh; then rm -f $@; exit 1; fi

# This used to be a configure-generated file (as is update.sh still).
# However config.status always touches the destination file, which
# means the appliance got rebuilt too often.
make.sh: make.sh.in
	cd $(top_builddir) && \
	  ./config.status --file=appliance/$@-t:appliance/$<
	chmod +x $@-t
	mv $@-t $@

$(INITRAMFSIMG): $(top_builddir)/initramfs/fakeroot.log $(top_builddir)/daemon/guestfsd init update.sh
	rm -f $@
	bash update.sh
	touch $@

kmod.whitelist: kmod.whitelist.in
	grep -v '^[[:space:]]*$$' < $< | grep -v '^#' > $@

packagelist: packagelist.in
	cpp -undef -D$(DIST)=1 < $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@

# This is for building the supermin appliance.  It has to be enabled
# specifically with './configure --enable-supermin'.  You really need
# to read the README file.

if SUPERMIN

supermin.d/base.img supermin.d/hostfiles: stamp-supermin
stamp-supermin: $(INITRAMFSIMG)
	mkdir -p supermin.d
	rm -f $@ supermin.d/base.img supermin.d/hostfiles
	febootstrap-to-supermin $(top_builddir)/initramfs supermin.d/base.img supermin.d/hostfiles
	if grep -q /usr/share/augeas/lenses supermin.d/hostfiles; then \
		echo "./usr/share/augeas/lenses/*.aug" >> supermin.d/hostfiles; \
	fi
	touch $@

supermin.d/daemon.img: $(INITRAMFSIMG)
	mkdir -p supermin.d
	rm -f $@ $@-t
	(cd $(top_builddir)/initramfs && \
	  echo -e "sbin\nsbin/guestfsd" | cpio --quiet -o -H newc ) > $@-t
	mv $@-t $@
endif

# Extra symlinks needed by the Debian appliance.
debirf_symlinks = \
	a0_prep-root \
	install-kernel \
	z0_remove-aptitude \
	z0_remove-locales \
	z1_clean-root
noinst_DATA = $(debirf_symlinks:%=debian/modules/%)
$(debirf_symlinks:%=debian/modules/%): stamp-debirf-modules
stamp-debirf-modules:
	mkdir -p debian/modules
	for f in $(debirf_symlinks); do \
	  ln -sf /usr/share/debirf/modules/$$f debian/modules/$$f; \
	done
	touch $@

# Make clean.

CLEANFILES = packagelist kmod.whitelist

clean-local:
	rm -f supermin.d/*
	rm -rf $(top_builddir)/initramfs
