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

EXTRA_DIST = \
	make.sh update.sh

# Build the root filesystem (appliance).
# Currently this is arch-dependent, so it seems like putting it in
# $(libdir) is best.  When we build cross-architecture filesystems we
# should probably move them to $(datadir).

fsdir = $(libdir)/guestfs

INITRAMFSIMG = initramfs.$(REPO).$(host_cpu).img
VMLINUZ = vmlinuz.$(REPO).$(host_cpu)

fs_DATA =  $(INITRAMFSIMG) $(VMLINUZ)

$(INITRAMFSIMG) $(VMLINUZ): $(top_builddir)/initramfs/fakeroot.log

$(top_builddir)/initramfs/fakeroot.log: make.sh
	-mv $(INITRAMFSIMG) $(INITRAMFSIMG).bak
	-mv $(VMLINUZ) $(VMLINUZ).bak
	if ! bash make.sh; then rm -f $@; exit 1; fi

$(INITRAMFSIMG): $(top_builddir)/initramfs/fakeroot.log $(top_builddir)/daemon/guestfsd
	rm -f $@
	bash update.sh
	touch $@

make.sh: make.sh.in
	cd .. && ./config.status appliance/$@

# Test-boot the image.

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
	  -append "console=ttyS0 guestfs=10.0.2.4:6666" \
	  -nographic \
	  -serial stdio \
	  -net channel,6666:unix:/tmp/sock,server,nowait \
	  -net user,vlan=0 \
	  -net nic,model=virtio,vlan=0

# Make clean.

CLEANFILES = $(fs_DATA)

clean-local:
	rm -rf $(top_builddir)/initramfs

