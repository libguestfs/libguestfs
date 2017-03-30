# libguestfs virt-p2v
# Copyright (C) 2009-2017 Red Hat Inc.
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

EXTRA_DIST = \
	$(TESTS) $(SLOW_TESTS) \
	dependencies.m4 \
	issue \
	kiwi-config.sh \
	kiwi-config.xml.in \
	launch-virt-p2v \
	p2v.ks.in \
	p2v.service \
	test-virt-p2v-docs.sh \
	test-virt-p2v-pxe.sshd_config.in \
	test-virt-p2v-scp.sh \
	test-virt-p2v-ssh.sh \
	virt-p2v.pod \
	virt-p2v-make-disk.in \
	virt-p2v-make-disk.pod \
	virt-p2v-make-kickstart.in \
	virt-p2v-make-kickstart.pod \
	virt-p2v-make-kiwi.in \
	virt-p2v-make-kiwi.pod

# Don't clean ssh_host_rsa_key{,.pub} or id_rsa{,.pub} since those
# consume system entropy to regenerate.
CLEANFILES += \
	$(dependencies_files) \
	stamp-test-virt-p2v-pxe-data-files \
	stamp-test-virt-p2v-pxe-kernel \
	test-virt-p2v-pxe.authorized_keys \
	test-virt-p2v-pxe.img \
	test-virt-p2v-pxe.vmlinuz \
	test-virt-p2v-pxe.initramfs \
	test-virt-p2v-pxe.sshd_config \
	virt-p2v.img \
	virt-p2v.xz

# Although virt-p2v is a regular binary, it is not usually installed
# in /usr/bin since it only functions when contained in an ISO or PXE
# image which is used to boot the physical machine (since otherwise
# virt-p2v would not be able to get a consistent snapshot of the
# physical disks).  Also we don't want the naked binary to appear on
# the host, which would cause various Gtk dependencies to be pulled
# in, so it must be compressed.
virtp2vlibdir = $(libdir)/virt-p2v
virtp2vlib_DATA = virt-p2v.xz

virt-p2v.xz: virt-p2v
	rm -f $@ $@-t
	xz --best --keep --stdout $< > $@-t
	mv $@-t $@

noinst_PROGRAMS = virt-p2v

virt_p2v_SOURCES = \
	about-authors.c \
	about-license.c \
	config.c \
	conversion.c \
	gui.c \
	gui-gtk2-compat.h \
	gui-gtk3-compat.h \
	inhibit.c \
	kernel.c \
	kernel-cmdline.c \
	main.c \
	nbd.c \
	p2v.h \
	ssh.c \
	utils.c \
	whole-file.c

virt_p2v_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/common/miniexpect -I$(top_builddir)/common/miniexpect \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_p2v_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(GTK_CFLAGS) \
	$(DBUS_CFLAGS)

virt_p2v_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/common/miniexpect/libminiexpect.la \
	$(PCRE_LIBS) \
	$(LIBXML2_LIBS) \
	$(GTK_LIBS) \
	$(DBUS_LIBS) \
	../gnulib/lib/libgnu.la

# Scripts to build the disk image, USB key, or kickstart.
bin_SCRIPTS = virt-p2v-make-disk virt-p2v-make-kickstart virt-p2v-make-kiwi

dependencies_files = \
	dependencies.archlinux \
	dependencies.debian \
	dependencies.redhat \
	dependencies.suse

$(dependencies_files): dependencies.m4 ../config.status
	define=`echo $@ | $(SED) 's/dependencies.//;y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/'`; \
	m4 -D$$define=1 -DGTK_VERSION=$(GTK_VERSION) $< > $@-t
	mv $@-t $@

# Support files needed by the virt-p2v-make-* scripts.
virtp2vdatadir = $(datadir)/virt-p2v

virtp2vdata_DATA = \
	$(dependencies_files) \
	issue \
	kiwi-config.sh \
	kiwi-config.xml.in \
	launch-virt-p2v \
	p2v.ks.in \
	p2v.service

