# libguestfs virt-p2v
# Copyright (C) 2009-2016 Red Hat Inc.
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
	HACKING \
	$(TESTS) $(SLOW_TESTS) \
	dependencies.m4 \
	issue \
	launch-virt-p2v.in \
	p2v.ks.in \
	p2v.service \
	test-virt-p2v-pxe.sshd_config.in \
	test-virt-p2v-scp.sh \
	test-virt-p2v-ssh.sh \
	virt-p2v.pod \
	virt-p2v-make-disk.in \
	virt-p2v-make-disk.pod \
	virt-p2v-make-kickstart.in \
	virt-p2v-make-kickstart.pod

# Don't clean ssh_host_rsa_key{,.pub} or id_rsa{,.pub} since those
# consume system entropy to regenerate.
CLEANFILES = \
	$(dependencies_files) \
	stamp-test-virt-p2v-pxe-kernel \
	stamp-virt-p2v.pod \
	stamp-virt-p2v-make-disk.pod \
	stamp-virt-p2v-make-kickstart.pod \
	test-virt-p2v-pxe.authorized_keys \
	test-virt-p2v-pxe.img \
	test-virt-p2v-pxe.vmlinuz \
	test-virt-p2v-pxe.initramfs \
	test-virt-p2v-pxe.sshd_config \
	virt-p2v.1 \
	virt-p2v-make-disk.1 \
	virt-p2v-make-kickstart.1

# Although virt-p2v is a regular binary, it is not usually installed
# in /usr/bin since it only functions when contained in an ISO or PXE
# image which is used to boot the physical machine (since otherwise
# virt-p2v would not be able to get a consistent snapshot of the
# physical disks).
libexec_PROGRAMS = virt-p2v

# Note that miniexpect comes from here:
# http://git.annexia.org/?p=miniexpect.git;a=summary
virt_p2v_SOURCES = \
	about-authors.c \
	about-license.c \
	config.c \
	conversion.c \
	gui.c \
	kernel.c \
	kernel-cmdline.c \
	main.c \
	miniexpect.c \
	miniexpect.h \
	p2v.h \
	ssh.c \
	utils.c \
	whole-file.c

virt_p2v_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_p2v_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(GTK2_CFLAGS)

virt_p2v_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(PCRE_LIBS) \
	$(LIBXML2_LIBS) \
	$(GTK2_LIBS) \
	../gnulib/lib/libgnu.la

# Scripts to build the disk image, USB key, or kickstart.
bin_SCRIPTS = virt-p2v-make-disk virt-p2v-make-kickstart

dependencies_files = \
	dependencies.archlinux \
	dependencies.debian \
	dependencies.redhat \
	dependencies.suse

$(dependencies_files): dependencies.m4
	define=`echo $@ | $(SED) 's/dependencies.//;y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/'`; \
	m4 -D$$define=1 $< > $@-t
	mv $@-t $@

# Support files needed by the virt-p2v-make-* scripts.
virtp2vdatadir = $(datadir)/virt-p2v

virtp2vdata_DATA = \
	$(dependencies_files) \
	issue \
	launch-virt-p2v \
	p2v.ks.in \
	p2v.service

# Deal with stupid autotools libexecdir-not-expandable crap.
launch-virt-p2v: launch-virt-p2v.in
	rm -f $@ $@-t
	$(SED) 's,@''libexecdir@,$(libexecdir),g' < $< > $@-t
	chmod 0555 $@-t
	mv $@-t $@

# Manual pages and HTML files for the website.
man_MANS = \
	virt-p2v.1 \
	virt-p2v-make-disk.1 \
	virt-p2v-make-kickstart.1

noinst_DATA = \
	$(top_builddir)/website/virt-p2v.1.html \
	$(top_builddir)/website/virt-p2v-make-disk.1.html \
	$(top_builddir)/website/virt-p2v-make-kickstart.1.html

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

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-p2v-cmdline.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-p2v.sh \
	$(SLOW_TESTS)
endif ENABLE_APPLIANCE

SLOW_TESTS = \
	test-virt-p2v-pxe.sh

check-slow: test-virt-p2v-pxe.img \
	    test-virt-p2v-pxe.authorized_keys \
	    test-virt-p2v-pxe.vmlinuz test-virt-p2v-pxe.initramfs \
	    test-virt-p2v-pxe.sshd_config \
	    test-virt-p2v-pxe.ssh_host_rsa_key \
	    test-virt-p2v-pxe.ssh_host_rsa_key.pub \
	    test-virt-p2v-pxe.id_rsa test-virt-p2v-pxe.id_rsa.pub
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

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
	$(top_builddir)/run sh -c 'echo -n environment=\"PATH=$$PATH\",environment=\"LD_LIBRARY_PATH=$(abs_top_builddir)/src/.libs\"\ ' > $@-t
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
