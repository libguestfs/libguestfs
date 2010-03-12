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
	debian/modules/install_kernel \
	debian/modules/y0_install-guestfsd \
	debian/modules/z99_final-cleanups \
	debian/debirf.conf.in \
	make.sh.in

# Build the root filesystem (appliance).
# Currently this is arch-dependent, so it seems like putting it in
# $(libdir) is best.  When we build cross-architecture filesystems we
# should probably move them to $(datadir).
fsdir = $(libdir)/guestfs
fs_DATA = $(APPLIANCE_FILES)

# These are the resulting output files from the whole process:
#   VMLINUZ        kernel for the full appliance
#   INITRAMFSIMG   initramfs (ie. root fs) for the full appliance
# For details of the supermin appliance, read the README file:
#   SUPERMINIMG    initramfs (ie. partial root fs) for the supermin appliance
#   SUPERMINFILES  list of missing files (the ones we will pull out of the
#                    host filesystem at runtime) in the supermin appliance
APPLIANCE_FILES = $(INITRAMFSIMG) $(VMLINUZ)
if SUPERMIN
APPLIANCE_FILES += $(SUPERMINIMG) $(SUPERMINFILES) kmod.whitelist
bin_PROGRAMS = libguestfs-supermin-helper
libguestfs_supermin_helper_SOURCES = \
	libguestfs-supermin-helper.c ../gnulib/lib/xalloc-die.c
libguestfs_supermin_helper_CFLAGS = \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
libguestfs_supermin_helper_LDADD = \
	../gnulib/lib/libgnu.la
endif

# Don't change these names - they must be the same as in '*.sh' scripts.
INITRAMFSIMG = initramfs.$(REPO).$(host_cpu).img
VMLINUZ = vmlinuz.$(REPO).$(host_cpu)
if SUPERMIN
SUPERMINIMG = initramfs.$(REPO).$(host_cpu).supermin.img
SUPERMINFILES = initramfs.$(REPO).$(host_cpu).supermin.hostfiles
endif

# This is for building the normal appliance:
$(INITRAMFSIMG) $(VMLINUZ): $(top_builddir)/initramfs/fakeroot.log

$(top_builddir)/initramfs/fakeroot.log: make.sh kmod.whitelist packagelist $(top_builddir)/daemon/guestfsd
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

# First we need to decide which files go in and out of the supermin
# appliance.  This decision is made by 'supermin-split.sh'.
$(SUPERMINFILES): supermin.incfiles
supermin.incfiles: $(top_builddir)/initramfs/fakeroot.log $(top_builddir)/daemon/guestfsd supermin-split.sh
	rm -f supermin.incfiles $(SUPERMINFILES)
	bash supermin-split.sh

# Second we need to create a supermin appliance with just the included
# files (leaving out the host files, which we'll add back at runtime).
$(SUPERMINIMG): supermin.incfiles supermin-make.sh
	rm -f $@
	bash supermin-make.sh

endif

# Extra symlinks needed by the Debian appliance.
debirf_symlinks = \
	a0_prep-root \
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

#----------------------------------------------------------------------
# Extra rules for testing the appliance.

# Test-boot the appliance.

test-boot: emptydisk
	qemu-system-$(host_cpu) \
	  -m 384 \
	  -kernel $(VMLINUZ) -initrd $(INITRAMFSIMG) \
	  -hda emptydisk

emptydisk:
	rm -f emptydisk
	dd if=/dev/zero of=emptydisk bs=1024 count=1440
	echo 0, | sfdisk -q -C 80 -H 2 -S 18 emptydisk > /dev/null

# This is a more realistic test boot command line which better
# reflects what the library does.

test-boot-realistic: emptydisk
	qemu-system-$(host_cpu) \
	  -m 384 \
	  -kernel $(VMLINUZ) -initrd $(INITRAMFSIMG) \
	  -hda emptydisk \
	  -append "console=ttyS0 guestfs=10.0.2.4:6666 guestfs_rescue=1" \
	  -nographic \
	  -serial stdio \
	  -net channel,6666:unix:/tmp/sock,server,nowait \
	  -net user,vlan=0 \
	  -net nic,model=virtio,vlan=0

# Make clean.

CLEANFILES = $(APPLIANCE_FILES) packagelist kmod.whitelist supermin.incfiles

clean-local:
	rm -rf $(top_builddir)/initramfs