# Manual pages and HTML files for the website.
man_MANS = \
	virt-p2v.1 \
	virt-p2v-make-disk.1 \
	virt-p2v-make-kickstart.1 \
	virt-p2v-make-kiwi.1

noinst_DATA = \
	$(top_builddir)/website/virt-p2v.1.html \
	$(top_builddir)/website/virt-p2v-make-disk.1.html \
	$(top_builddir)/website/virt-p2v-make-kickstart.1.html \
	$(top_builddir)/website/virt-p2v-make-kiwi.1.html

virt-p2v.1 $(top_builddir)/website/virt-p2v.1.html: stamp-virt-p2v.pod

stamp-virt-p2v.pod: virt-p2v.pod
	$(PODWRAPPER) \
	  --man virt-p2v.1 \
	  --html $(top_builddir)/website/virt-p2v.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-p2v-make-disk.1 $(top_builddir)/website/virt-p2v-make-disk.1.html: stamp-virt-p2v-make-disk.pod

stamp-virt-p2v-make-disk.pod: virt-p2v-make-disk.pod
	$(PODWRAPPER) \
	  --man virt-p2v-make-disk.1 \
	  --html $(top_builddir)/website/virt-p2v-make-disk.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-p2v-make-kickstart.1 $(top_builddir)/website/virt-p2v-make-kickstart.1.html: stamp-virt-p2v-make-kickstart.pod

stamp-virt-p2v-make-kickstart.pod: virt-p2v-make-kickstart.pod
	$(PODWRAPPER) \
	  --man virt-p2v-make-kickstart.1 \
	  --html $(top_builddir)/website/virt-p2v-make-kickstart.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-p2v-make-kiwi.1 $(top_builddir)/website/virt-p2v-make-kiwi.1.html: stamp-virt-p2v-make-kiwi.pod

stamp-virt-p2v-make-kiwi.pod: virt-p2v-make-kiwi.pod
	$(PODWRAPPER) \
	  --man virt-p2v-make-kiwi.1 \
	  --html $(top_builddir)/website/virt-p2v-make-kiwi.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Run virt-p2v locally either directly or in a VM.
# See guestfs-hacking(1) section "Running virt-p2v"

PHYSICAL_MACHINE = $(abs_top_builddir)/test-data/phony-guests/windows.img

run-virt-p2v-directly: $(PHYSICAL_MACHINE)
	$(top_builddir)/run virt-p2v --test-disk=$(PHYSICAL_MACHINE)

run-virt-p2v-in-a-vm: virt-p2v.img $(PHYSICAL_MACHINE)
	$(QEMU) \
	  -M pc,accel=kvm:tcg \
	  -cpu host \
	  -m 1024 \
	  -drive id=hd0,file=$(PHYSICAL_MACHINE),format=raw,if=ide \
	  -device piix3-usb-uhci \
	  -drive id=usb0,file=$<,format=raw,snapshot=on,if=none \
	  -device usb-storage,bootindex=1,drive=usb0 \
	  -boot menu=on \
	  -netdev user,id=net0,net=169.254.0.0/16 \
	  -device virtio-net-pci,netdev=net0 \
	  -netdev user,id=net1 \
	  -device rtl8139,netdev=net1 \
	  -netdev user,id=net2 \
	  -device e1000,netdev=net2 \
	  $(QEMU_OPTIONS) \
	  &

run-virt-p2v-non-gui-conversion: stamp-test-virt-p2v-pxe-data-files
	SLOW=1 $(top_builddir)/run ./test-virt-p2v-pxe.sh

$(abs_top_builddir)/test-data/phony-guests/windows.img:
	$(MAKE) -C $(top_builddir)/test-data/phony-guests windows.img

virt-p2v.img: \
	    dependencies.m4 \
	    issue \
	    launch-virt-p2v \
	    p2v.service \
	    virt-p2v \
	    virt-p2v-make-disk
	$(top_builddir)/run virt-p2v-make-disk -o $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-p2v-cmdline.sh \
	test-virt-p2v-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-p2v.sh \
	test-virt-p2v-nbdkit.sh \
	$(SLOW_TESTS)
endif ENABLE_APPLIANCE

check-valgrind:
	make VG="@VG@" check

SLOW_TESTS = \
	test-virt-p2v-pxe.sh

check-slow: stamp-test-virt-p2v-pxe-data-files
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

stamp-test-virt-p2v-pxe-data-files: \
	    test-virt-p2v-pxe.authorized_keys \
	    test-virt-p2v-pxe.img \
	    test-virt-p2v-pxe.vmlinuz test-virt-p2v-pxe.initramfs \
	    test-virt-p2v-pxe.sshd_config \
	    test-virt-p2v-pxe.ssh_host_rsa_key \
	    test-virt-p2v-pxe.ssh_host_rsa_key.pub \
	    test-virt-p2v-pxe.id_rsa test-virt-p2v-pxe.id_rsa.pub
	touch $@

test-virt-p2v-pxe.img: \
	    dependencies.m4 \
	    issue \
	    launch-virt-p2v \
	    p2v.service \
	    test-virt-p2v-pxe.id_rsa \
	    virt-p2v \
	    virt-p2v-make-disk
	$(top_builddir)/run virt-p2v-make-disk \
	    --inject-ssh-identity=test-virt-p2v-pxe.id_rsa \
	    -o $@-t
	mv $@-t $@

test-virt-p2v-pxe.vmlinuz test-virt-p2v-pxe.initramfs: stamp-test-virt-p2v-pxe-kernel

stamp-test-virt-p2v-pxe-kernel: test-virt-p2v-pxe.img
	rm -f $@ vmlinuz initramfs test-virt-p2v-pxe.vmlinuz test-virt-p2v-pxe.initramfs
	$(top_builddir)/run virt-get-kernel --unversioned-names -a $<
	mv vmlinuz test-virt-p2v-pxe.vmlinuz
	mv initramfs test-virt-p2v-pxe.initramfs
	touch $@

test-virt-p2v-pxe.sshd_config: test-virt-p2v-pxe.sshd_config.in
	rm -f $@ $@-t
	@AWK@ \
	  -v "abs_builddir=$(abs_builddir)" \
	  '{ \
	    gsub (/__RANDOM_PORT__/, 10000 + int (1000 * rand())); \
	    gsub (/__abs_builddir__/, abs_builddir); \
	    print; \
	  }' < $< > $@-t
	chmod 0444 $@-t
	mv $@-t $@

test-virt-p2v-pxe.authorized_keys: test-virt-p2v-pxe.id_rsa.pub $(top_builddir)/run
	rm -f $@ $@-t
	$(top_builddir)/run sh -c 'echo -n environment=\"PATH=$$PATH\",environment=\"LD_LIBRARY_PATH=$(abs_top_builddir)/lib/.libs\",environment=\"LIBGUESTFS_PATH=$(abs_top_builddir)/appliance\",environment=\"LIBGUESTFS_CACHEDIR=$(abs_top_builddir)/tmp\"\ ' > $@-t
	cat $< >> $@-t
	mv $@-t $@

test-virt-p2v-pxe.ssh_host_rsa_key test-virt-p2v-pxe.ssh_host_rsa_key.pub: stamp-test-virt-p2v-pxe-hostkey

stamp-test-virt-p2v-pxe-hostkey:
	rm -f test-virt-p2v-pxe.ssh_host_rsa_key
	rm -f test-virt-p2v-pxe.ssh_host_rsa_key.pub
	ssh-keygen -t rsa -f test-virt-p2v-pxe.ssh_host_rsa_key -N ''
	touch $@

test-virt-p2v-pxe.id_rsa test-virt-p2v-pxe.id_rsa.pub: stamp-test-virt-p2v-pxe-userkey

stamp-test-virt-p2v-pxe-userkey:
	rm -f test-virt-p2v-pxe.id_rsa
	rm -f test-virt-p2v-pxe.id_rsa.pub
	ssh-keygen -t rsa -f test-virt-p2v-pxe.id_rsa -N ''
	touch $@
